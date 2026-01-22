#!/usr/bin/env bash
set -euo pipefail

# Install Observability Stack
# Provisions Loki S3 backend via Terraform and deploys observability components via ArgoCD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo "========================================"
echo "Observability Stack Installation"
echo "========================================"
echo ""

# =============================================================================
# Phase 1: Terraform - Loki S3 Backend
# =============================================================================
info "Phase 1: Provisioning Loki S3 backend..."

cd "${PROJECT_ROOT}/cluster/terraform"

# Apply only Loki resources
info "Running terraform apply for Loki resources..."
terraform apply -target=aws_s3_bucket.loki \
                -target=aws_s3_bucket_versioning.loki \
                -target=aws_s3_bucket_lifecycle_configuration.loki \
                -target=random_id.loki_bucket_suffix \
                -target=aws_iam_policy.loki_s3 \
                -target=module.loki_irsa \
                -auto-approve || error "Terraform failed"

# Get outputs
LOKI_BUCKET=$(terraform output -raw loki_bucket_name) || error "Failed to get Loki bucket name"
LOKI_ROLE=$(terraform output -raw loki_role_arn) || error "Failed to get Loki IAM role ARN"
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "${AWS_REGION:-us-east-1}")

success "Loki S3 bucket: ${LOKI_BUCKET}"
success "Loki IAM role: ${LOKI_ROLE}"
success "AWS region: ${AWS_REGION}"

cd "${PROJECT_ROOT}"

# =============================================================================
# Phase 2: Render ArgoCD Application Manifests
# =============================================================================
info "Phase 2: Rendering ArgoCD Application manifests from templates..."

# Render ArgoCD Applications with dynamic domains
"${SCRIPT_DIR}/render-argocd-apps.sh" || error "Failed to render ArgoCD apps"

# Update Loki Application with Terraform outputs (use | as delimiter to handle / in ARN)
sed -i.bak "s|\${LOKI_BUCKET}|${LOKI_BUCKET}|g" argocd-apps/platform/loki.yaml
sed -i.bak "s|\${LOKI_ROLE_ARN}|${LOKI_ROLE}|g" argocd-apps/platform/loki.yaml
sed -i.bak "s|\${AWS_REGION}|${AWS_REGION}|g" argocd-apps/platform/loki.yaml

success "ArgoCD manifests rendered and updated"

# =============================================================================
# Phase 3: Apply ArgoCD Applications
# =============================================================================
info "Phase 3: Applying ArgoCD applications..."

# Check if ArgoCD is accessible
if ! kubectl get namespace argocd > /dev/null 2>&1; then
  error "ArgoCD namespace not found. Please install ArgoCD first."
fi

# Apply observability namespace
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Apply ArgoCD applications
info "Applying Loki..."
kubectl apply -f argocd-apps/platform/loki.yaml

info "Applying Promtail..."
kubectl apply -f argocd-apps/platform/promtail.yaml

info "Applying kube-prometheus-stack..."
kubectl apply -f argocd-apps/platform/kube-prometheus-stack.yaml

success "ArgoCD applications applied"

# =============================================================================
# Phase 4: Wait for Sync and Health
# =============================================================================
info "Phase 4: Waiting for ArgoCD sync..."

