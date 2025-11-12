#! /usr/bin/env python3
import asyncio
import ipaddress
import kr8s
import sys
import yaml
from typing import cast
from urllib.parse import urlparse
from kr8s.asyncio.objects import new_class, ConfigMap, Node

# --- Configuration ---
# MetalLB / external-dns
POOL_NAME = "external-ips"
DNSENDPOINT_NAME = "apiservers"

# cheapam IPAM
IPAM_CONFIG_MAP = "cheapam-config"
IPAM_STATE_MAP = "cheapam-state"
IPAM_CONFIG_KEY_V4 = "IPv4"
IPAM_NAMESPACE = "kube-system"
IPV4_PREFIX = 24
IPV6_PREFIX = 64
DEBOUNCE_DELAY_SECONDS = 2.0

# --- Kubernetes API Object Definitions ---
IPAddressPool = new_class(
    kind="IPAddressPool",
    version="metallb.io/v1beta1",
    namespaced=True,
    plural="ipaddresspools",
)

DNSEndpoint = new_class(
    kind="DNSEndpoint",
    version="externaldns.k8s.io/v1alpha1",
    namespaced=True,
    plural="dnsendpoints",
)


async def get_cluster_hostname() -> str:
    """Retrieves the API server hostname from the cluster-info ConfigMap."""
    cluster_info = await ConfigMap.get("cluster-info", "kube-public")
    kubeconfig_data = yaml.safe_load(cluster_info.data["kubeconfig"])
    server_url = kubeconfig_data["clusters"][0]["cluster"]["server"]
    return urlparse(server_url).hostname


async def reconcile_ipam(nodes: list[Node]):
    """Manages node podCIDR allocations."""
    print("--- Starting IPAM reconciliation ---")
    try:
        config_cm = await ConfigMap.get(IPAM_CONFIG_MAP, IPAM_NAMESPACE)
        ipv4_pool_str = config_cm.data.get(IPAM_CONFIG_KEY_V4)
        if not ipv4_pool_str:
            print(
                f"Error: ConfigMap '{IPAM_CONFIG_MAP}' is missing required key '{IPAM_CONFIG_KEY_V4}'. Exiting.",
                file=sys.stderr,
            )
            raise SystemExit(1)
        ipv4_pool = ipaddress.ip_network(ipv4_pool_str)
    except kr8s.NotFoundError:
        print(
            f"Error: Required ConfigMap '{IPAM_CONFIG_MAP}' not found in namespace '{IPAM_NAMESPACE}'. Exiting.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    state_cm_spec = {
        "metadata": {"name": IPAM_STATE_MAP},
        "data": {"placeholder": "10.13.37.0/24"},
    }
    try:
        state_cm = await ConfigMap.get(IPAM_STATE_MAP, namespace=IPAM_NAMESPACE)
        print(f"Fetched IPAM state ConfigMap '{IPAM_STATE_MAP}'")
    except kr8s.NotFoundError:
        state_cm = await ConfigMap(state_cm_spec, namespace=IPAM_NAMESPACE)
        await state_cm.create()
        print(f"Created IPAM state ConfigMap '{IPAM_STATE_MAP}'")

    current_nodes = {node.name for node in nodes}

    # Reclaim IPs from deleted nodes
    for node_name in list(state_cm.data.keys()):
        if node_name not in current_nodes:
            print(f"Node '{node_name}' deleted. Reclaiming its IPv4 CIDR.")
            state_cm.data[node_name] = None

    # Populate state from existing nodes that already have a podCIDR
    for node in nodes:
        if pod_cidr := node.spec.get("podCIDR"):
            if state_cm.get("data", {}).get(node.name) != pod_cidr:
                print(
                    f"Discovered existing IPv4 CIDR '{pod_cidr}' on node '{node.name}'. Importing to state."
                )
                state_cm.data[node.name] = pod_cidr

    # Allocate IPs for all nodes
    # Filter out None values from reclaimed IPs before creating the set
    allocated_ipv4_subnets = {cidr for cidr in state_cm.data.values() if cidr}
    available_ipv4_subnets = iter(ipv4_pool.subnets(new_prefix=IPV4_PREFIX))

    for node in nodes:
        if node.spec.get("podCIDR"):
            continue

        desired_v4: str | None = None
        desired_v6: str | None = None

        # --- IPv6 Allocation ---
        node_ipv6 = None
        for addr in node.status.addresses:
            if addr.type == "ExternalIP":
                ip = ipaddress.ip_address(addr.address)
                if ip.version == 6:
                    node_ipv6 = ip
                    break

        if node_ipv6:
            # Split the node's /64 into two /65s, use the second for pods
            ipv6_net = ipaddress.ip_network(f"{node_ipv6}/{IPV6_PREFIX}", strict=False)
            pod_ipv6_cidr = list(ipv6_net.subnets(prefixlen_diff=1))[1]
            desired_v6 = str(pod_ipv6_cidr)

        while (subnet := str(next(available_ipv4_subnets))) in allocated_ipv4_subnets:
            continue
        print(f"Allocating new IPv4 CIDR '{subnet}' to node '{node.name}'")
        state_cm.data[node.name] = subnet
        allocated_ipv4_subnets.add(subnet)
        desired_v4 = subnet

        patch = {
            "spec": {
                "podCIDR": desired_v4,
                "podCIDRs": [desired_v4, desired_v6],
            }
        }
        print(f"Patching node '{node.name}' with podCIDRs: {desired_v4=},{desired_v6=}")
        await node.patch(patch)

    # --- Update State ConfigMap ---
    print(f"Updating IPAM state in ConfigMap '{IPAM_STATE_MAP}'")
    await state_cm.patch({"data": state_cm.data})

    print("--- Finished IPAM reconciliation ---")


