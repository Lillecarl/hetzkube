# Updating projects

Skip "cluster critical projects" (Cilium, ClusterAPI).

## Workflow

```python (pseudocode)
for project in projects:  # one at a time, sequential
    update_version        # bump the version string in configuration/<project>.nix
                          # or modules/<project>.nix default
    update_hash           # if the module uses pkgs.fetchFromGitHub / pkgs.fetchHelm,
                          # set hash to "" so pynix can auto-detect the FOD source

    # Verify the diff looks right
    PYTHONPATH="" pynix ekn diff --file . --attr kubenix

    # Deploy
    PYTHONPATH="" pynix ekn deploy --file . --attr kubenix --push

    # Wait for ArgoCD sync, then verify rollout
    kubectl get application everything -n argocd -w  # watch for Synced
    kubectl get pods -A | grep <project>             # all running
    kubectl get externalsecret -A | grep -v True     # no broken secrets

    # Auto-patch FOD hash (if using pkgs.fetchFromGitHub/fetchHelm with ""):
    PYTHONPATH="" pynix ekn eval --file . --attr kubenix \
      --update-fod --source-file kubenix/<path>/<module>.nix

    # Commit
    jj diff --git
    jj commit -m "update <project> from <old> to <new>"
```

## Deployment command

```bash
PYTHONPATH="" pynix ekn deploy --file . --attr kubenix --push
```

`PYTHONPATH=""` prevents the local nanopynix checkout from shadowing the
installed packages (the dev env mounts editable source paths that can drift
from the compiled binary).

## Hash auto-patching

When a module uses `pkgs.fetchFromGitHub` or `pkgs.fetchHelm`, set the `hash`
(or `sha256` / `chartHash`) to `""`. On the next `pynix ekn eval --update-fod
--source-file <file>`, pynix reads the hash mismatch error, extracts the
correct hash, and replaces the `""` literal in the source file. This avoids
the `lib.fakeHash` round-trip where you have to read the error output manually.