# Function to check pod status and detect issues
check_pod_status() {
  local app=$1
  local namespace=${2:-observability}
  local is_daemonset=${3:-false}  # Whether this is a DaemonSet

  # Map app names to label selectors
  case $app in
    loki)
      local selector="app.kubernetes.io/name=loki"
      ;;
    promtail)
      local selector="app.kubernetes.io/name=promtail"
      is_daemonset=true  # Promtail is a DaemonSet
      ;;
    kube-prometheus-stack)
      local selector="app.kubernetes.io/name=grafana"
      ;;
    *)
      return 0
      ;;
  esac

  # Check for CrashLoopBackOff pods (always an error)
  local crash_loop_pods=$(kubectl get pods -n "$namespace" -l "$selector" \
    -o jsonpath='{.items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")].metadata.name}' 2>/dev/null || echo "")

  if [ -n "$crash_loop_pods" ]; then
    warn "⚠️  Detected CrashLoopBackOff pods for ${app}:"
    echo "$crash_loop_pods" | tr ' ' '\n' | while read -r pod; do
      if [ -n "$pod" ]; then
        echo "  - ${pod}"
        info "    Showing last 20 lines of logs:"
        kubectl logs -n "$namespace" "$pod" --tail=20 2>&1 | sed 's/^/      /' || true
      fi
    done
    return 1
  fi

  # Check for Pending pods
  local pending_pods=$(kubectl get pods -n "$namespace" -l "$selector" \
    -o jsonpath='{.items[?(@.status.phase=="Pending")].metadata.name}' 2>/dev/null || echo "")

  if [ -n "$pending_pods" ]; then
    # Check why pods are pending
    echo "$pending_pods" | tr ' ' '\n' | while read -r pod; do
      if [ -n "$pod" ]; then
        local pending_reason=$(kubectl get pod "$pod" -n "$namespace" \
          -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null || echo "Unknown")
        local pending_message=$(kubectl get pod "$pod" -n "$namespace" \
          -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo "")

        # For DaemonSets, "Unschedulable" due to capacity is expected (Karpenter will provision)
        if [ "$is_daemonset" = "true" ] && [[ "$pending_message" == *"Too many pods"* ]] || [[ "$pending_message" == *"Insufficient"* ]]; then
          info "ℹ️  DaemonSet pod ${pod} is Pending due to node capacity (expected - Karpenter will provision nodes)"
          info "    Reason: ${pending_reason}"
          info "    Message: ${pending_message}"
        else
          warn "⚠️  Pod ${pod} is Pending:"
          warn "    Reason: ${pending_reason}"
          warn "    Message: ${pending_message}"
          if [ "$is_daemonset" = "false" ]; then
            # For non-DaemonSets, Pending is more concerning
            return 1
          fi
        fi
      fi
    done
  fi

  # Check for other error states (Failed, Error, etc)
  local error_pods=$(kubectl get pods -n "$namespace" -l "$selector" \
    -o jsonpath='{.items[?(@.status.phase=="Failed" || @.status.phase=="Error")].metadata.name}' 2>/dev/null || echo "")

  if [ -n "$error_pods" ]; then
    local error_states=$(kubectl get pods -n "$namespace" -l "$selector" \
      -o jsonpath='{range .items[?(@.status.phase=="Failed" || @.status.phase=="Error")]}{.metadata.name}:{.status.phase}{"\n"}{end}' 2>/dev/null || echo "")
    if [ -n "$error_states" ]; then
      warn "⚠️  Pods in error state for ${app}:"
      echo "$error_states" | sed 's/^/  /'
      return 1
    fi
  fi

  return 0
}

# Function to wait for ArgoCD app with progress feedback
wait_for_argocd_app() {
  local app=$1
  local timeout=${2:-150}  # Default 2.5 minutes
  local interval=10
  local elapsed=0

  info "Waiting for ${app} to sync and become healthy (timeout: ${timeout}s)..."

  while [ $elapsed -lt $timeout ]; do
    # Check ArgoCD app status
    local health_status=$(kubectl get application "${app}" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    local sync_status=$(kubectl get application "${app}" -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

    # Show progress
    echo -n "  [${elapsed}s] Health: ${health_status}, Sync: ${sync_status}"

    # Check for healthy status (accept Progressing for DaemonSets)
    if [ "$health_status" = "Healthy" ] || [ "$health_status" = "Progressing" ]; then
      if [ "$sync_status" = "Synced" ]; then
        echo " ✅"
        success "${app} is ${health_status} and synced"
        return 0
      fi
    fi

    # Check for error states
    if [ "$health_status" = "Degraded" ] || [ "$health_status" = "Missing" ]; then
      echo ""
      warn "⚠️  ${app} is in ${health_status} state"

      # Show ArgoCD app conditions
      info "ArgoCD application conditions:"
      kubectl get application "${app}" -n argocd \
        -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' 2>/dev/null | sed 's/^/    /' || true

      # Check pod status
      check_pod_status "$app"

      # Show recent events
      info "Recent events for ${app}:"
      kubectl get events -n observability \
        --field-selector involvedObject.name=~"${app}.*" \
        --sort-by='.lastTimestamp' \
        --tail=5 2>/dev/null | sed 's/^/    /' || true
    fi

    echo ""
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo ""
  warn "⚠️  Timeout reached for ${app} (${timeout}s)"

  # Final status check
  local final_health=$(kubectl get application "${app}" -n argocd \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  local final_sync=$(kubectl get application "${app}" -n argocd \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

  warn "  Final status - Health: ${final_health}, Sync: ${final_sync}"

  # Check pod status one more time
  check_pod_status "$app"

  return 1
}

# Wait for each application with dependency checking
for app in loki promtail kube-prometheus-stack; do
  # Determine criticality and dependencies
  is_critical="false"
  depends_on=""

  case $app in
    loki)
      is_critical="true"
      depends_on=""
      ;;
    promtail)
      is_critical="true"
      depends_on="loki"
      ;;
    kube-prometheus-stack)
      is_critical="false"
      depends_on="loki"
      ;;
  esac

  # Check if dependency is healthy
  if [ -n "$depends_on" ]; then
    dep_health=$(kubectl get application "$depends_on" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    # Accept both Healthy and Progressing for dependencies
    if [ "$dep_health" != "Healthy" ] && [ "$dep_health" != "Progressing" ]; then
      error "❌ Cannot proceed with ${app}: dependency ${depends_on} is not healthy (status: ${dep_health})"
    fi
  fi

  # Wait for app
  if ! wait_for_argocd_app "$app" 150; then
    if [ "$is_critical" = "true" ]; then
      error "❌ Critical application ${app} did not become healthy within timeout period"
    else
      warn "⚠️  Application ${app} did not become healthy (non-critical, continuing...)"
      if [ -n "$depends_on" ]; then
        warn "   Note: ${app} depends on ${depends_on}, some features may not work"
      fi
    fi
  fi

  # Show manual check commands
  info "To check ${app} status manually:"
  info "  kubectl get application ${app} -n argocd"
  case $app in
    loki)
      info "  kubectl get pods -n observability -l app.kubernetes.io/name=loki"
      info "  kubectl logs -n observability -l app.kubernetes.io/name=loki --tail=50"
      ;;
    promtail)
      info "  kubectl get pods -n observability -l app.kubernetes.io/name=promtail"
      info "  kubectl logs -n observability -l app.kubernetes.io/name=promtail --tail=50"
      ;;
    kube-prometheus-stack)
      info "  kubectl get pods -n observability -l app.kubernetes.io/name=grafana"
      info "  kubectl get pods -n observability -l app.kubernetes.io/name=prometheus"
      ;;
  esac
