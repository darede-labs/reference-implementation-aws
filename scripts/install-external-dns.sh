#!/usr/bin/env bash
################################################################################
# Install External DNS
################################################################################
# This script installs External DNS using Helm with IRSA for Route53 access
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
EXTERNAL_DNS_DIR="${SCRIPT_DIR}/../platform/external-dns"
EXTERNAL_DNS_NAMESPACE="external-dns"

info "Starting External DNS installation..."

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

info "Rendering External DNS templates..."

if [ -f "${SCRIPT_DIR}/render-templates.sh" ]; then
    bash "${SCRIPT_DIR}/render-templates.sh"
else
    error "render-templates.sh not found"
fi

# Verify rendered values file exists
if [ ! -f "${EXTERNAL_DNS_DIR}/helm-values.yaml" ]; then
    error "External DNS helm-values.yaml not found after template rendering"
fi

info "✓ Templates rendered"

################################################################################
# Create Namespace
################################################################################

info "Creating External DNS namespace..."

kubectl create namespace "$EXTERNAL_DNS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

info "✓ Namespace ready"

################################################################################
# Add External DNS Helm Repository
################################################################################

info "Adding External DNS Helm repository..."

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns 2>/dev/null || true
helm repo update

info "✓ Helm repository updated"

################################################################################
# Install/Upgrade External DNS
################################################################################

if helm list -n "$EXTERNAL_DNS_NAMESPACE" | grep -q "^external-dns"; then
    info "External DNS already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing External DNS for the first time..."
    HELM_ACTION="install"
fi

info "Running: helm $HELM_ACTION external-dns..."

helm "$HELM_ACTION" external-dns external-dns/external-dns \
    --namespace "$EXTERNAL_DNS_NAMESPACE" \
    --values "${EXTERNAL_DNS_DIR}/helm-values.yaml" \
    --wait \
    --timeout 5m

info "✓ External DNS Helm chart installed"

################################################################################
# Wait for External DNS to be Ready
################################################################################

info "Waiting for External DNS to be ready..."

kubectl wait --for=condition=available --timeout=180s \
    deployment/external-dns \
    -n "$EXTERNAL_DNS_NAMESPACE" 2>/dev/null || true

info "✓ External DNS is ready"

################################################################################
# Verify IRSA Configuration
################################################################################

info "Verifying IRSA configuration..."

SA_ANNOTATION=$(kubectl get sa external-dns -n "$EXTERNAL_DNS_NAMESPACE" \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

if [ -n "$SA_ANNOTATION" ]; then
    info "✓ IRSA role attached: $SA_ANNOTATION"
else
    warn "IRSA role annotation not found. External DNS may not have Route53 access."
fi

info "✓ External DNS installation complete!"
echo ""
echo "External DNS will automatically create DNS records for Ingress resources."
