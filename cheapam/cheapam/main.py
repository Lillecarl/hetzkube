import asyncio
import logging
from typing import cast
from urllib.parse import urlparse

import kr8s
import yaml
from kr8s.asyncio.objects import ConfigMap, Node

from . import config
from .external_resources import update_external_resources
from .ipam import reconcile_ipam

logger = logging.getLogger(__name__)


async def get_cluster_hostname() -> str:
    """
    Retrieves the API server hostname from the cluster-info ConfigMap.

    Returns:
        The cluster hostname.
    """
    cluster_info = await ConfigMap.get("cluster-info", "kube-public")
    kubeconfig_data = yaml.safe_load(cluster_info.data["kubeconfig"])
    server_url = kubeconfig_data["clusters"][0]["cluster"]["server"]
    return urlparse(server_url).hostname


async def reconciliation_worker(event: asyncio.Event, cluster_hostname: str) -> None:
    """
    Waits for an event, then triggers a full reconciliation.

    Args:
        event: The event to wait for.
        cluster_hostname: The cluster's hostname.
    """
    while True:
        await event.wait()
        logger.info(f"Change detected, waiting {config.DEBOUNCE_DELAY_SECONDS}s for debounce period...")
        await asyncio.sleep(config.DEBOUNCE_DELAY_SECONDS)
        event.clear()

        logger.info("--- Debounce period over. Starting full reconciliation. ---")
        try:
            all_nodes = [cast(Node, node) async for node in kr8s.asyncio.get("nodes")]
            await reconcile_ipam(all_nodes)
            await update_external_resources(all_nodes, cluster_hostname)
        except Exception as e:
            logger.error(f"Error during reconciliation: {e}")
        logger.info("--- Full reconciliation complete. Awaiting next change. ---")


async def node_watcher(event: asyncio.Event) -> None:
    """
    Watches for node changes and sets an event to trigger reconciliation.

    Args:
        event: The event to set on changes.
    """
    while True:
        try:
            async for evt, node in kr8s.asyncio.watch("nodes"):
                logger.info(f"Node '{node.name}' event: '{evt}'. Triggering reconciliation.")
                event.set()
        except Exception as e:
            logger.error(f"Error in watch loop: {e}. Reconnecting in 10 seconds.")
            await asyncio.sleep(10)


class CheapamApp:
    """Main application class for the cheapam IPAM/CCM combo."""

    def __init__(self):
        self.cluster_hostname: str = ""

    async def setup(self) -> None:
        """Sets up the application, including fetching cluster hostname."""
        self.cluster_hostname = await get_cluster_hostname()
        if self.cluster_hostname:
            logger.info(f"Operating on cluster: {self.cluster_hostname}")

    async def run(self) -> None:
        """Runs the main application loop."""
        await self.setup()

        reconciliation_needed = asyncio.Event()
        watcher_task = asyncio.create_task(node_watcher(reconciliation_needed))
        worker_task = asyncio.create_task(
            reconciliation_worker(reconciliation_needed, self.cluster_hostname)
        )

        # No initial reconciliation trigger needed since nodes appear as ADDED
        # when watch is started
        await asyncio.gather(watcher_task, worker_task)


def cli():
    """Main command-line entrypoint."""
    app = CheapamApp()
    try:
        asyncio.run(app.run())
    except (KeyboardInterrupt, SystemExit) as e:
        if isinstance(e, SystemExit) and e.code == 0:
            logger.info("Exiting normally.")
        elif isinstance(e, SystemExit):
            logger.error(f"Exiting due to fatal error (code {e.code}).")
        else:
            logger.info("Exiting.")


if __name__ == "__main__":
    cli()
