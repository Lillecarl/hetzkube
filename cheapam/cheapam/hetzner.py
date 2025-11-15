import os
from hcloud import Client
from hcloud.servers.client import BoundServer

# Initialize the client. It will automatically use the HCLOUD_TOKEN env var.
hcloud_client = Client(token=os.environ["HCLOUD_TOKEN"])

async def get_server_details(node_name: str) -> BoundServer | None:
    """
    Fetches a server from the Hetzner Cloud API by its name.
    The Kubernetes node name is expected to match the server name in Hetzner.
    """
    try:
        server = hcloud_client.servers.get_by_name(node_name)
        return server
    except Exception as e:
        print(f"Error fetching server '{node_name}' from Hetzner API: {e}")
        return None

