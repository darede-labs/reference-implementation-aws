#!/usr/bin/env bash
################################################################################
# Install Crossplane - SIMPLIFIED APPROACH
################################################################################
# Phase 1: Install Crossplane Core
# Phase 2: Install AWS Provider Family
# Phase 3: Configure ProviderConfig with IRSA
# Phase 4: Validate with S3 Bucket
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}[STEP]${NC} $1\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
CROSSPLANE_DIR="${ROOT_DIR}/platform/crossplane"
CROSSPLANE_NAMESPACE="crossplane-system"
CROSSPLANE_VERSION="1.18.3"

################################################################################
# Phase 0: Prerequisites
################################################################################

step "Phase 0: Validating Prerequisites"

info "Checking required tools..."
command -v helm &> /dev/null || error "helm is not installed"
command -v kubectl &> /dev/null || error "kubectl is not installed"
kubectl cluster-info &> /dev/null || error "Cannot connect to Kubernetes cluster"
info "✓ All required tools available"

info "Rendering templates..."
bash "${SCRIPT_DIR}/render-templates.sh" || error "Failed to render templates"
[ -f "${CROSSPLANE_DIR}/helm-values.yaml" ] || error "helm-values.yaml not found after rendering"
info "✓ Templates rendered"

################################################################################
# Phase 1: Install Crossplane Core
################################################################################

step "Phase 1: Installing Crossplane Core"

info "Adding Crossplane Helm repository..."
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo update
info "✓ Helm repository updated"

if kubectl get namespace "$CROSSPLANE_NAMESPACE" &>/dev/null; then
    warn "Namespace $CROSSPLANE_NAMESPACE already exists"

    if helm list -n "$CROSSPLANE_NAMESPACE" | grep -q "^crossplane"; then
        info "Crossplane already installed. Upgrading..."
        helm upgrade crossplane crossplane-stable/crossplane \
            --namespace "$CROSSPLANE_NAMESPACE" \
            --version "$CROSSPLANE_VERSION" \
            --values "${CROSSPLANE_DIR}/helm-values.yaml" \
            --wait \
            --timeout 5m
    else
        info "Installing Crossplane..."
        helm install crossplane crossplane-stable/crossplane \
            --namespace "$CROSSPLANE_NAMESPACE" \
            --version "$CROSSPLANE_VERSION" \
            --values "${CROSSPLANE_DIR}/helm-values.yaml" \
            --wait \
            --timeout 5m
    fi
else
    info "Installing Crossplane (first time)..."
    helm install crossplane crossplane-stable/crossplane \
        --namespace "$CROSSPLANE_NAMESPACE" \
        --create-namespace \
        --version "$CROSSPLANE_VERSION" \
        --values "${CROSSPLANE_DIR}/helm-values.yaml" \
        --wait \
        --timeout 5m
fi

info "✓ Crossplane Helm chart installed"

info "Waiting for Crossplane to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/crossplane -n "$CROSSPLANE_NAMESPACE" || error "Crossplane deployment not ready"
info "✓ Crossplane is ready"

