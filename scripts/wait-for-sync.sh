#!/usr/bin/env bash
################################################################################
# Wait for ArgoCD Applications to Sync
# Monitors ArgoCD applications and reports progress with timeout
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

TIMEOUT=${1:-600}  # Default 10 minutes
CHECK_INTERVAL=10  # Check every 10 seconds
ELAPSED=0

info "=========================================="
info "Waiting for ArgoCD Applications to Sync"
info "=========================================="
info "Timeout: ${TIMEOUT}s"
info "Check interval: ${CHECK_INTERVAL}s"
echo ""

# Get list of applications (excluding root-app)
APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.name!="root-app")].metadata.name}' | tr ' ' '\n' | sort)
TOTAL_APPS=$(echo "$APPS" | wc -l | tr -d ' ')

info "Applications to monitor: ${TOTAL_APPS}"
echo "$APPS" | sed 's/^/  - /'
echo ""

while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNCED=0
    HEALTHY=0
    DEGRADED=0
    PROGRESSING=0
    MISSING=0
    UNKNOWN=0

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "⏱️  Elapsed: %3ds / %ds\n" "$ELAPSED" "$TIMEOUT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check each application
    for APP in $APPS; do
        SYNC_STATUS=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        # Count statuses
        case "$SYNC_STATUS" in
            "Synced") ((SYNCED++)) || true ;;
            "OutOfSync") ;;
            "Unknown") ((UNKNOWN++)) || true ;;
        esac

        case "$HEALTH_STATUS" in
            "Healthy") ((HEALTHY++)) || true ;;
            "Degraded") ((DEGRADED++)) || true ;;
            "Progressing") ((PROGRESSING++)) || true ;;
            "Missing") ((MISSING++)) || true ;;
            "Unknown") ;;
        esac

        # Format status with colors
        SYNC_ICON="⏳"
        HEALTH_ICON="⏳"

        case "$SYNC_STATUS" in
            "Synced") SYNC_ICON="✅" ;;
            "OutOfSync") SYNC_ICON="🔄" ;;
            "Unknown") SYNC_ICON="❓" ;;
        esac

        case "$HEALTH_STATUS" in
            "Healthy") HEALTH_ICON="✅" ;;
            "Degraded") HEALTH_ICON="❌" ;;
            "Progressing") HEALTH_ICON="🔄" ;;
            "Missing") HEALTH_ICON="⚠️ " ;;
            "Unknown") HEALTH_ICON="❓" ;;
        esac

        printf "%-25s %s %-12s %s %-12s\n" "$APP" "$SYNC_ICON" "$SYNC_STATUS" "$HEALTH_ICON" "$HEALTH_STATUS"
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "📊 Summary: Synced=%d/%d  Healthy=%d/%d  Progressing=%d  Missing=%d  Unknown=%d\n" \
        "$SYNCED" "$TOTAL_APPS" "$HEALTHY" "$TOTAL_APPS" "$PROGRESSING" "$MISSING" "$UNKNOWN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if all apps are synced and healthy
    if [ "$SYNCED" -eq "$TOTAL_APPS" ] && [ "$HEALTHY" -eq "$TOTAL_APPS" ]; then
        echo ""
        info "✅ All applications are synced and healthy!"
        exit 0
    fi

    # Check for stuck apps (Missing for too long)
    if [ "$MISSING" -gt 0 ] && [ $ELAPSED -gt 120 ]; then
        echo ""
        warn "⚠️  Some applications are Missing (may indicate configuration issues)"
        warn "   Check ArgoCD UI or logs for details"
    fi

    echo ""
    info "⏳ Waiting ${CHECK_INTERVAL}s before next check..."
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    echo ""
done

# Timeout reached
echo ""
error "❌ Timeout reached (${TIMEOUT}s)"
error "   Not all applications are synced and healthy"
echo ""
info "Current status:"
kubectl get applications -n argocd
echo ""
info "💡 Tip: Check ArgoCD UI or run 'kubectl get applications -n argocd' for details"
exit 1
