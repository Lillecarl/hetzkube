from kr8s.asyncio.objects import new_class

DNSEndpoint = new_class(
    kind="DNSEndpoint",
    version="externaldns.k8s.io/v1alpha1",
    namespaced=True,
    plural="dnsendpoints",
)
