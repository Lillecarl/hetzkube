#!/usr/bin/env bash
set -euo pipefail
set -x

nix run --show-trace --file . kubenix.deploymentScript --argstr stage full -- --write-command-result=false --prune --yes
