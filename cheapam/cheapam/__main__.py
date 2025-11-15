#! /usr/bin/env python3

import asyncio
import kr8s
import sys
import yaml
from typing import cast
from urllib.parse import urlparse
from kr8s.asyncio.objects import ConfigMap, Node

from . import config
from .ipam import reconcile_ipam
from .external_resources import update_external_resources


async def get_cluster_hostname() -> str:
    """Retrieves the API server hostname from the cluster-info ConfigMap."""
    cluster_info = await ConfigMap.get("cluster-info", "kube-public")
    kubeconfig_data = yaml.safe_load(cluster_info.data["kubeconfig"])
    server_url = kubeconfig_data["clusters"][0]["cluster"]["server"]
    return urlparse(server_url).hostname


async def reconciliation_worker(event: asyncio.Event, cluster_hostname: str):
    """Waits for an event, then triggers a full reconciliation."""
    while True:
        await event.wait()
        print(
            f"Change detected, waiting {config.DEBOUNCE_DELAY_SECONDS}s for debounce period..."
        )
        await asyncio.sleep(config.DEBOUNCE_DELAY_SECONDS)
        event.clear()

        print("--- Debounce period over. Starting full reconciliation. ---")
        try:
            all_nodes = [cast(Node, node) async for node in kr8s.asyncio.get("nodes")]
            await reconcile_ipam(all_nodes)
            await update_external_resources(all_nodes, cluster_hostname)
        except Exception as e:
            print(f"Error during reconciliation: {e}", file=sys.stderr)
        print("--- Full reconciliation complete. Awaiting next change. ---")


async def node_watcher(event: asyncio.Event):
    """Watches for node changes and sets an event to trigger reconciliation."""
    while True:
        try:
            async for evt, node in kr8s.asyncio.watch("nodes"):
                print(f"Node '{node.name}' event: '{evt}'. Triggering reconciliation.")
                event.set()
        except Exception as e:
            print(
                f"Error in watch loop: {e}. Reconnecting in 10 seconds.",
                file=sys.stderr,
            )
            await asyncio.sleep(10)


async def main():
    """Sets up and runs the watcher and reconciliation tasks."""
    cluster_hostname = await get_cluster_hostname()
    if cluster_hostname:
        print(f"Operating on cluster: {cluster_hostname}")

    reconciliation_needed = asyncio.Event()
    watcher_task = asyncio.create_task(node_watcher(reconciliation_needed))
    worker_task = asyncio.create_task(
        reconciliation_worker(reconciliation_needed, cluster_hostname)
    )

    # No initial reconciliation trigger needed since nodes appear as ADDED
    # when watch is started
    await asyncio.gather(watcher_task, worker_task)


def cli():
    """Main command-line entrypoint."""
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit) as e:
        if isinstance(e, SystemExit) and e.code == 0:
            print("Exiting normally.")
        elif isinstance(e, SystemExit):
            print(f"Exiting due to fatal error (code {e.code}).", file=sys.stderr)
        else:
            print("\nExiting.")


if __name__ == "__main__":
    cli()
