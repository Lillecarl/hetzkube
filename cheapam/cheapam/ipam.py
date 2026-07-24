import ipaddress
import logging
from asyncio import Event
from typing import Iterator, List, Optional, cast

import kr8s
from kr8s.asyncio.objects import ConfigMap, Node

from . import config
from . import hetzner

logger = logging.getLogger(__name__)


class IPAMReconciler:
    """Handles IPAM reconciliation, including node initialization and podCIDR allocation."""

    ipv4_pool: ipaddress.IPv4Network
    state_cm: ConfigMap
    reconciliation_event: Event

    def __init__(self, ipv4_pool: ipaddress.IPv4Network, state_cm: ConfigMap, event: Event):
        self.ipv4_pool = ipv4_pool
        self.state_cm = state_cm
        self.event = event

    @classmethod
    async def create(cls, event: Event) -> "IPAMReconciler":
        """
        Asynchronous factory method to create and initialize an IPAMReconciler instance.
        """
        ipv4_pool = await cls._load_ipv4_pool()
        state_cm = await cls._load_or_create_state_cm()
        return cls(ipv4_pool, state_cm, event)

    @staticmethod
    async def _load_ipv4_pool() -> ipaddress.IPv4Network:
        """Loads the IPv4 pool from the config ConfigMap."""
        try:
            config_cm = await ConfigMap.get(config.IPAM_CONFIG_MAP, config.IPAM_NAMESPACE)
            ipv4_pool_str = config_cm.data.get(config.IPAM_CONFIG_KEY_V4)
            if not ipv4_pool_str:
                raise ValueError(f"ConfigMap '{config.IPAM_CONFIG_MAP}' is missing required key '{config.IPAM_CONFIG_KEY_V4}'.")
            return cast(ipaddress.IPv4Network, ipaddress.ip_network(ipv4_pool_str))
        except kr8s.NotFoundError:
            raise ValueError(f"Required ConfigMap '{config.IPAM_CONFIG_MAP}' not found in namespace '{config.IPAM_NAMESPACE}'.")
        except Exception as e:
            logger.error(f"Error loading IPAM config: {e}")
            raise

    @staticmethod
    async def _load_or_create_state_cm() -> ConfigMap:
        """Loads or creates the state ConfigMap."""
        state_cm_spec = {"metadata": {"name": config.IPAM_STATE_MAP}, "data": {"placeholder": "10.13.37.0/24"}}
        try:
            state_cm = await ConfigMap.get(config.IPAM_STATE_MAP, namespace=config.IPAM_NAMESPACE)
            logger.info(f"Fetched IPAM state ConfigMap '{config.IPAM_STATE_MAP}'")
            return state_cm
        except kr8s.NotFoundError:
            state_cm = await ConfigMap(state_cm_spec, namespace=config.IPAM_NAMESPACE)
            await state_cm.create()
            logger.info(f"Created IPAM state ConfigMap '{config.IPAM_STATE_MAP}'")
            return state_cm

    async def _initialize_node(self, node: Node) -> None:
        """Initializes an uninitialized node by setting providerID, addresses, and removing taints."""
        uninitialized_taint = any(
            taint.get("key") == "node.cloudprovider.kubernetes.io/uninitialized"
            for taint in node.spec.get("taints", [])
        )

        if uninitialized_taint or not node.spec.get("providerID"):
            logger.info(f"Node '{node.name}' is uninitialized. Fetching details from Hetzner.")
            server = await hetzner.get_server_details(node.name)
            if server:
                try:
                    provider_id = f"hcloud://{server.id}"

                    assert server.public_net is not None
                    assert server.public_net.ipv4 is not None
                    assert server.public_net.ipv4.ip is not None

                    # Construct addresses
                    addresses = [
                        {"type": "ExternalIP", "address": str(server.public_net.ipv4.ip)},
                        {"type": "InternalIP", "address": str(server.public_net.ipv4.ip)},
                        {"type": "Hostname", "address": node.name},
                    ]
                    if server.public_net.ipv6:
                        # The API returns a subnet like "2a01:4f9:c012:7d72::/64".
                        # We parse it and take the first available host IP (e.g., ...::1).
                        ipv6_subnet = ipaddress.IPv6Network(ipaddress.ip_network(server.public_net.ipv6.ip))
                        hosts = cast(Iterator[ipaddress.IPv6Address],ipv6_subnet.hosts())
                        first_host_ipv6: ipaddress.IPv6Address = next(hosts)
                        addresses.append({"type": "ExternalIP", "address": str(first_host_ipv6)})

                    # Patch providerID
                    logger.info(f"Setting providerID for node '{node.name}' to '{provider_id}'")
                    await node.patch({"spec": {"providerID": provider_id}})

                    # Patch addresses
                    logger.info(f"Setting addresses for node '{node.name}'")
                    await node.patch({"status": {"addresses": addresses}}, subresource="status")

                    # Remove the uninitialized taint
                    logger.info(f"Removing uninitialized taint from node '{node.name}'")
                    taints = [
                        taint for taint in node.spec.get("taints", [])
                        if taint.get("key") != "node.cloudprovider.kubernetes.io/uninitialized"
                    ]
                    await node.patch({"spec": {"taints": taints}})
                except Exception as e:
                    logger.error(e)
                    self.event.set()
            else:
                logger.error(f"Could not initialize node '{node.name}', server details not found.")
                return  # Skip to next node if we can't find it in Hetzner

    async def _import_existing_pod_cidrs(self, nodes: List[Node]) -> None:
        """Imports existing podCIDRs from nodes into the state ConfigMap."""
        for node in nodes:
            if pod_cidr := node.spec.get("podCIDR"):
                if self.state_cm.data.get(node.name) != pod_cidr:
                    logger.info(f"Discovered existing IPv4 CIDR '{pod_cidr}' on node '{node.name}'. Importing to state.")
                    self.state_cm.data[node.name] = pod_cidr

    async def _reclaim_deleted_nodes(self, current_nodes: set) -> None:
        """Reclaims CIDRs for deleted nodes."""
        for node_name in list(self.state_cm.data.keys()):
            if node_name not in current_nodes:
                logger.info(f"Node '{node_name}' deleted. Reclaiming its IPv4 CIDR.")
                self.state_cm.data[node_name] = None

    async def _allocate_pod_cidrs(self, nodes: List[Node]) -> None:
        """Allocates new podCIDRs for nodes that don't have them."""
        allocated_ipv4_subnets = {cidr for cidr in self.state_cm.data.values() if cidr}
        available_ipv4_subnets = iter(self.ipv4_pool.subnets(new_prefix=config.IPV4_PREFIX))

        for node in nodes:
            if node.spec.get("podCIDR"):
                continue

            desired_v4: Optional[str] = None
            desired_v6: Optional[str] = None

            node_ipv6 = None
            for addr in node.status.addresses:
                if addr.type == "ExternalIP":
                    ip = ipaddress.ip_address(addr.address)
                    if ip.version == 6:
                        node_ipv6 = ip
                        break

            if node_ipv6:
                ipv6_net = ipaddress.ip_network(f"{node_ipv6}/{config.IPV6_PREFIX}", strict=False)
                pod_ipv6_cidr = list(ipv6_net.subnets(prefixlen_diff=1))[1]
                desired_v6 = str(pod_ipv6_cidr)

            while (subnet := str(next(available_ipv4_subnets))) in allocated_ipv4_subnets:
                continue
            logger.info(f"Allocating new IPv4 CIDR '{subnet}' to node '{node.name}'")
            self.state_cm.data[node.name] = subnet
            allocated_ipv4_subnets.add(subnet)
            desired_v4 = subnet

            patch = {"spec": {"podCIDR": desired_v4, "podCIDRs": [desired_v4, desired_v6]}}
            logger.info(f"Patching node '{node.name}' with podCIDRs: {desired_v4=},{desired_v6=}")
            await node.patch(patch)

    async def reconcile(self, nodes: List[Node]) -> None:
        """
        Manages node initialization (providerID, IPs) and podCIDR allocations.

        Args:
            nodes: List of current Node objects.
        """
        logger.info("--- Starting IPAM reconciliation ---")

        current_nodes = {node.name for node in nodes}

        await self._reclaim_deleted_nodes(current_nodes)

        for node in nodes:
            await self._initialize_node(node)

        await self._import_existing_pod_cidrs(nodes)
        await self._allocate_pod_cidrs(nodes)

        logger.info(f"Updating IPAM state in ConfigMap '{config.IPAM_STATE_MAP}'")
        await self.state_cm.patch({"data": self.state_cm.data})
        logger.info("--- Finished IPAM reconciliation ---")


async def reconcile_ipam(nodes: List[Node], event: Event) -> None:
    """Legacy entry point for IPAM reconciliation."""
    reconciler = await IPAMReconciler.create(event)
    await reconciler.reconcile(nodes)
