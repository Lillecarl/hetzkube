"""LoadBalancer service IP assignment.

Replaces MetalLB controller for assigning external IPs to LoadBalancer services.
Assigns node external IPs with full port-based IP sharing between services.

IPv4: assigned from a node's single external IP (shared across all services).
IPv6: assigned from the second half of the node's /64 subnet (free-for-all).

Port 22 (SSH) services are never assigned — they must stay node-accessible.
"""

import ipaddress
import logging
from asyncio import Event
from typing import Dict, List, Optional, Set, Tuple, cast

from kr8s.asyncio.objects import Node, Service

from . import config

logger = logging.getLogger(__name__)

# Annotation cheapam uses to track its assignments
ANNOTATION_ASSIGNED_IPS = "cheapam.io/loadbalancer-ips"

# IPv6: second half of the node's /64 subnet
IPV6_SERVICE_SUBNET_OFFSET = 2

# kr8s doesn't have a built-in Service class that supports status patching,
# so we define the minimal patch helpers inline.


def _ports_key(svc: dict) -> Set[Tuple[str, int]]:
    """Extract (protocol, port) tuples from a service spec.

    These are always resolved to numeric values by Kubernetes.
    """
    ports: Set[Tuple[str, int]] = set()
    for p in svc.get("spec", {}).get("ports", []):
        ports.add((p.get("protocol", "TCP"), p["port"]))
    return ports


def _sharing_key(svc: dict) -> str:
    """Unique per-service key so port conflicts are enforced.

    Two services on the same IP must have non-overlapping (protocol, port)
    tuples.  This means any two services can share an IP as long as they
    don't compete for the same port.
    """
    return svc.get("metadata", {}).get("uid", "")


def _is_lb(svc: dict) -> bool:
    return svc.get("spec", {}).get("type") == "LoadBalancer"


def _has_port_22(svc: dict) -> bool:
    return any(p.get("port") == 22 for p in svc.get("spec", {}).get("ports", []))


def _get_assigned_ips(svc: dict) -> List[str]:
    ingress = svc.get("status", {}).get("loadBalancer", {}).get("ingress", [])
    return [entry["ip"] for entry in ingress if entry.get("ip")]


def _assigned_ip_str(svc: dict) -> Optional[str]:
    """Return the cheapam-assigned IP string from annotation, if any."""
    ann = svc.get("metadata", {}).get("annotations", {})
    return ann.get(ANNOTATION_ASSIGNED_IPS)


class IpShareState:
    """Tracks which services are assigned to which IPs, for conflict detection."""

    def __init__(self):
        # ip -> {sharing_key -> {(protocol, port), ...}}
        self._ip_ports: Dict[str, Dict[str, Set[Tuple[str, int]]]] = {}

    def assign(self, ip: str, sharing_key: str, ports: Set[Tuple[str, int]]):
        """Record an IP assignment for a service."""
        if ip not in self._ip_ports:
            self._ip_ports[ip] = {}
        if sharing_key not in self._ip_ports[ip]:
            self._ip_ports[ip][sharing_key] = set()
        self._ip_ports[ip][sharing_key].update(ports)

    def unassign(self, ip: str, sharing_key: str, ports: Set[Tuple[str, int]]):
        """Remove an IP assignment for a service."""
        if ip in self._ip_ports and sharing_key in self._ip_ports[ip]:
            self._ip_ports[ip][sharing_key] -= ports
            if not self._ip_ports[ip][sharing_key]:
                del self._ip_ports[ip][sharing_key]
            if not self._ip_ports[ip]:
                del self._ip_ports[ip]

    def is_conflict(self, ip: str, sharing_key: str, ports: Set[Tuple[str, int]]) -> bool:
        """Check if assigning these ports to this IP would conflict.

        Two services sharing an IP can't have overlapping (protocol, port) tuples.
        """
        if ip not in self._ip_ports:
            return False
        for other_key, other_ports in self._ip_ports[ip].items():
            if other_key == sharing_key:
                continue
            if ports & other_ports:
                return True
        return False


def _collect_node_addresses(nodes: List[dict]) -> Tuple[List[str], List[str]]:
    """Collect IPv4 and IPv6 external addresses from nodes.

    Returns:
        (ipv4_addresses, ipv6_service_addresses)
    """
    v4: List[str] = []
    v6: List[str] = []
    for node in nodes:
        for addr in node.get("status", {}).get("addresses", []):
            if addr.get("type") != "ExternalIP":
                continue
            try:
                ip = ipaddress.ip_address(addr["address"])
            except ValueError:
                continue
            if ip.version == 4:
                v4.append(str(ip))
            elif ip.version == 6:
                # Use second half of the /64 for services — first usable host
                net = ipaddress.IPv6Network(f"{ip}/64", strict=False)
                service_subnets = list(net.subnets(prefixlen_diff=1))
                if len(service_subnets) >= 2:
                    v6.append(str(next(service_subnets[1].hosts())))
    return v4, v6


