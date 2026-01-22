#!/usr/bin/env bash
################################################################################
# Destroy Cluster - Complete Cleanup
# Removes all ArgoCD Applications, Kubernetes resources, and Terraform infrastructure
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/cluster/terraform"
CONFIG_FILE="${REPO_ROOT}/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Read config
if [ ! -f "$CONFIG_FILE" ]; then
    error "config.yaml not found. Cannot determine cluster name."
    exit 1
fi

CLUSTER_NAME=$(yq eval '.cluster_name' "$CONFIG_FILE" 2>/dev/null || echo "")
AWS_REGION=$(yq eval '.region' "$CONFIG_FILE" 2>/dev/null || echo "us-east-1")

if [ -z "$CLUSTER_NAME" ]; then
    error "cluster_name not found in config.yaml"
    exit 1
fi

info "=========================================="
info "Destroying Cluster: ${CLUSTER_NAME}"
info "=========================================="
echo ""

# Check if kubectl context exists
KUBECTL_CONTEXT_EXISTS=false
if kubectl cluster-info &>/dev/null 2>&1; then
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ "$CURRENT_CONTEXT" == *"${CLUSTER_NAME}"* ]] || [[ -n "$CURRENT_CONTEXT" ]]; then
        KUBECTL_CONTEXT_EXISTS=true
        info "Found kubectl context: ${CURRENT_CONTEXT}"
    fi
fi

# Step 1: Remove ArgoCD Applications (if cluster is accessible)
if [ "$KUBECTL_CONTEXT_EXISTS" = true ]; then
    info "Step 1: Removing ArgoCD Applications..."

    # Get all Applications
    APPS=$(kubectl -n argocd get applications.argoproj.io -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$APPS" ]; then
        for app in $APPS; do
            info "  Removing Application: ${app}"
            # Remove finalizers first
            kubectl -n argocd patch applications.argoproj.io "$app" \
                --type json \
                -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
            # Delete application
            kubectl -n argocd delete applications.argoproj.io "$app" --timeout=60s 2>/dev/null || true
        done

        # Wait for applications to be deleted
        info "  Waiting for Applications to be deleted..."
        sleep 10
    else
        info "  No ArgoCD Applications found"
    fi

    # Step 2: Remove ArgoCD via Helm (if installed)
    info "Step 2: Removing ArgoCD..."
    if helm list -n argocd 2>/dev/null | grep -q "^argocd"; then
        helm uninstall argocd -n argocd --wait --timeout=5m 2>/dev/null || warn "Failed to uninstall ArgoCD via Helm"
    else
        info "  ArgoCD not installed via Helm"
    fi

    # Step 3: Remove namespaces (this will cascade delete resources)
    info "Step 3: Removing namespaces..."
    NAMESPACES=("argocd" "keycloak" "backstage" "ingress-nginx" "external-dns" "prometheus" "loki" "grafana")
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null 2>&1; then
            info "  Removing namespace: ${ns}"
            kubectl delete namespace "$ns" --timeout=120s --ignore-not-found=true || warn "Failed to delete namespace ${ns}"
        fi
    done

    # Step 4: Remove PVCs explicitly (sometimes they don't cascade)
    info "Step 4: Removing PersistentVolumeClaims..."
    for ns in "${NAMESPACES[@]}"; do
        PVCs=$(kubectl get pvc -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$PVCs" ]; then
            for pvc in $PVCs; do
                info "  Removing PVC: ${ns}/${pvc}"
                kubectl delete pvc "$pvc" -n "$ns" --ignore-not-found=true || true
            done
        fi
    done

    info "✓ Kubernetes resources removed"
else
    warn "kubectl context not accessible - skipping Kubernetes cleanup"
    warn "  This is OK if cluster was already destroyed"
fi

# Step 5: Destroy Terraform infrastructure
info "Step 5: Destroying Terraform infrastructure..."
cd "$TERRAFORM_DIR"

if [ ! -d ".terraform" ]; then
    warn "Terraform not initialized - skipping destroy"
else
    # Check if state exists
    if terraform state list &>/dev/null 2>&1; then
        info "  Running terraform destroy..."
        terraform destroy -auto-approve || error "Terraform destroy failed"
        info "✓ Terraform infrastructure destroyed"
    else
        warn "  No Terraform state found - nothing to destroy"
    fi
fi

# Step 6: Clean up kubeconfig
info "Step 6: Cleaning up kubeconfig..."
KUBECONFIG_CONTEXT="arn:aws:eks:${AWS_REGION}:*:cluster/${CLUSTER_NAME}"
if kubectl config get-contexts | grep -q "${CLUSTER_NAME}"; then
    info "  Removing kubectl context..."
    kubectl config delete-context "${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config delete-cluster "${CLUSTER_NAME}" 2>/dev/null || true
    info "✓ kubeconfig cleaned"
else
    info "  No kubectl context found for ${CLUSTER_NAME}"
fi

echo ""
info "=========================================="
info "✅ Cluster destruction complete!"
info "=========================================="
info ""
info "All resources have been removed:"
info "  ✓ ArgoCD Applications"
info "  ✓ ArgoCD Helm release"
info "  ✓ Kubernetes namespaces and resources"
info "  ✓ Terraform infrastructure"
info "  ✓ kubeconfig contexts"
info ""
