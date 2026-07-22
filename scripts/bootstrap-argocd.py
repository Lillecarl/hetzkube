#!/usr/bin/env python3
"""One-time, idempotent ArgoCD bootstrap.

ArgoCD can't sync itself into existence, so this ensures its SOPS/ksops
decrypt identity exists, then applies the "bootstrap" GitOps target
(ArgoCD's own install manifests plus the bootstrap/everything Application
CRs -- see kubenix/configuration/gitops.nix) via `ekn kubeapply`, bypassing
kluctl entirely.

From that point on, ArgoCD's own "bootstrap" Application reconciles itself
(and, once the `deploy` git branch is populated via `ekn commit`, syncs
"everything" too). Re-running this script is safe -- both the Secret
ensure-step and `ekn kubeapply` are idempotent.

Usage:
    scripts/bootstrap-argocd.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

EXPECTED_CONTEXT = "hetzkube"
ARGOCD_NAMESPACE = "argocd"
SOPS_AGE_SECRET = "sops-age-key"


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


def ensure_sops_age_secret() -> None:
    """Idempotently ensure argocd-repo-server's SOPS decrypt identity
    exists. ekn never handles key material -- this is the one place a
    fresh age keypair gets generated and applied, directly via kubectl,
    never through Nix/git (see kubenix/modules/argocd.nix's ksops.enable
    and its `secretName` option, which must match SOPS_AGE_SECRET)."""
    existing = subprocess.run(
        ["kubectl", "get", "secret", "-n", ARGOCD_NAMESPACE, SOPS_AGE_SECRET],
        capture_output=True,
    )
    if existing.returncode == 0:
        print(f"Secret/{SOPS_AGE_SECRET} already exists in {ARGOCD_NAMESPACE}, leaving it alone.")
        return

    print(f"Ensuring namespace/{ARGOCD_NAMESPACE} exists...")
    ns = {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": ARGOCD_NAMESPACE}}
    subprocess.run(
        ["kubectl", "apply", "--server-side", "-f", "-"],
        input=json.dumps(ns),
        text=True,
        check=True,
    )

    print(f"Generating a fresh age keypair for Secret/{SOPS_AGE_SECRET}...")
    with tempfile.TemporaryDirectory() as tmp:
        key_file = Path(tmp) / "key.txt"
        subprocess.run(["age-keygen", "-o", str(key_file)], check=True, capture_output=True)
        public_key = next(
            line.split(":", 1)[1].strip()
            for line in key_file.read_text().splitlines()
            if line.startswith("# public key:")
        )
        subprocess.run(
            [
                "kubectl", "create", "secret", "generic", SOPS_AGE_SECRET,
                "-n", ARGOCD_NAMESPACE,
                f"--from-file=key.txt={key_file}",
            ],
            check=True,
        )

    print(
        f"\nAdd this recipient to .sops.yaml and re-run `sops updatekeys` on "
        f"any file that should be decryptable by ArgoCD:\n\n    {public_key}\n"
    )


def kubeapply_bootstrap() -> None:
    ekn_out = subprocess.check_output(
        ["nix", "build", "--no-link", "--print-out-paths", "--file", ".", "kubenix.passthru.ekn"],
        text=True,
    ).strip()
    subprocess.run(
        [
            f"{ekn_out}/bin/ekn", "kubeapply",
            "--file", "./default.nix", "-A", "kubenix",
            "--target", "bootstrap",
        ],
        check=True,
    )


def main() -> None:
    check_context()
    ensure_sops_age_secret()
    kubeapply_bootstrap()
    print(
        "\nArgoCD bootstrapped. Next: populate the `deploy` branch (e.g. `ekn commit`) "
        "and check `kubectl get applications -n argocd`."
    )


if __name__ == "__main__":
    main()
