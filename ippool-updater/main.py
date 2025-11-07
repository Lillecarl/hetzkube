#! /usr/bin/env python3
import asyncio
import ipaddress
import kr8s
from kr8s.asyncio.objects import new_class

# Configuration
POOL_NAME = "external-ips"
IPV6_PREFIX = 64
DNSENDPOINT_NAME = "apiservers"

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


async def update_ip_info():
    """Gathers ExternalIPs and creates or patches the MetalLB IPAddressPool."""
    nodes = kr8s.asyncio.get("nodes")
    subnets = []
    addresses4 = []
    addresses6 = []
    async for node in nodes:
        for addr in node.status.addresses:
            if addr.type == "ExternalIP":
                try:
                    ip = ipaddress.ip_address(addr.address)
                    if ip.version == 4:
                        # LB IPPool
                        network = ipaddress.ip_network(f"{ip}/32", strict=False)
                        subnets.append(str(network.with_prefixlen))
                        # CP RRDNS
                        if "node-role.kubernetes.io/control-plane" in node.metadata.get(
                            "labels", {}
                        ):
                            addresses4.append(addr.address)
                    elif ip.version == 6:
                        # LB IPPool
                        network = ipaddress.ip_network(f"{ip}/64", strict=False)
                        subnets.append(str(network.with_prefixlen))
                        # CP RRDNS
                        if "node-role.kubernetes.io/control-plane" in node.metadata.get(
                            "labels", {}
                        ):
                            addresses6.append(addr.address)
                except ValueError:
                    print(f"Skipping invalid IP address: {addr.address}")

    if not subnets or not addresses4:
        print("No ExternalIPs found. IPAddressPool will not be modified.")
        return

    ippool_spec = {
        "metadata": {"name": POOL_NAME},
        "spec": {"addresses": sorted(set(subnets))},
    }
    ippool = await IPAddressPool(ippool_spec, "metallb-system")

    dnsendpoint_spec = {
        "metadata": {"name": DNSENDPOINT_NAME},
        "spec": {
            "endpoints": [
                {
                    "dnsName": "kubernetes.lillecarl.com",
                    "recordTTL": 60,
                    "recordType": "A",
                    "targets": sorted(list(set(addresses4))),
                },
                {
                    "dnsName": "kubernetes.lillecarl.com",
                    "recordTTL": 60,
                    "recordType": "AAAA",
                    "targets": sorted(list(set(addresses6))),
                },
            ]
        },
    }
    dnsendpoint = await DNSEndpoint(dnsendpoint_spec, "kube-system")

    try:
        if await ippool.exists():
            await ippool.patch(ippool_spec)
            print(f"Patched {ippool.kind} '{ippool.name}'")
        else:
            await ippool.create()
            print(f"Created {ippool.kind} '{ippool.name}'")
    except Exception as e:
        print(f"An error occurred: {e}")

    try:
        if await dnsendpoint.exists():
            await dnsendpoint.patch(dnsendpoint_spec)
            print(f"Patched {dnsendpoint.kind} '{dnsendpoint.name}'")
        else:
            await dnsendpoint.create()
            print(f"Created {dnsendpoint.kind} '{dnsendpoint.name}'")
    except Exception as e:
        print(f"An error occurred: {e}")


async def main():
    """Watches for node changes and triggers IP pool updates."""
    while True:
        async for event, node in kr8s.asyncio.watch("nodes"):
            if event in ("ADDED", "MODIFIED", "DELETED"):
                print(f"Node {node.name} event: {event}. Re-evaluating IP pool.")
                await update_ip_info()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Exiting.")
