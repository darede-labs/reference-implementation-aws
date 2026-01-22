#!/usr/bin/env bash
################################################################################
# Install ArgoCD
################################################################################
# This script installs ArgoCD using Helm with rendered values from templates
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_DIR="${SCRIPT_DIR}/../platform/argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-7.7.0}"
ARGOCD_NAMESPACE="argocd"

info "Starting ArgoCD installation..."

################################################################################
# Validate Prerequisites
################################################################################

info "Validating prerequisites..."

if ! command -v helm &> /dev/null; then
    error "helm is not installed"
fi

if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed"
fi

if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
fi

info "✓ Prerequisites validated"

################################################################################
# Render Templates
################################################################################

info "Rendering ArgoCD templates..."

if [ -f "${SCRIPT_DIR}/render-templates.sh" ]; then
    bash "${SCRIPT_DIR}/render-templates.sh"
else
    error "render-templates.sh not found"
fi

# Verify rendered values file exists
if [ ! -f "${ARGOCD_DIR}/helm-values.yaml" ]; then
    error "ArgoCD helm-values.yaml not found after template rendering"
fi

info "✓ Templates rendered"

################################################################################
# Create Namespace
################################################################################

info "Creating ArgoCD namespace..."

kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

info "✓ Namespace ready"

################################################################################
# Add Argo Helm Repository
################################################################################

info "Adding Argo Helm repository..."

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

info "✓ Helm repository updated"

################################################################################
# Install/Upgrade ArgoCD
################################################################################

if helm list -n "$ARGOCD_NAMESPACE" | grep -q "^argocd"; then
    info "ArgoCD already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing ArgoCD for the first time..."
    HELM_ACTION="install"
fi

info "Running: helm $HELM_ACTION argocd..."

helm "$HELM_ACTION" argocd argo/argo-cd \
    --namespace "$ARGOCD_NAMESPACE" \
    --version "$ARGOCD_VERSION" \
    --values "${ARGOCD_DIR}/helm-values.yaml" \
    --wait \
    --timeout 10m

info "✓ ArgoCD Helm chart installed"

################################################################################
# Wait for ArgoCD to be Ready
################################################################################

info "Waiting for ArgoCD server to be ready..."

kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    -n "$ARGOCD_NAMESPACE"

info "✓ ArgoCD server is ready"

################################################################################
# Get Initial Admin Password
################################################################################

info "Retrieving ArgoCD initial admin password..."

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -n "$ADMIN_PASSWORD" ]; then
    info "✓ Admin password retrieved (save this securely)"
    echo ""
    echo "=========================================="
    echo "ArgoCD Admin Credentials:"
    echo "Username: admin"
    echo "Password: $ADMIN_PASSWORD"
    echo "=========================================="
    echo ""
else
    warn "Could not retrieve admin password (may not exist yet)"
fi

################################################################################
# Apply Bootstrap App-of-Apps (if exists)
################################################################################

if [ -f "${ARGOCD_DIR}/bootstrap-apps.yaml" ]; then
    info "Applying bootstrap app-of-apps..."
    kubectl apply -f "${ARGOCD_DIR}/bootstrap-apps.yaml"
    info "✓ Bootstrap application created"
else
    warn "bootstrap-apps.yaml not found, skipping app-of-apps setup"
fi

################################################################################
# Display Status
################################################################################

info "ArgoCD installation summary:"
kubectl get deployment,svc -n "$ARGOCD_NAMESPACE"

echo ""
info "=========================================="
info "✓ ArgoCD installation completed successfully!"
info "=========================================="
echo ""
info "Access ArgoCD:"
info "1. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
info "2. Open: https://localhost:8080"
info "3. Login with admin / $ADMIN_PASSWORD"
echo ""
info "Or access via ingress (if configured):"
info "https://argocd.yourdomain.com"
echo ""