done

success "ArgoCD sync phase completed"

# =============================================================================
# Phase 5: Validation
# =============================================================================
info "Phase 5: Validating deployment..."

# Function to wait for pods with progress feedback
wait_for_pods() {
  local selector=$1
  local app_name=$2
  local app_key=$3  # Key for check_pod_status function
  local timeout=${4:-150}  # Default 2.5 minutes
  local interval=5
  local elapsed=0

  info "Waiting for ${app_name} pods to be ready (timeout: ${timeout}s)..."

  while [ $elapsed -lt $timeout ]; do
    local ready_count=$(kubectl get pods -n observability -l "$selector" \
      -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' 2>/dev/null | wc -w || echo "0")

    local total_count=$(kubectl get pods -n observability -l "$selector" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || echo "0")

    if [ "$total_count" -eq 0 ]; then
      echo "  [${elapsed}s] No pods found yet..."
    else
      echo "  [${elapsed}s] Ready: ${ready_count}/${total_count}"

      # Check if all pods are ready
      if [ "$ready_count" -gt 0 ] && [ "$ready_count" -eq "$total_count" ]; then
        echo " ✅"
        success "${app_name} pods are ready"
        return 0
      fi

      # Check for CrashLoopBackOff (only every 30 seconds to avoid spam)
      if [ $((elapsed % 30)) -eq 0 ]; then
        check_pod_status "$app_key" "observability" > /dev/null 2>&1 || true
      fi
    fi

    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo ""
  warn "⚠️  Timeout reached for ${app_name} pods (${timeout}s)"

  # Show final pod status
  info "Final pod status for ${app_name}:"
  kubectl get pods -n observability -l "$selector" -o wide 2>/dev/null | sed 's/^/  /' || true

  # Final check for issues
  check_pod_status "$app_key" "observability"

  return 1
}

# Wait for each component's pods
wait_for_pods "app.kubernetes.io/name=loki" "Loki" "loki" 150 || warn "Loki pods not ready yet"
wait_for_pods "app.kubernetes.io/name=promtail" "Promtail" "promtail" 150 || warn "Promtail pods not ready yet"
wait_for_pods "app.kubernetes.io/name=grafana" "Grafana" "kube-prometheus-stack" 150 || warn "Grafana pods not ready yet"

success "Pod validation phase completed"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo ""
echo "Observability Stack Status:"
echo "  ✅ Loki S3 Backend: ${LOKI_BUCKET}"
echo "  ✅ Loki IAM Role: ${LOKI_ROLE}"
echo "  ✅ ArgoCD Applications: loki, promtail, kube-prometheus-stack"
echo ""
echo "Access Grafana:"
GRAFANA_URL=$(kubectl get ingress -n observability \
  -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "${GRAFANA_HOSTNAME}")
echo "  URL: https://${GRAFANA_URL}"
echo "  Username: admin"
echo "  Password: changeme"
echo ""
echo "Check logs:"
echo "  kubectl logs -n observability -l app.kubernetes.io/name=loki"
echo "  kubectl logs -n observability -l app.kubernetes.io/name=promtail"
echo ""
echo "Next steps:"
echo "  1. Access Grafana and verify datasources"
echo "  2. Create/use Backstage templates with observability annotations"
echo "  3. View logs and metrics in Grafana"
echo "  4. Run E2E validation: ./scripts/e2e-mvp.sh"
echo ""
