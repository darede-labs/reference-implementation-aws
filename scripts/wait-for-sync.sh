#!/usr/bin/env bash
################################################################################
# Wait for ArgoCD Applications to Sync - Optimized for Speed
#
# Optimization strategy:
# 1. SINGLE kubectl call per loop (not N calls for N apps)
# 2. Early-exit when cluster is USABLE (not perfect)
# 3. Gate tiers: Critical (blocks) vs Soft (doesn't block)
# 4. Adaptive polling: fast early, slower later
# 5. Skip sleep if terminal state reached
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
TIMEOUT=${1:-600}
ELAPSED=0

# Gate definitions (apps that MUST be ready vs apps that can drift)
# Critical: Core infra that makes cluster usable
CRITICAL_APPS="ingress-nginx|external-dns|keycloak|cert-manager"
# Soft-gate: Can be Healthy+OutOfSync without blocking
SOFT_GATE_PATTERN="kyverno|prometheus|loki|grafana|promtail|observability|backstage"

################################################################################
# Optimization: Single kubectl call returns ALL app status as JSON
################################################################################
get_all_apps_status() {
    kubectl get applications -n argocd \
        -o jsonpath='{range .items[?(@.metadata.name!="root-app")]}{.metadata.name}|{.status.sync.status}|{.status.health.status}{"\n"}{end}' \
        2>/dev/null | sort
}

# Adaptive interval: aggressive early, relaxed later
get_interval() {
    if [ $ELAPSED -lt 30 ]; then echo 3
    elif [ $ELAPSED -lt 90 ]; then echo 5
    elif [ $ELAPSED -lt 180 ]; then echo 10
    else echo 15
    fi
}

# Check if app matches pattern
matches_pattern() {
    local app="$1" pattern="$2"
    [[ "$app" =~ $pattern ]]
}

################################################################################
# Main
################################################################################

info "=========================================="
info "ArgoCD Sync Monitor (Optimized)"
info "=========================================="
info "Timeout: ${TIMEOUT}s | Critical: ${CRITICAL_APPS}"
echo ""

# Initial app list (one-time)
INITIAL_STATUS=$(get_all_apps_status)
if [ -z "$INITIAL_STATUS" ]; then
    warn "No ArgoCD applications found (excluding root-app)"
    info "Early exit: nothing to wait for"
    exit 0
fi

TOTAL_APPS=$(echo "$INITIAL_STATUS" | wc -l | tr -d ' ')
info "Monitoring ${TOTAL_APPS} applications"
echo ""

