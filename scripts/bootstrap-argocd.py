#!/usr/bin/env python3
"""One-time, idempotent ArgoCD bootstrap.

ArgoCD can't sync itself into existence, so this applies just the objects
routed to the "bootstrap" GitOps target (ArgoCD's own install manifests plus
the `bootstrap`/`everything` Application CRs, see kubenix/configuration/
gitops.nix) directly to the cluster via kubectl -- bypassing kluctl entirely.

From that point on, ArgoCD's own "bootstrap" Application reconciles itself
(and, once the `deploy` git branch is populated via `ekn commit`, syncs
"everything" too). Re-running this script is safe: it's a plain `kubectl
apply`, no pruning.

Usage:
    scripts/bootstrap-argocd.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

EXPECTED_CONTEXT = "hetzkube"
TARGET_PATH = "bootstrap"
ARGOCD_NAMESPACE = "argocd"


def nix_eval(attr: str) -> object:
    out = subprocess.check_output(
        ["nix", "eval", "--impure", "--file", "./default.nix", "--json", attr],
        text=True,
    )
    return json.loads(out)


def check_context() -> None:
    current = subprocess.check_output(
        ["kubectl", "config", "current-context"], text=True
    ).strip()
    if current.endswith(EXPECTED_CONTEXT):
        return
    print(
        f"Warning: current kubectl context is {current!r}, not *{EXPECTED_CONTEXT}",
        file=sys.stderr,
    )
    if input("Continue anyway? [y/N] ").strip().lower() != "y":
        sys.exit("Aborted.")


def bootstrap_objects() -> list[dict]:
    generated: list[dict] = nix_eval("kubenix.config.kubernetes.generated")  # type: ignore[assignment]
    eken_by_path: dict = nix_eval("kubenix.config.kubernetes.eknByPath")  # type: ignore[assignment]

    routed_keys: set[tuple[str, str, str]] = set()
    for namespace, kinds in eken_by_path.items():
        for kind, names in kinds.items():
            for name, routes in names.items():
                if any(route["path"] == TARGET_PATH for route in routes):
                    routed_keys.add((namespace, kind, name))

    def key(obj: dict) -> tuple[str, str, str]:
        return (obj["metadata"].get("namespace", "none"), obj["kind"], obj["metadata"]["name"])

    return [obj for obj in generated if key(obj) in routed_keys]


def kubectl_apply(objects: list[dict], *, wait_crds: bool) -> None:
    manifest = json.dumps({"apiVersion": "v1", "kind": "List", "items": objects})
    subprocess.run(
        ["kubectl", "apply", "--server-side", "-f", "-"],
        input=manifest,
        text=True,
        check=True,
    )
    if wait_crds:
        crd_names = [
            obj["metadata"]["name"] for obj in objects if obj["kind"] == "CustomResourceDefinition"
        ]
        for name in crd_names:
            subprocess.run(
                ["kubectl", "wait", f"crd/{name}", "--for=condition=Established", "--timeout=60s"],
                check=True,
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="print the manifest instead of applying it"
    )
    args = parser.parse_args()

    objects = bootstrap_objects()
    if not objects:
        sys.exit("No objects routed to the bootstrap target -- nothing to apply.")

    if args.dry_run:
        json.dump({"apiVersion": "v1", "kind": "List", "items": objects}, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return

    check_context()

    print(f"Ensuring namespace/{ARGOCD_NAMESPACE} exists...")
    ns = {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": ARGOCD_NAMESPACE}}
    subprocess.run(
        ["kubectl", "apply", "--server-side", "-f", "-"],
        input=json.dumps(ns),
        text=True,
        check=True,
    )

    crds = [obj for obj in objects if obj["kind"] == "CustomResourceDefinition"]
    rest = [obj for obj in objects if obj["kind"] != "CustomResourceDefinition"]

    if crds:
        print(f"Applying {len(crds)} CustomResourceDefinitions and waiting for them to establish...")
        kubectl_apply(crds, wait_crds=True)

    print(f"Applying remaining {len(rest)} bootstrap objects (ArgoCD + Application CRs)...")
    kubectl_apply(rest, wait_crds=False)

    print(
        "\nArgoCD bootstrapped. Next: populate the `deploy` branch (e.g. `ekn commit`) "
        "and check `kubectl get applications -n argocd`."
    )


if __name__ == "__main__":
    main()