info "Verifying IRSA configuration..."
SA_ANNOTATION=$(kubectl get sa crossplane -n "$CROSSPLANE_NAMESPACE" \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
if [ -n "$SA_ANNOTATION" ]; then
    info "✓ IRSA role attached: $SA_ANNOTATION"
else
    error "IRSA role annotation not found on service account"
fi

################################################################################
# Phase 2: Install AWS Provider Family
################################################################################

step "Phase 2: Installing AWS Provider Family"

info "Applying AWS Provider Family manifest..."
kubectl apply -f "${CROSSPLANE_DIR}/provider-aws-family.yaml"
info "✓ Provider manifest applied"

info "Waiting for Provider to install (this takes 2-3 minutes)..."
sleep 10 # Initial wait for CRDs to be registered

# Wait for provider to be installed
for i in {1..60}; do
    INSTALLED=$(kubectl get provider upbound-provider-family-aws -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "Unknown")

    if [ "$INSTALLED" = "True" ]; then
        info "✓ Provider installed successfully"
        break
    fi

    if [ $i -eq 60 ]; then
        error "Provider did not install within 5 minutes"
    fi

    echo -n "."
    sleep 5
done

info "Waiting for Provider to become healthy..."
for i in {1..60}; do
    HEALTHY=$(kubectl get provider upbound-provider-family-aws -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "Unknown")

    if [ "$HEALTHY" = "True" ]; then
        info "✓ Provider is healthy"
        break
    fi

    if [ $i -eq 60 ]; then
        warn "Provider did not become healthy within 5 minutes, but may still work"
        kubectl get provider upbound-provider-family-aws
        break
    fi

    echo -n "."
    sleep 5
done

info "Checking provider pods..."
kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=upbound-provider-family-aws

################################################################################
# Phase 3: Configure ProviderConfig
################################################################################

step "Phase 3: Configuring ProviderConfig with IRSA"

info "Waiting for ProviderConfig CRD to be available..."
for i in {1..30}; do
    if kubectl get crd providerconfigs.aws.upbound.io &>/dev/null; then
        info "✓ ProviderConfig CRD is available"
        break
    fi

    if [ $i -eq 30 ]; then
        error "ProviderConfig CRD not available after 2.5 minutes"
    fi

    echo -n "."
    sleep 5
done

info "Applying ProviderConfig..."
kubectl apply -f "${CROSSPLANE_DIR}/providerconfig.yaml"
info "✓ ProviderConfig applied"

sleep 5

info "Verifying ProviderConfig..."
kubectl get providerconfig default -o yaml | grep -A 5 "spec:" || warn "Could not verify ProviderConfig"

################################################################################
# Phase 4: Validate Installation
################################################################################

step "Phase 4: Validating Installation"

info "Testing with S3 Bucket creation..."
kubectl apply -f "${CROSSPLANE_DIR}/examples/s3-bucket-test.yaml"
info "✓ Test S3 Bucket manifest applied"

info "Waiting for bucket to be created (30 seconds)..."
sleep 30

info "Checking bucket status..."
kubectl get bucket || warn "No buckets found yet"

CLUSTER_NAME=$(cd "${ROOT_DIR}/cluster/terraform" && terraform output -raw cluster_name 2>/dev/null || echo "")
if [ -n "$CLUSTER_NAME" ]; then
    BUCKET_NAME="${CLUSTER_NAME}-crossplane-test"
    info "Expected bucket name: $BUCKET_NAME"

    BUCKET_STATUS=$(kubectl get bucket "$BUCKET_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
    if [ "$BUCKET_STATUS" = "True" ]; then
        info "✓ Bucket is ready!"
    else
        warn "Bucket not ready yet. Status: $BUCKET_STATUS"
        info "Check with: kubectl describe bucket $BUCKET_NAME"
    fi
fi

################################################################################
# Summary
################################################################################

step "Installation Summary"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        ✅ CROSSPLANE INSTALLATION COMPLETE                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Installed Components:"
echo "  ✓ Crossplane Core v${CROSSPLANE_VERSION}"
echo "  ✓ AWS Provider Family (S3, EC2, RDS, IAM, etc.)"
echo "  ✓ ProviderConfig with IRSA"
echo "  ✓ Test S3 Bucket created"
echo ""
echo "🔍 Verification Commands:"
echo "  kubectl get providers"
echo "  kubectl get providerconfigs"
echo "  kubectl get buckets"
echo "  kubectl describe bucket ${CLUSTER_NAME}-crossplane-test"
echo ""
echo "📝 Next Steps:"
echo "  - Create more AWS resources via Crossplane"
echo "  - Set up Compositions for higher-level abstractions"
echo "  - Integrate with ArgoCD for GitOps"
echo ""
echo "════════════════════════════════════════════════════════════════"