async def update_external_resources(nodes: list[Node], cluster_hostname: str):
    """Gathers ExternalIPs and creates/patches MetalLB IPAddressPool and external-dns DNSEndpoint."""
    print("--- Starting external resource update ---")
    service_subnets = []
    cp_addresses4 = []
    cp_addresses6 = []

    for node in nodes:
        for addr in node.status.addresses:
            if addr.type == "ExternalIP":
                try:
                    ip = ipaddress.ip_address(addr.address)
                    if ip.version == 4:
                        # Use the /32 for MetalLB
                        service_subnets.append(f"{ip}/32")
                        if "node-role.kubernetes.io/control-plane" in node.metadata.get(
                            "labels", {}
                        ):
                            cp_addresses4.append(addr.address)
                    elif ip.version == 6:
                        # Split the /64, use the *first* /65 for services and
                        # nodes, second goes to pods
                        ipv6_net = ipaddress.ip_network(
                            f"{ip}/{IPV6_PREFIX}", strict=False
                        )
                        subnets = list(ipv6_net.subnets(prefixlen_diff=1))
                        service_subnets.append(str(subnets[0]))
                        if "node-role.kubernetes.io/control-plane" in node.metadata.get(
                            "labels", {}
                        ):
                            cp_addresses6.append(addr.address)
                except ValueError:
                    print(f"Skipping invalid IP address: {addr.address}")

    if not service_subnets:
        print("No ExternalIPs found. IPAddressPool will not be modified.")
        return

    # --- MetalLB IPAddressPool ---
    ippool_spec = {
        "metadata": {"name": POOL_NAME},
        "spec": {"addresses": sorted(list(set(service_subnets)))},
    }
    ippool = await IPAddressPool(ippool_spec, "metallb-system")
    try:
        if await ippool.exists():
            await ippool.patch(ippool_spec)
            print(f"Patched {ippool.kind} '{ippool.name}'")
        else:
            await ippool.create()
            print(f"Created {ippool.kind} '{ippool.name}'")
    except Exception as e:
        print(f"An error occurred updating IPAddressPool: {e}")

    # --- external-dns DNSEndpoint ---
    if cp_addresses4 or cp_addresses6:
        endpoints = []
        if cp_addresses4:
            endpoints.append(
                {
                    "dnsName": cluster_hostname,
                    "recordTTL": 60,
                    "recordType": "A",
                    "targets": sorted(list(set(cp_addresses4))),
                }
            )
        if cp_addresses6:
            endpoints.append(
                {
                    "dnsName": cluster_hostname,
                    "recordTTL": 60,
                    "recordType": "AAAA",
                    "targets": sorted(list(set(cp_addresses6))),
                }
            )

        dnsendpoint_spec = {
            "metadata": {"name": DNSENDPOINT_NAME},
            "spec": {"endpoints": endpoints},
        }
        dnsendpoint = await DNSEndpoint(dnsendpoint_spec, "kube-system")
        try:
            if await dnsendpoint.exists():
                await dnsendpoint.patch(dnsendpoint_spec)
                print(f"Patched {dnsendpoint.kind} '{dnsendpoint.name}'")
            else:
                await dnsendpoint.create()
                print(f"Created {dnsendpoint.kind} '{dnsendpoint.name}'")
        except Exception as e:
            print(f"An error occurred updating DNSEndpoint: {e}")
    print("--- Finished external resource update ---")


