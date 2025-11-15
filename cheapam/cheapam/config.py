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
IPV6_SERVICE_PREFIX = 118
DEBOUNCE_DELAY_SECONDS = 2.0

