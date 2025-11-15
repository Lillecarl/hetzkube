import ipaddress
import kr8s
import sys
from kr8s.asyncio.objects import ConfigMap, Node

from . import config
from . import hetzner


async def reconcile_ipam(nodes: list[Node]):
    """Manages node initialization (providerID, IPs) and podCIDR allocations."""
    print("--- Starting IPAM reconciliation ---")

    # --- This part remains unchanged ---
    try:
        config_cm = await ConfigMap.get(config.IPAM_CONFIG_MAP, config.IPAM_NAMESPACE)
        ipv4_pool_str = config_cm.data.get(config.IPAM_CONFIG_KEY_V4)
        if not ipv4_pool_str:
            print(f"Error: ConfigMap '{config.IPAM_CONFIG_MAP}' is missing required key '{config.IPAM_CONFIG_KEY_V4}'. Exiting.", file=sys.stderr)
            raise SystemExit(1)
        ipv4_pool = ipaddress.ip_network(ipv4_pool_str)
    except kr8s.NotFoundError:
        print(f"Error: Required ConfigMap '{config.IPAM_CONFIG_MAP}' not found in namespace '{config.IPAM_NAMESPACE}'. Exiting.", file=sys.stderr)
        raise SystemExit(1)

    state_cm_spec = {"metadata": {"name": config.IPAM_STATE_MAP}, "data": {"placeholder": "10.13.37.0/24"}}
    try:
        state_cm = await ConfigMap.get(config.IPAM_STATE_MAP, namespace=config.IPAM_NAMESPACE)
        print(f"Fetched IPAM state ConfigMap '{config.IPAM_STATE_MAP}'")
    except kr8s.NotFoundError:
        state_cm = await ConfigMap(state_cm_spec, namespace=config.IPAM_NAMESPACE)
        await state_cm.create()
        print(f"Created IPAM state ConfigMap '{config.IPAM_STATE_MAP}'")

    current_nodes = {node.name for node in nodes}

    for node_name in list(state_cm.data.keys()):
        if node_name not in current_nodes:
            print(f"Node '{node_name}' deleted. Reclaiming its IPv4 CIDR.")
            state_cm.data[node_name] = None

    for node in nodes:
        # --- NEW: Node Initialization Logic ---
        uninitialized_taint = any(
            taint.get("key") == "node.cloudprovider.kubernetes.io/uninitialized"
            for taint in node.spec.get("taints", [])
        )

        if uninitialized_taint or not node.spec.get("providerID"):
            print(f"Node '{node.name}' is uninitialized. Fetching details from Hetzner.")
            server = await hetzner.get_server_details(node.name)
            if server:
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
                    ipv6_subnet = ipaddress.ip_network(server.public_net.ipv6.ip)
                    first_host_ipv6 = next(ipv6_subnet.hosts())
                    addresses.append({"type": "ExternalIP", "address": str(first_host_ipv6)})

                # Patch providerID
                print(f"Setting providerID for node '{node.name}' to '{provider_id}'")
                await node.patch({"spec": {"providerID": provider_id}})

                # Patch addresses
                print(f"Setting addresses for node '{node.name}'")
                await node.patch({"status": {"addresses": addresses}}, subresource="status")

                # Remove the uninitialized taint
                print(f"Removing uninitialized taint from node '{node.name}'")
                taints = [
                    taint for taint in node.spec.get("taints", [])
                    if taint.get("key") != "node.cloudprovider.kubernetes.io/uninitialized"
                ]
                await node.patch({"spec": {"taints": taints}})
            else:
                print(f"Could not initialize node '{node.name}', server details not found.")
                continue # Skip to next node if we can't find it in Hetzner

        # --- Existing podCIDR state import logic ---
        if pod_cidr := node.spec.get("podCIDR"):
            if state_cm.data.get(node.name) != pod_cidr:
                print(f"Discovered existing IPv4 CIDR '{pod_cidr}' on node '{node.name}'. Importing to state.")
                state_cm.data[node.name] = pod_cidr
    # --- END OF MODIFIED SECTION ---

    # --- This part remains unchanged ---
    allocated_ipv4_subnets = {cidr for cidr in state_cm.data.values() if cidr}
    available_ipv4_subnets = iter(ipv4_pool.subnets(new_prefix=config.IPV4_PREFIX))

    for node in nodes:
        if node.spec.get("podCIDR"):
            continue

        desired_v4: str | None = None
        desired_v6: str | None = None

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
        print(f"Allocating new IPv4 CIDR '{subnet}' to node '{node.name}'")
        state_cm.data[node.name] = subnet
        allocated_ipv4_subnets.add(subnet)
        desired_v4 = subnet

        patch = {"spec": {"podCIDR": desired_v4, "podCIDRs": [desired_v4, desired_v6]}}
        print(f"Patching node '{node.name}' with podCIDRs: {desired_v4=},{desired_v6=}")
        await node.patch(patch)

    print(f"Updating IPAM state in ConfigMap '{config.IPAM_STATE_MAP}'")
    await state_cm.patch({"data": state_cm.data})
    print("--- Finished IPAM reconciliation ---")
