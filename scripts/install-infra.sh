#!/usr/bin/env bash
################################################################################
# Install Infrastructure via Terraform
# Wrapper script for Terraform apply
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
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Validate Terraform is installed
if ! command -v terraform &> /dev/null; then
    error "terraform is not installed"
fi

# Read config
CLUSTER_NAME=$(yq eval '.cluster_name' "$CONFIG_FILE")
AWS_REGION=$(yq eval '.region' "$CONFIG_FILE")
BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' "$CONFIG_FILE" 2>/dev/null || echo "")
BACKEND_KEY=$(yq eval '.terraform_backend.key' "$CONFIG_FILE" 2>/dev/null)
BACKEND_REGION=$(yq eval '.terraform_backend.region' "$CONFIG_FILE" 2>/dev/null || echo "$AWS_REGION")

# Default backend key if not specified
if [ -z "$BACKEND_KEY" ] || [ "$BACKEND_KEY" = "null" ]; then
    BACKEND_KEY="cluster-state/terraform.tfstate"
fi

# Use darede AWS profile if not set
if [ -z "${AWS_PROFILE:-}" ]; then
    export AWS_PROFILE="darede"
fi

info "Provisioning infrastructure with Terraform..."
info "Cluster: ${CLUSTER_NAME}"
info "Region: ${AWS_REGION}"
echo ""

cd "$TERRAFORM_DIR"

# Initialize Terraform with backend configuration
info "Initializing Terraform..."
if [ -n "$BACKEND_BUCKET" ] && [ "$BACKEND_BUCKET" != "null" ]; then
    info "Using S3 backend: bucket=${BACKEND_BUCKET}, key=${BACKEND_KEY}, region=${BACKEND_REGION}"
    terraform init \
        -backend-config="bucket=${BACKEND_BUCKET}" \
        -backend-config="key=${BACKEND_KEY}" \
        -backend-config="region=${BACKEND_REGION}" \
        -upgrade || terraform init \
        -backend-config="bucket=${BACKEND_BUCKET}" \
        -backend-config="key=${BACKEND_KEY}" \
        -backend-config="region=${BACKEND_REGION}"
else
    warn "No backend bucket configured, using local state"
    terraform init -upgrade || terraform init
fi

# Plan and apply
info "Running terraform plan..."
terraform plan -out=tfplan

info "Applying Terraform changes..."
terraform apply tfplan

info "✓ Infrastructure provisioned"

# Update kubeconfig
info "Updating kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || warn "Failed to update kubeconfig (cluster may still be creating)"

info "✓ Infrastructure installation complete"
