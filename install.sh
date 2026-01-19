#!/usr/bin/env bash
################################################################################
# IDP Platform - One-Shot Installer
################################################################################
# This script installs the complete platform from scratch:
# 1. Infrastructure (Terraform)
# 2. Platform components (Karpenter, ArgoCD, Keycloak)
# 3. Applications (Backstage)
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
step() { echo -e "\n${BLUE}==>${NC} ${BLUE}$1${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse flags
DRY_RUN=false
SKIP_TERRAFORM=false
SKIP_APPS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=true
      shift
      ;;
    --skip-apps)
      SKIP_APPS=true
      shift
      ;;
    -h|--help)
      cat << EOF
Usage: $0 [OPTIONS]

Install complete IDP platform from scratch.

OPTIONS:
  --dry-run           Show what would be done without executing
  --skip-terraform    Skip Terraform apply (cluster already exists)
  --skip-apps         Skip application installation (only infra)
  -h, --help          Show this help message

EXAMPLES:
  # Full installation
  $0

  # Dry run (show steps)
  $0 --dry-run

  # Only install apps (cluster exists)
  $0 --skip-terraform

EOF
      exit 0
      ;;
    *)
      error "Unknown option: $1. Use --help for usage."
      ;;
  esac
done

if [ "$DRY_RUN" = true ]; then
  info "DRY RUN MODE - No changes will be made"
fi

################################################################################
# Phase 0: Pre-flight checks
################################################################################

step "Phase 0: Pre-flight Checks"

# Check required tools
info "Checking required tools..."
for tool in terraform kubectl helm aws jq yq; do
  if ! command -v $tool &> /dev/null; then
    error "$tool is not installed. Please install it first."
  fi
  info "✓ $tool found"
done

# Check config.yaml exists
if [ ! -f "config.yaml" ]; then
  error "config.yaml not found. Copy config.yaml.example and customize it."
fi
info "✓ config.yaml found"

# Validate config.yaml
info "Validating config.yaml..."
if [ -f "scripts/validate-config.sh" ]; then
  bash scripts/validate-config.sh || error "config.yaml validation failed"
else
  warn "validate-config.sh not found, skipping validation"
fi

# Check AWS credentials
info "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
  error "AWS credentials not configured. Run: aws configure"
fi
info "✓ AWS credentials valid"

################################################################################
# Phase 1: Infrastructure (Terraform)
################################################################################

if [ "$SKIP_TERRAFORM" = false ]; then
  step "Phase 1: Infrastructure Provisioning (Terraform)"

  cd cluster/terraform

  info "Initializing Terraform..."
  if [ "$DRY_RUN" = false ]; then
    terraform init
  fi

  info "Planning infrastructure..."
  if [ "$DRY_RUN" = false ]; then
    terraform plan -out=tfplan
  fi

  info "Applying infrastructure..."
  if [ "$DRY_RUN" = false ]; then
    terraform apply tfplan
    rm -f tfplan
  else
    info "[DRY RUN] Would run: terraform apply"
  fi

  cd "$SCRIPT_DIR"

  # Update kubeconfig
  info "Updating kubeconfig..."
  if [ "$DRY_RUN" = false ]; then
    CLUSTER_NAME=$(cd cluster/terraform && terraform output -raw cluster_name)
    REGION=$(cd cluster/terraform && terraform output -raw region)
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
  fi

  # Wait for cluster to be ready
  info "Waiting for cluster to be ready..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "cluster/bootstrap/healthcheck.sh" ]; then
      bash cluster/bootstrap/healthcheck.sh
    else
      info "Waiting 60 seconds for cluster stabilization..."
      sleep 60
    fi
  fi
else
  info "Skipping Terraform (--skip-terraform)"
fi

################################################################################
# Phase 2: Platform Components
################################################################################

if [ "$SKIP_APPS" = false ]; then
  step "Phase 2: Platform Components"

  # Render templates
  info "Rendering manifest templates..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "scripts/render-templates.sh" ]; then
      bash scripts/render-templates.sh
    else
      # Fallback: use existing generate scripts
      if [ -f "scripts/generate-karpenter-manifests.sh" ]; then
        bash scripts/generate-karpenter-manifests.sh
      fi
    fi
  fi

  # Install Karpenter
  info "Installing Karpenter..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "scripts/install-karpenter.sh" ]; then
      bash scripts/install-karpenter.sh
    else
      warn "install-karpenter.sh not found, skipping"
    fi
  fi

  # Install ArgoCD (if configured)
  info "Installing ArgoCD..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "scripts/install-argocd.sh" ]; then
      bash scripts/install-argocd.sh
    else
      info "ArgoCD install script not found yet, skipping for now"
    fi
  fi

  # Install Keycloak (if configured)
  info "Installing Keycloak..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "scripts/install-keycloak.sh" ]; then
      bash scripts/install-keycloak.sh
    else
      info "Keycloak install script not found yet, skipping for now"
    fi
  fi

################################################################################
# Phase 3: Applications
################################################################################

  step "Phase 3: Applications"

  # Install Backstage (if configured)
  info "Installing Backstage..."
  if [ "$DRY_RUN" = false ]; then
    if [ -f "apps/backstage/install.sh" ]; then
      bash apps/backstage/install.sh
    else
      info "Backstage install script not found yet, skipping for now"
    fi
  fi
else
  info "Skipping application installation (--skip-apps)"
fi

################################################################################
# Success
################################################################################

step "Installation Complete!"

info "=========================================="
info "✓ Platform installed successfully!"
info "=========================================="
echo ""

if [ "$DRY_RUN" = false ] && [ "$SKIP_TERRAFORM" = false ]; then
  CLUSTER_NAME=$(cd cluster/terraform && terraform output -raw cluster_name 2>/dev/null || echo "unknown")
  NLB_DNS=$(cd cluster/terraform && terraform output -raw nlb_dns_name 2>/dev/null || echo "unknown")

  info "Cluster: $CLUSTER_NAME"
  info "Load Balancer: $NLB_DNS"
  echo ""
  info "Next steps:"
  info "1. Wait for DNS propagation (if using custom domain)"
  info "2. Access applications:"
  info "   - Backstage: https://backstage.<your-domain>"
  info "   - ArgoCD: https://argocd.<your-domain>"
  info "   - Keycloak: https://keycloak.<your-domain>"
  info "3. Check logs: kubectl get pods -A"
fi

echo ""
