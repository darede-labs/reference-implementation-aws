#!/usr/bin/env bash
################################################################################
# Install Karpenter on EKS Cluster
################################################################################
# This script installs Karpenter after the EKS cluster is provisioned.
# It should be run AFTER terraform apply completes successfully.
#
# Prerequisites:
# - EKS cluster is running
# - kubectl configured (aws eks update-kubeconfig)
# - Terraform outputs available
# - AWS CLI configured with correct profile
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
KARPENTER_NAMESPACE="karpenter"

info "Starting Karpenter installation..."

################################################################################
# Validate Prerequisites
################################################################################

info "Validating prerequisites..."

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    error "Terraform directory not found: $TERRAFORM_DIR"
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in PATH"
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    error "helm is not installed or not in PATH"
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster. Run: aws eks update-kubeconfig --name <cluster-name> --region us-east-1"
fi

info "✓ Prerequisites validated"

################################################################################
# Get Terraform Outputs
################################################################################

info "Fetching Terraform outputs..."

cd "$TERRAFORM_DIR"

CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null) || error "Failed to get cluster_name from Terraform"
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null) || error "Failed to get cluster_endpoint from Terraform"
KARPENTER_QUEUE=$(terraform output -raw karpenter_queue_name 2>/dev/null) || error "Failed to get karpenter_queue_name from Terraform"
KARPENTER_IRSA_ARN=$(terraform output -raw karpenter_irsa_arn 2>/dev/null) || error "Failed to get karpenter_irsa_arn from Terraform"
KARPENTER_VERSION=$(terraform output -raw karpenter_version 2>/dev/null) || error "Failed to get karpenter_version from Terraform"

info "✓ Terraform outputs fetched"
info "  Cluster: $CLUSTER_NAME"
info "  Queue: $KARPENTER_QUEUE"

################################################################################
# Check if Karpenter is already installed
################################################################################

if helm list -n "$KARPENTER_NAMESPACE" | grep -q "^karpenter"; then
    warn "Karpenter is already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing Karpenter for the first time..."
    HELM_ACTION="install"
fi

################################################################################
# Login to ECR Public (for Karpenter Helm chart)
################################################################################

info "Authenticating to ECR Public..."

if ! aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws 2>/dev/null; then
    warn "Failed to login to ECR Public (non-critical, may still work)"
fi

################################################################################
# Install/Upgrade Karpenter Helm Chart
################################################################################

info "Installing Karpenter Helm chart (version $KARPENTER_VERSION)..."

helm "$HELM_ACTION" karpenter oci://public.ecr.aws/karpenter/karpenter \
    --version "$KARPENTER_VERSION" \
    --namespace "$KARPENTER_NAMESPACE" \
    --set "settings.clusterName=$CLUSTER_NAME" \
    --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
    --set "settings.interruptionQueue=$KARPENTER_QUEUE" \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$KARPENTER_IRSA_ARN" \
    --set "replicas=2" \
    --set "resources.requests.cpu=100m" \
    --set "resources.requests.memory=128Mi" \
    --set "resources.limits.cpu=1000m" \
    --set "resources.limits.memory=512Mi" \
    --wait \
    --timeout 5m

info "✓ Karpenter Helm chart installed"

################################################################################
# Wait for Karpenter Controller to be Ready
################################################################################

info "Waiting for Karpenter controller to be ready..."

if ! kubectl wait --for=condition=available --timeout=300s deployment/karpenter -n "$KARPENTER_NAMESPACE"; then
    error "Karpenter controller did not become ready within 5 minutes"
fi

info "✓ Karpenter controller is ready"

################################################################################
# Display Karpenter Status
################################################################################

info "Karpenter installation summary:"
kubectl get deployment karpenter -n "$KARPENTER_NAMESPACE"
kubectl get pods -n "$KARPENTER_NAMESPACE" -l app.kubernetes.io/name=karpenter

################################################################################
# Apply NodePool and NodeClass (if they exist)
################################################################################

KARPENTER_MANIFESTS_DIR="${SCRIPT_DIR}/../../packages/karpenter"

if [ -d "$KARPENTER_MANIFESTS_DIR" ]; then
    info "Applying Karpenter NodePool and EC2NodeClass..."

    if [ -f "$KARPENTER_MANIFESTS_DIR/nodepool.yaml" ]; then
        kubectl apply -f "$KARPENTER_MANIFESTS_DIR/nodepool.yaml"
        info "✓ NodePool applied"
    else
        warn "NodePool manifest not found: $KARPENTER_MANIFESTS_DIR/nodepool.yaml"
    fi

    if [ -f "$KARPENTER_MANIFESTS_DIR/ec2nodeclass.yaml" ]; then
        kubectl apply -f "$KARPENTER_MANIFESTS_DIR/ec2nodeclass.yaml"
        info "✓ EC2NodeClass applied"
    else
        warn "EC2NodeClass manifest not found: $KARPENTER_MANIFESTS_DIR/ec2nodeclass.yaml"
    fi
else
    warn "Karpenter manifests directory not found: $KARPENTER_MANIFESTS_DIR"
    warn "You need to manually create NodePool and EC2NodeClass resources"
fi

################################################################################
# Success
################################################################################

echo ""
info "=========================================="
info "✓ Karpenter installation completed successfully!"
info "=========================================="
echo ""
info "Next steps:"
info "1. Verify Karpenter is running: kubectl get pods -n $KARPENTER_NAMESPACE -l app.kubernetes.io/name=karpenter"
info "2. Check NodePools: kubectl get nodepools"
info "3. Check EC2NodeClasses: kubectl get ec2nodeclasses"
info "4. Deploy a test workload to trigger Karpenter provisioning"
echo ""