async def _patch_lb_status(name: str, namespace: str, ips: List[str], pool_name: str) -> None:
    """Patch a service's LoadBalancer status and annotations with assigned IPs."""
    ingress = [{"ip": ip} for ip in ips]
    svc = await Service.get(name, namespace=namespace)
    # Patch status via status subresource
    await svc.patch({
        "status": {"loadBalancer": {"ingress": ingress}},
    }, subresource="status")
    # Patch annotations via main resource
    await svc.patch({
        "metadata": {
            "annotations": {
                ANNOTATION_ASSIGNED_IPS: ",".join(ips),
                "cheapam.io/ip-allocated-from-pool": pool_name,
            },
        },
    })


async def _clear_lb_status(name: str, namespace: str) -> None:
    """Clear LoadBalancer status and cheapam annotations on a service."""
    svc = await Service.get(name, namespace=namespace)
    # Clear status via status subresource
    await svc.patch({
        "status": {"loadBalancer": {"ingress": []}},
    }, subresource="status")
    # Clear annotations via main resource
    await svc.patch({
        "metadata": {
            "annotations": {
                ANNOTATION_ASSIGNED_IPS: None,
                "cheapam.io/ip-allocated-from-pool": None,
            },
        },
    })


async def reconcile_lb_services(services: List[dict], nodes: List[dict]) -> None:
    """Reconcile all LoadBalancer services against current node addresses.

    Called during each reconciliation cycle.  Idempotent.
    """
    logger.info(f"Reconciling {len(services)} services, {len(nodes)} nodes")
    v4_addrs, v6_subnets = _collect_node_addresses(nodes)
    logger.info(f"Node addresses: {len(v4_addrs)} IPv4, {len(v6_subnets)} IPv6 subnets")

    state = IpShareState()

    # Pre-populate state from all existing LB ingress IPs, not just cheapam-assigned ones.
    # This prevents port conflicts with services managed by other controllers (cilium gateway, etc.)
    populated = 0
    for svc in services:
        current_ips = _get_assigned_ips(svc)
        if current_ips:
            populated += 1
            svc_name = svc.get("metadata", {}).get("name", "?")
            svc_ns = svc.get("metadata", {}).get("namespace", "?")
            logger.debug(f"Pre-populated state for {svc_ns}/{svc_name}: IPs={current_ips} ports={_ports_key(svc)}")
            for ip in current_ips:
                state.assign(ip, _sharing_key(svc), _ports_key(svc))
    logger.info(f"Pre-populated state from {populated} services with LB ingress IPs")

    for svc_raw in services:
        svc_name = svc_raw["metadata"]["name"]
        svc_ns = svc_raw["metadata"]["namespace"]
        key = f"{svc_ns}/{svc_name}"

        if not _is_lb(svc_raw):
            # Was it previously assigned by us?  Clean up.
            if _assigned_ip_str(svc_raw):
                assigned = _assigned_ip_str(svc_raw)
                logger.info(f"Clearing LB status for non-LB service '{key}'")
                for ip in assigned.split(","):
                    state.unassign(ip, _sharing_key(svc_raw), _ports_key(svc_raw))
                await _clear_lb_status(svc_name, svc_ns)
            continue

        if _has_port_22(svc_raw):
            logger.warning(f"Service '{key}' exposes port 22 — skipping IP assignment")
            if _get_assigned_ips(svc_raw):
                await _clear_lb_status(svc_name, svc_ns)
            continue

        current_ips = _get_assigned_ips(svc_raw)
        ports = _ports_key(svc_raw)
        sharing_key = _sharing_key(svc_raw)

        # If the service already has IPs and they're still valid, skip.
        if current_ips:
            still_valid = True
            for ip in current_ips:
                if state.is_conflict(ip, sharing_key, ports):
                    still_valid = False
                    break
                # Re-affirm the assignment so the conflict tracker accounts
                # for any port changes.
                state.assign(ip, sharing_key, ports)

            if still_valid:
                # Update annotation if it's missing
                if not _assigned_ip_str(svc_raw):
                    await _patch_lb_status(svc_name, svc_ns, current_ips, config.POOL_NAME)
                continue

            # Existing IPs no longer valid, clear and re-assign
            logger.info(f"Current IPs for '{key}' no longer valid, reassigning")
            for ip in current_ips:
                state.unassign(ip, sharing_key, ports)
            await _clear_lb_status(svc_name, svc_ns)
            current_ips = []

        # Need to assign an IP.  Try IPv4 first, then IPv6 if available.
        assigned_ips = []
        for candidate_pool, pool_name in [(v4_addrs, "ipv4-node"), (v6_subnets, "ipv6-service")]:
            if not candidate_pool:
                continue
            # Find the first address that doesn't conflict
            for addr in candidate_pool:
                conflict = state.is_conflict(addr, sharing_key, ports)
                logger.debug(f"  Trying {addr} for '{key}': conflict={conflict}")
                if not conflict:
                    assigned_ips.append(addr)
                    state.assign(addr, sharing_key, ports)
                    break

        if assigned_ips:
            logger.info(f"Assigned IP(s) {assigned_ips} to service '{key}'")
            await _patch_lb_status(svc_name, svc_ns, assigned_ips, config.POOL_NAME)
        else:
            logger.warning(f"No available IP for service '{key}'")
