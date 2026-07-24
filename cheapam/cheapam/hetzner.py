import logging
import os
from typing import Optional

from hcloud import Client
from hcloud.servers.client import BoundServer

logger = logging.getLogger(__name__)

# Initialize the client. It will automatically use the HCLOUD_TOKEN env var.
hcloud_client = Client(token=os.environ["HCLOUD_TOKEN"])


async def get_server_details(node_name: str) -> Optional[BoundServer]:
    """
    Fetches a server from the Hetzner Cloud API by its name.
    The Kubernetes node name is expected to match the server name in Hetzner.

    Args:
        node_name: The name of the Kubernetes node/server.

    Returns:
        The BoundServer object if found, None otherwise.
    """
    try:
        server = hcloud_client.servers.get_by_name(node_name)
        return server
    except Exception as e:
        logger.error(f"Error fetching server '{node_name}' from Hetzner API: {e}")
        return None
