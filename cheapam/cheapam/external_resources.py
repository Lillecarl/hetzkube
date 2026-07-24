import ipaddress
import logging
from typing import List

from asyncio import Event
from kr8s.asyncio.objects import Node

from . import config
from .kr8s_objects import DNSEndpoint

logger = logging.getLogger(__name__)


def _node_dns_name(node_name: str, cluster_hostname: str) -> str:
    """Build a DNS name for an individual node.

    For a node named "hetzkube-worker-x86-abc" and cluster "kubernetes.lillecarl.com",
    returns "hetzkube-worker-x86-abc.lillecarl.com".
    """
    domain = ".".join(cluster_hostname.split(".", 1)[1:])
    return f"{node_name}.{domain}"


class ExternalResourcesUpdater:
    """Handles updates to external resources like external-dns DNSEndpoint."""

    event: Event

    def __init__(self, event: Event):
        self.event = event

    async def _collect_addresses(self, nodes: List[Node]) -> tuple:
        """Collects control plane addresses from nodes."""
        cp_addresses4 = []
        cp_addresses6 = []

        for node in nodes:
            for addr in node.status.addresses:
                if addr.type == "ExternalIP":
                    try:
                        ip = ipaddress.ip_address(addr.address)
                        if ip.version == 4:
                            if "node-role.kubernetes.io/control-plane" in node.metadata.get("labels", {}):
                                cp_addresses4.append(addr.address)
                        elif ip.version == 6:
                            if "node-role.kubernetes.io/control-plane" in node.metadata.get("labels", {}):
                                cp_addresses6.append(addr.address)
                    except ValueError:
                        logger.warning(f"Skipping invalid IP address: {addr.address}")

        return cp_addresses4, cp_addresses6

    async def _update_dns_endpoint(self, cp_addresses4: List[str], cp_addresses6: List[str], cluster_hostname: str) -> None:
        """Creates or patches the external-dns DNSEndpoint for the cluster hostname."""
        endpoints = []
        if cp_addresses4:
            endpoints.append({"dnsName": cluster_hostname, "recordTTL": 60, "recordType": "A", "targets": sorted(list(set(cp_addresses4)))})
        if cp_addresses6:
            endpoints.append({"dnsName": cluster_hostname, "recordTTL": 60, "recordType": "AAAA", "targets": sorted(list(set(cp_addresses6)))})

        if not endpoints:
            return

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

    async def _update_node_dns(self, nodes: List[Node], cluster_hostname: str) -> None:
        """Creates one DNSEndpoint per node, owned by that node so GC cleans it up on delete."""
        for node in nodes:
            v4_targets = []
            v6_targets = []
            for addr in node.status.addresses:
                if addr.type != "ExternalIP":
                    continue
                try:
                    ip = ipaddress.ip_address(addr.address)
                except ValueError:
                    continue
                if ip.version == 4:
                    v4_targets.append(addr.address)
                elif ip.version == 6:
                    v6_targets.append(addr.address)

            dns_name = _node_dns_name(node.name, cluster_hostname)

            endpoints = []
            if v4_targets:
                endpoints.append({"dnsName": dns_name, "recordTTL": 60, "recordType": "A", "targets": sorted(v4_targets)})
            if v6_targets:
                endpoints.append({"dnsName": dns_name, "recordTTL": 60, "recordType": "AAAA", "targets": sorted(v6_targets)})

            dnsendpoint_spec = {
                "metadata": {
                    "name": node.name,
                    "ownerReferences": [{
                        "apiVersion": "v1",
                        "kind": "Node",
                        "name": node.name,
                        "uid": node.metadata.uid,
                    }],
                },
                "spec": {"endpoints": endpoints},
            }

            dnsendpoint = await DNSEndpoint(dnsendpoint_spec, "kube-system")
            try:
                if await dnsendpoint.exists():
                    await dnsendpoint.patch(dnsendpoint_spec)
                else:
                    await dnsendpoint.create()
            except Exception as e:
                logger.error(f"An error occurred updating node DNS for '{node.name}': {e}")
                self.event.set()

    async def update(self, nodes: List[Node], cluster_hostname: str) -> None:
        """
        Creates/patches external-dns DNSEndpoints for cluster and nodes.

        Args:
            nodes: List of current Node objects.
            cluster_hostname: The cluster's hostname.
        """
        logger.info("--- Starting external resource update ---")

        cp_addresses4, cp_addresses6 = await self._collect_addresses(nodes)
        await self._update_dns_endpoint(cp_addresses4, cp_addresses6, cluster_hostname)
        await self._update_node_dns(nodes, cluster_hostname)

        logger.info("--- Finished external resource update ---")


async def update_external_resources(nodes: List[Node], cluster_hostname: str, event: Event) -> None:
    """Legacy entry point for external resource updates."""
    updater = ExternalResourcesUpdater(event)
    await updater.update(nodes, cluster_hostname)
