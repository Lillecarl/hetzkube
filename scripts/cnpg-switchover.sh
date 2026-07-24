#!/usr/bin/env bash
set -euo pipefail

# CloudNativePG cluster switchover script
#
# Performs a controlled switchover of the primary instance to a ready replica.
# Useful for:
#   - Testing failover procedures
#   - Maintenance (e.g., before node draining)
#   - Distributing primary workload across nodes over time
#
# The script uses structured JSON output from kubectl-cnpg to avoid brittle
# text parsing. It selects the first ready replica and promotes it to primary.
#
# Requirements: kubectl-cnpg, jq
#
# Example cronjob (weekly switchover on Sundays at 3 AM):
#   0 3 * * 0 /path/to/cnpg-switchover.sh >> /var/log/cnpg-switchover.log 2>&1

usage() {
  echo "Usage: $0 [OPTIONS] [CLUSTER] [NAMESPACE]"
  echo ""
  echo "Options:"
  echo "  -n, --dry-run    Show what would be done without executing"
  echo "  -h, --help       Show this help message"
  echo ""
  echo "Arguments:"
  echo "  CLUSTER          Cluster name (default: pg0)"
  echo "  NAMESPACE        Namespace (default: database)"
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

CLUSTER="${1:-pg0}"
NAMESPACE="${2:-database}"

set -x

# Fetch cluster status as JSON for reliable parsing
status=$(kubectl-cnpg status "$CLUSTER" -n "$NAMESPACE" -o json)

# Verify cluster is healthy before attempting switchover
cluster_phase=$(echo "$status" | jq -r '.cluster.status.phase')
if [[ "$cluster_phase" != "Cluster in healthy state" ]]; then
  echo "ERROR: Cluster is not healthy. Current phase: $cluster_phase" >&2
  exit 1
fi

# Extract current primary from cluster status
current_primary=$(echo "$status" | jq -r '.cluster.status.currentPrimary')

# Build a list of instances with their role and readiness state
instances=$(echo "$status" | jq -r '[.instanceStatus.items[] | {name: .pod.metadata.name, isPrimary, isPodReady}]')

# Select the first replica that is ready to be promoted
# Filters for: not the current primary AND pod is ready to serve traffic
new_primary=$(echo "$instances" | jq -r --arg primary "$current_primary" '
  map(select(.name != $primary and .isPodReady == true))
  | .[0].name // empty
')

if [[ -z "$new_primary" ]]; then
  echo "ERROR: No ready replica found to promote" >&2
  exit 1
fi

echo "Current primary: $current_primary"
echo "Promoting: $new_primary"

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would execute: kubectl-cnpg promote $CLUSTER $new_primary -n $NAMESPACE"
  exit 0
fi

# Initiate the switchover - CNPG handles the graceful transition:
# 1. New primary is promoted
# 2. Old primary demotes itself to replica
# 3. Replication reconfigures automatically
kubectl-cnpg promote "$CLUSTER" "$new_primary" -n "$NAMESPACE"

echo "Switchover initiated: $current_primary -> $new_primary"
