import ipaddress
from kr8s.asyncio.objects import Node

from . import config
from .kr8s_objects import IPAddressPool, DNSEndpoint


async def update_external_resources(nodes: list[Node], cluster_hostname: str):
    """Creates/patches MetalLB IPAddressPool and external-dns DNSEndpoint."""
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
                    print(f"Skipping invalid IP address: {addr.address}")

    if not service_subnets:
        print("No ExternalIPs found. IPAddressPool will not be modified.")
        return

    # MetalLB IPAddressPool
    ippool_spec = {
        "metadata": {"name": config.POOL_NAME},
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
        print(f"{ippool_spec=}")

    # external-dns DNSEndpoint
    if cp_addresses4 or cp_addresses6:
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
                print(f"Patched {dnsendpoint.kind} '{dnsendpoint.name}'")
            else:
                await dnsendpoint.create()
                print(f"Created {dnsendpoint.kind} '{dnsendpoint.name}'")
        except Exception as e:
            print(f"An error occurred updating DNSEndpoint: {e}")
    print("--- Finished external resource update ---")