# Track previous state for change detection
PREV_STATE=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    INTERVAL=$(get_interval)
    
    # OPTIMIZATION: Single kubectl call for ALL apps
    APP_STATUS=$(get_all_apps_status)
    
    # Skip processing if state unchanged (reduces CPU, not API calls)
    if [ "$APP_STATUS" = "$PREV_STATE" ] && [ -n "$PREV_STATE" ]; then
        printf "\r⏱️  %3ds/%ds [stable] " "$ELAPSED" "$TIMEOUT"
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi
    PREV_STATE="$APP_STATUS"
    
    # Single-pass evaluation
    SYNCED=0 HEALTHY=0 DEGRADED=0 PROGRESSING=0
    CRITICAL_READY=0 CRITICAL_TOTAL=0 CRITICAL_BLOCKED=""
    SOFT_READY=0 SOFT_TOTAL=0
    OTHER_READY=0 OTHER_TOTAL=0
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "⏱️  %3ds / %ds (poll: %ds)\n" "$ELAPSED" "$TIMEOUT" "$INTERVAL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    while IFS='|' read -r APP SYNC HEALTH; do
        [ -z "$APP" ] && continue
        
        # Determine gate type and count
        if matches_pattern "$APP" "$CRITICAL_APPS"; then
            GATE="🔒" && ((CRITICAL_TOTAL++))
            if [[ "$SYNC" == "Synced" && "$HEALTH" == "Healthy" ]]; then
                ((CRITICAL_READY++))
            else
                CRITICAL_BLOCKED+=" $APP"
            fi
        elif matches_pattern "$APP" "$SOFT_GATE_PATTERN"; then
            GATE="🔓" && ((SOFT_TOTAL++))
            # Soft: Healthy alone is sufficient
            [[ "$HEALTH" == "Healthy" || "$HEALTH" == "Progressing" ]] && ((SOFT_READY++))
        else
            GATE="  " && ((OTHER_TOTAL++))
            [[ "$HEALTH" == "Healthy" || "$HEALTH" == "Progressing" ]] && ((OTHER_READY++))
        fi
        
        # Global counters
        [[ "$SYNC" == "Synced" ]] && ((SYNCED++))
        case "$HEALTH" in
            Healthy) ((HEALTHY++)) ;;
            Degraded) ((DEGRADED++)) ;;
            Progressing) ((PROGRESSING++)) ;;
        esac
        
        # Status icons
        case "$SYNC" in Synced) SI="✅";; OutOfSync) SI="🔄";; *) SI="❓";; esac
        case "$HEALTH" in Healthy) HI="✅";; Degraded) HI="❌";; Progressing) HI="🔄";; Missing) HI="⚠️";; *) HI="❓";; esac
        
        printf "%s %-24s %s %-10s %s %s\n" "$GATE" "$APP" "$SI" "$SYNC" "$HI" "$HEALTH"
    done <<< "$APP_STATUS"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "📊 Synced=%d/%d  Healthy=%d  Progressing=%d  Degraded=%d\n" \
        "$SYNCED" "$TOTAL_APPS" "$HEALTHY" "$PROGRESSING" "$DEGRADED"
    printf "🔒 Critical: %d/%d  🔓 Soft: %d/%d  Other: %d/%d\n" \
        "$CRITICAL_READY" "$CRITICAL_TOTAL" "$SOFT_READY" "$SOFT_TOTAL" "$OTHER_READY" "$OTHER_TOTAL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # ==================== EARLY EXIT DECISIONS ====================
    
    # BEST CASE: Perfect sync
    if [ "$SYNCED" -eq "$TOTAL_APPS" ] && [ "$HEALTHY" -eq "$TOTAL_APPS" ]; then
        echo ""
        info "✅ Perfect: All ${TOTAL_APPS} apps Synced+Healthy"
        exit 0
    fi
    
    # GOOD CASE: Cluster is usable (critical ready + all effectively healthy)
    TOTAL_EFFECTIVE=$((CRITICAL_READY + SOFT_READY + OTHER_READY))
    if [ "$CRITICAL_TOTAL" -gt 0 ] && [ "$CRITICAL_READY" -eq "$CRITICAL_TOTAL" ] && [ "$TOTAL_EFFECTIVE" -eq "$TOTAL_APPS" ]; then
        echo ""
        info "✅ Cluster operational! (${ELAPSED}s)"
        info "   🔒 Critical: ${CRITICAL_READY}/${CRITICAL_TOTAL} Synced+Healthy"
        [ "$SOFT_TOTAL" -gt 0 ] && info "   🔓 Soft-gate: ${SOFT_READY}/${SOFT_TOTAL} Healthy (may be OutOfSync)"
        [ "$SYNCED" -lt "$TOTAL_APPS" ] && info "   ℹ️  Some apps OutOfSync - will sync in background"
        exit 0
    fi
    
    # EARLY CASE: All healthy, even if not all synced
    if [ "$HEALTHY" -eq "$TOTAL_APPS" ] && [ "$CRITICAL_READY" -eq "$CRITICAL_TOTAL" ]; then
        echo ""
        info "✅ All apps Healthy (${ELAPSED}s)"
        info "   ℹ️  ${SYNCED}/${TOTAL_APPS} synced, rest will sync in background"
        exit 0
    fi
    
    # FAIL FAST: Degraded critical apps after grace period
    if [ "$DEGRADED" -gt 0 ] && [ $ELAPSED -gt 120 ]; then
        # Check if degraded apps are critical
        while IFS='|' read -r APP _ HEALTH; do
            if matches_pattern "$APP" "$CRITICAL_APPS" && [[ "$HEALTH" == "Degraded" ]]; then
                echo ""
                error_msg="Critical app $APP is Degraded after ${ELAPSED}s"
                echo -e "${RED}[ERROR]${NC} $error_msg"
                info "💡 Check: kubectl describe application $APP -n argocd"
                exit 1
            fi
        done <<< "$APP_STATUS"
    fi
    
    # ==================== STATUS MESSAGES ====================
    
    if [ -n "$CRITICAL_BLOCKED" ]; then
        warn "⏳ Waiting for critical:$CRITICAL_BLOCKED"
    fi
    
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

# ==================== TIMEOUT ====================

echo ""
echo -e "${RED}[ERROR]${NC} ❌ Timeout after ${TIMEOUT}s"

# Quick final check
if [ -n "$CRITICAL_BLOCKED" ]; then
    echo -e "${RED}[ERROR]${NC} 🔒 Critical NOT ready:$CRITICAL_BLOCKED"
fi

echo ""
info "📋 Final:"
kubectl get applications -n argocd -o wide 2>/dev/null || true
echo ""
info "💡 Debug: kubectl describe application <name> -n argocd"
exit 1