async def reconciliation_worker(event: asyncio.Event, cluster_hostname: str):
    """Waits for an event, then triggers a full reconciliation of the cluster state."""
    while True:
        await event.wait()
        print(
            f"Change detected, waiting {DEBOUNCE_DELAY_SECONDS}s for debounce period..."
        )
        await asyncio.sleep(DEBOUNCE_DELAY_SECONDS)
        event.clear()

        print("--- Debounce period over. Starting full reconciliation. ---")
        try:
            all_nodes = [cast(Node, node) async for node in kr8s.asyncio.get("nodes")]
            await reconcile_ipam(all_nodes)
            await update_external_resources(all_nodes, cluster_hostname)
        except Exception as e:
            print(f"Error during reconciliation: {e}", file=sys.stderr)
        print("--- Full reconciliation complete. Awaiting next change. ---")


async def node_watcher(event: asyncio.Event):
    """Watches for node changes and sets an event to trigger reconciliation."""
    while True:
        try:
            async for evt, node in kr8s.asyncio.watch("nodes"):
                if evt not in ["ADDED", "DELETED"]:
                    continue
                print(f"Node '{node.name}' event: '{evt}'. Triggering reconciliation.")
                event.set()
        except Exception as e:
            print(
                f"Error in watch loop: {e}. Reconnecting in 10 seconds.",
                file=sys.stderr,
            )
            await asyncio.sleep(10)


async def main():
    """Sets up and runs the watcher and reconciliation tasks."""
    cluster_hostname = await get_cluster_hostname()
    if cluster_hostname:
        print(f"Operating on cluster: {cluster_hostname}")

    reconciliation_needed = asyncio.Event()

    # Create concurrent tasks for watching and reconciling
    watcher_task = asyncio.create_task(node_watcher(reconciliation_needed))
    worker_task = asyncio.create_task(
        reconciliation_worker(reconciliation_needed, cluster_hostname)
    )

    # Trigger an initial run on startup
    print("Triggering initial reconciliation on startup...")
    reconciliation_needed.set()

    await asyncio.gather(watcher_task, worker_task)


if __name__ == "__main__":
    # To set up the IPv4 pool, create the ConfigMap like this:
    # ---
    # apiVersion: v1
    # kind: ConfigMap
    # metadata:
    #   name: cheapam-config
    #   namespace: kube-system
    # data:
    #   IPv4: "10.100.0.0/16"
    # ---
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit) as e:
        if isinstance(e, SystemExit) and e.code == 0:
            print("Exiting normally.")
        elif isinstance(e, SystemExit):
            print(f"Exiting due to fatal error (code {e.code}).", file=sys.stderr)
        else:
            print("\nExiting.")
