#!/usr/bin/env bash
################################################################################
# Install Ingress NGINX
################################################################################
# This script installs Ingress NGINX using Helm with rendered values from templates
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
INGRESS_DIR="${SCRIPT_DIR}/../platform/ingress-nginx"
INGRESS_NAMESPACE="ingress-nginx"

info "Starting Ingress NGINX installation..."

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

info "Rendering Ingress NGINX templates..."

if [ -f "${SCRIPT_DIR}/render-templates.sh" ]; then
    bash "${SCRIPT_DIR}/render-templates.sh"
else
    error "render-templates.sh not found"
fi

# Verify rendered values file exists
if [ ! -f "${INGRESS_DIR}/helm-values.yaml" ]; then
    error "Ingress NGINX helm-values.yaml not found after template rendering"
fi

info "✓ Templates rendered"

################################################################################
# Create Namespace
################################################################################

info "Creating Ingress NGINX namespace..."

kubectl create namespace "$INGRESS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

info "✓ Namespace ready"

################################################################################
# Add Ingress NGINX Helm Repository
################################################################################

info "Adding Ingress NGINX Helm repository..."

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update

info "✓ Helm repository updated"

################################################################################
# Install/Upgrade Ingress NGINX
################################################################################

if helm list -n "$INGRESS_NAMESPACE" | grep -q "^ingress-nginx"; then
    info "Ingress NGINX already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing Ingress NGINX for the first time..."
    HELM_ACTION="install"
fi

info "Running: helm $HELM_ACTION ingress-nginx..."

helm "$HELM_ACTION" ingress-nginx ingress-nginx/ingress-nginx \
    --namespace "$INGRESS_NAMESPACE" \
    --values "${INGRESS_DIR}/helm-values.yaml" \
    --wait \
    --timeout 10m

info "✓ Ingress NGINX Helm chart installed"

################################################################################
# Wait for Ingress NGINX to be Ready
################################################################################

info "Waiting for Ingress NGINX controller to be ready..."

kubectl wait --for=condition=available --timeout=300s \
    deployment/ingress-nginx-controller \
    -n "$INGRESS_NAMESPACE"

info "✓ Ingress NGINX controller is ready"

################################################################################
# Get Load Balancer DNS
################################################################################

info "Retrieving Load Balancer DNS..."

LB_DNS=$(kubectl get svc ingress-nginx-controller -n "$INGRESS_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$LB_DNS" ]; then
    info "✓ Load Balancer DNS: $LB_DNS"
    echo ""
    echo "=============================================="
    echo "Ingress NGINX Load Balancer DNS:"
    echo "$LB_DNS"
    echo "=============================================="
    echo ""
    echo "Configure your DNS records to point to this address."
else
    warn "Load Balancer DNS not yet available. Run the following command to check:"
    echo "kubectl get svc ingress-nginx-controller -n ingress-nginx"
fi

info "✓ Ingress NGINX installation complete!"
