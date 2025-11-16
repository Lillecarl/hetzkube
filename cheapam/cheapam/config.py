import logging
import os

# Get log level from environment variable or default to INFO
CHEAPAM_LOG_LEVEL = os.environ.get("CHEAPAM_LOG_LEVEL", "INFO").upper()
# Get dependencies log level from environment variable or default to WARNING
DEPENDENCIES_LOG_LEVEL = os.environ.get("DEPENDENCIES_LOG_LEVEL", "WARNING").upper()

# Configure logging
logging.basicConfig(
    level=getattr(logging, DEPENDENCIES_LOG_LEVEL, logging.WARNING),  # Set default level for all loggers
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

# Set specific level for cheapam loggers
cheapam_logger = logging.getLogger("cheapam")
cheapam_logger.setLevel(getattr(logging, CHEAPAM_LOG_LEVEL, logging.INFO))

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
