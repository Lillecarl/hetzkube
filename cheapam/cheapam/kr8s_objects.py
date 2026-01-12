from kr8s.asyncio.objects import new_class

IPAddressPool = new_class(
    kind="IPAddressPool",
    version="metallb.io/v1beta1",
    namespaced=True,
    plural="ipaddresspools",
)

CiliumLoadBalancerIPPool = new_class(
    kind="CiliumLoadBalancerIPPool",
    version="cilium.io/v2",
    namespaced=False,
    plural="ciliumloadbalancerippools",
)

DNSEndpoint = new_class(
    kind="DNSEndpoint",
    version="externaldns.k8s.io/v1alpha1",
    namespaced=True,
    plural="dnsendpoints",
)

