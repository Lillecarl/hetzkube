import ipaddress
import logging
from typing import List

from asyncio import Event
from kr8s.asyncio.objects import Node

from . import config
from .kr8s_objects import CiliumLoadBalancerIPPool, DNSEndpoint

logger = logging.getLogger(__name__)


class ExternalResourcesUpdater:
    """Handles updates to external resources like CiliumLoadbalancerIPPool and external-dns DNSEndpoint."""

    event: Event

    def __init__(self, event: Event):
        self.event = event

    async def _collect_addresses(self, nodes: List[Node]) -> tuple:
        """Collects service subnets and control plane addresses from nodes."""
        service_subnets = []
        cp_addresses4 = []
        cp_addresses6 = []

        for node in nodes:
            for addr in node.status.addresses:
                if addr.type == "ExternalIP":
                    try:
                        ip = ipaddress.ip_address(addr.address)
                        if ip.version == 4:
                            service_subnets.append(f"{ip}/32")
                            if "node-role.kubernetes.io/control-plane" in node.metadata.get("labels", {}):
                                cp_addresses4.append(addr.address)
                        elif ip.version == 6:
                            ipv6_net = ipaddress.ip_network(f"{ip}/{config.IPV6_SERVICE_PREFIX}", strict=False)
                            supernet = ipv6_net.supernet()
                            subnets = list(supernet.subnets())
                            service_subnets.append(str(subnets[1]))
                            if "node-role.kubernetes.io/control-plane" in node.metadata.get("labels", {}):
                                cp_addresses6.append(addr.address)
                    except ValueError:
                        logger.warning(f"Skipping invalid IP address: {addr.address}")

        return service_subnets, cp_addresses4, cp_addresses6

    async def _update_ip_address_pool(self, service_subnets: List[str]) -> None:
        """Creates or patches the LoadBalancer CiliumLoadbalancerIPPool."""
        if not service_subnets:
            logger.warning("No ExternalIPs found. CiliumLoadbalancerIPPool will not be modified.")
            return

        ippool_spec = {
            "metadata": {"name": config.POOL_NAME},
            "spec": {"blocks": [{"cidr": cidr} for cidr in sorted(list(set(service_subnets)))]},
        }
        ippool = await CiliumLoadBalancerIPPool(ippool_spec)
        try:
            if await ippool.exists():
                await ippool.patch(ippool_spec)
                logger.info(f"Patched {ippool.kind} '{ippool.name}'")
            else:
                await ippool.create()
                logger.info(f"Created {ippool.kind} '{ippool.name}'")
        except Exception as e:
            logger.error(f"An error occurred updating CiliumLoadbalancerIPPool: {e}")
            logger.error(f"{ippool_spec=}")
            self.event.set()

    async def _update_dns_endpoint(self, cp_addresses4: List[str], cp_addresses6: List[str], cluster_hostname: str) -> None:
        """Creates or patches the external-dns DNSEndpoint."""
        if not cp_addresses4 and not cp_addresses6:
            return

        endpoints = []
        if cp_addresses4:
            endpoints.append({"dnsName": cluster_hostname, "recordTTL": 60, "recordType": "A", "targets": sorted(list(set(cp_addresses4)))})
        if cp_addresses6:
            endpoints.append({"dnsName": cluster_hostname, "recordTTL": 60, "recordType": "AAAA", "targets": sorted(list(set(cp_addresses6)))})

        dnsendpoint_spec = {"metadata": {"name": config.DNSENDPOINT_NAME}, "spec": {"endpoints": endpoints}}
        dnsendpoint = await DNSEndpoint(dnsendpoint_spec, "kube-system")
        try:
            if await dnsendpoint.exists():
                await dnsendpoint.patch(dnsendpoint_spec)
                logger.info(f"Patched {dnsendpoint.kind} '{dnsendpoint.name}'")
            else:
                await dnsendpoint.create()
                logger.info(f"Created {dnsendpoint.kind} '{dnsendpoint.name}'")
        except Exception as e:
            logger.error(f"An error occurred updating DNSEndpoint: {e}")
            logger.error(f"{dnsendpoint_spec=}")
            self.event.set()

    async def update(self, nodes: List[Node], cluster_hostname: str) -> None:
        """
        Creates/patches CiliumLoadbalancerIPPool and external-dns DNSEndpoint.

        Args:
            nodes: List of current Node objects.
            cluster_hostname: The cluster's hostname.
        """
        logger.info("--- Starting external resource update ---")

        service_subnets, cp_addresses4, cp_addresses6 = await self._collect_addresses(nodes)
        await self._update_ip_address_pool(service_subnets)
        await self._update_dns_endpoint(cp_addresses4, cp_addresses6, cluster_hostname)

        logger.info("--- Finished external resource update ---")


async def update_external_resources(nodes: List[Node], cluster_hostname: str, event: Event) -> None:
    """Legacy entry point for external resource updates."""
    updater = ExternalResourcesUpdater(event)
    await updater.update(nodes, cluster_hostname)
