#!/usr/bin/env bash
################################################################################
# Add nodeSelector to all platform applications
# Ensures workloads run on Karpenter-managed nodes, not bootstrap node
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

info "Adding nodeSelector to platform applications..."

# List of deployments/statefulsets that should run on Karpenter nodes
NAMESPACES_AND_APPS=(
    "observability:deployment/loki-gateway"
    "observability:statefulset/loki"
    "observability:daemonset/loki-canary"
    "observability:daemonset/promtail"
    "keycloak:statefulset/keycloak"
    "backstage:deployment/backstage"
)

for item in "${NAMESPACES_AND_APPS[@]}"; do
    NS="${item%%:*}"
    RESOURCE="${item##*:}"

    info "Patching $RESOURCE in $NS..."
    kubectl patch $RESOURCE -n $NS -p '{
      "spec": {
        "template": {
          "spec": {
            "nodeSelector": {
              "workload-type": "general"
            }
          }
        }
      }
    }' 2>&1 || warn "Failed to patch $RESOURCE (may not exist yet)"
done

info "✓ NodeSelectors added"
