#!/usr/bin/env bash
################################################################################
# Pre-Flight Check
# Validates all prerequisites before installation
# Usage: ./pre-flight-check.sh [--dry-run]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.yaml"
TERRAFORM_DIR="${REPO_ROOT}/cluster/terraform"

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]] || [[ "${DRY_RUN:-}" == "true" ]]; then
    DRY_RUN=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

ERRORS=0

info "=========================================="
info "Pre-Flight Check${DRY_RUN:+ (DRY-RUN MODE)}"
info "=========================================="
echo ""

# 1. Check config.yaml exists
if [ ! -f "$CONFIG_FILE" ]; then
    error "config.yaml not found"
    echo "  Copy config.yaml.example to config.yaml and fill in values"
    ERRORS=$((ERRORS + 1))
else
    info "✓ config.yaml exists"
fi

# 2. Validate config.yaml structure (basic check)
info "Validating config.yaml structure..."
REQUIRED_CONFIG_FIELDS=(
    "domain"
    "cluster_name"
    "region"
    "gitops.repo_url"
    "gitops.revision"
    "keycloak.image_tag"
)

for field in "${REQUIRED_CONFIG_FIELDS[@]}"; do
    value=$(yq eval ".${field}" "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -z "$value" || "$value" == "null" ]]; then
        error "Missing required field in config.yaml: ${field}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    info "✓ Config.yaml structure valid"
else
    warn "Config.yaml has missing fields - full validation will run during install"
fi

# 3. Check Terraform state
info "Checking Terraform state..."
cd "$TERRAFORM_DIR"
if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
    if terraform state list &>/dev/null 2>&1; then
        STATE_RESOURCES=$(terraform state list 2>/dev/null | wc -l || echo "0")
        if [ "$STATE_RESOURCES" -gt 0 ]; then
            if [ "$DRY_RUN" = true ]; then
                info "✓ Terraform state contains ${STATE_RESOURCES} resources (dry-run: skipping warnings)"
            else
                warn "Terraform state contains ${STATE_RESOURCES} resources"
                warn "  Run 'make clean' or 'scripts/destroy-cluster.sh' first to clean up existing cluster"
                warn "  Or proceed if you want to update existing infrastructure"
            fi
        else
            info "✓ Terraform state is empty"
        fi
    else
        info "✓ No Terraform state (fresh installation)"
    fi
else
    info "✓ No Terraform state (fresh installation)"
fi

# 4. Check AWS credentials and permissions (use darede profile)
info "Checking AWS credentials..."
# Ensure we use darede profile if no profile is set
if [ -z "${AWS_PROFILE:-}" ]; then
    export AWS_PROFILE="darede"
fi

if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured or invalid"
    error "  Login with SSO: aws sso login --profile darede"
    error "  Or set: export AWS_PROFILE=darede"
    ERRORS=$((ERRORS + 1))
else
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
    CURRENT_PROFILE="${AWS_PROFILE:-darede}"
    info "✓ AWS credentials valid (Account: ${AWS_ACCOUNT}, Profile: ${CURRENT_PROFILE})"
fi

# 5. Check GitOps repo accessibility (if private)
GITOPS_REPO_URL=$(yq eval '.gitops.repo_url' "$CONFIG_FILE" 2>/dev/null || echo "")
if [ -n "$GITOPS_REPO_URL" ]; then
    info "Checking GitOps repository access..."
    if [[ "$GITOPS_REPO_URL" == *"github.com"* ]]; then
        # Try to load GITHUB_TOKEN from config.yaml if not in ENV
        GITHUB_TOKEN="${GITHUB_TOKEN:-}"
        if [ -z "$GITHUB_TOKEN" ]; then
            GITHUB_TOKEN=$(yq eval '.secrets.github_token' "$CONFIG_FILE" 2>/dev/null || echo "")
        fi

        if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" == "null" ]; then
            error "GITHUB_TOKEN not found in ENV or config.yaml"
            error "  Set in config.yaml: secrets.github_token: <token>"
            error "  Or export: export GITHUB_TOKEN=<token>"
            ERRORS=$((ERRORS + 1))
        else
            REPO_OWNER=$(echo "$GITOPS_REPO_URL" | sed -E 's|.*github.com[:/]([^/]+)/([^/]+).*|\1/\2|' | sed 's|\.git$||')
            if curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
                "https://api.github.com/repos/${REPO_OWNER}" &>/dev/null; then
                info "✓ GitOps repository accessible"
            else
                error "Cannot access GitOps repository: ${GITOPS_REPO_URL}"
                error "  Check GITHUB_TOKEN in config.yaml or ENV"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    else
        warn "GitOps repo is not GitHub - skipping access check"
    fi
fi

# 6. Check required CLI tools
info "Checking required CLI tools..."
REQUIRED_TOOLS=("aws" "kubectl" "helm" "yq" "jq" "gomplate" "terraform")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    error "Missing required tools: ${MISSING_TOOLS[*]}"
    error "  Run 'make doctor' for installation instructions"
    for tool in "${MISSING_TOOLS[@]}"; do
        case "$tool" in
            gomplate)
                warn "  Install gomplate: brew install gomplate (macOS) or see https://docs.gomplate.ca/installing/"
                ;;
            yq)
                warn "  Install yq: brew install yq (macOS) or see https://github.com/mikefarah/yq"
                ;;
            jq)
                warn "  Install jq: brew install jq (macOS) or see https://stedolan.github.io/jq/download/"
                ;;
        esac
    done
    ERRORS=$((ERRORS + ${#MISSING_TOOLS[@]}))
else
    info "✓ All required CLI tools installed"
fi

# 7. Check Terraform outputs (if cluster exists)
info "Checking Terraform outputs..."
cd "$TERRAFORM_DIR"
if terraform state list &>/dev/null 2>&1; then
    REQUIRED_OUTPUTS=("keycloak_db_address" "external_dns_role_arn" "acm_certificate_arn")
    MISSING_OUTPUTS=()

    for output in "${REQUIRED_OUTPUTS[@]}"; do
        if ! terraform output -raw "$output" &>/dev/null 2>&1; then
            MISSING_OUTPUTS+=("$output")
        fi
    done

    if [ ${#MISSING_OUTPUTS[@]} -gt 0 ]; then
        warn "Missing Terraform outputs: ${MISSING_OUTPUTS[*]}"
        warn "  These will be created during terraform apply"
    else
        info "✓ Required Terraform outputs available"
    fi
else
    info "✓ No Terraform state (outputs will be created during installation)"
fi

# Summary
echo ""
if [ $ERRORS -eq 0 ]; then
    info "=========================================="
    info "✅ Pre-flight check passed!"
    info "=========================================="
    info ""
    if [ "$DRY_RUN" = true ]; then
        info "Dry-run completed successfully - all validations passed"
        info "Run without --dry-run to see full warnings about existing resources"
    else
        info "Ready to proceed with installation:"
        info "  Run: make install"
    fi
    exit 0
else
    error "=========================================="
    error "❌ Pre-flight check failed with ${ERRORS} error(s)"
    error "=========================================="
    error ""
    error "Please fix the errors above before proceeding"
    error ""
    error "Common fixes:"
    error "  - Set environment variables:"
    error "    export GITHUB_TOKEN=<token>"
    error "    export KEYCLOAK_ADMIN_PASSWORD=<password>"
    error "    export ARGOCD_CLIENT_SECRET=\$(openssl rand -hex 32)"
    error "    export BACKSTAGE_CLIENT_SECRET=\$(openssl rand -hex 32)"
    error "  - Configure AWS: aws configure"
    error "  - Install missing tools: make doctor"
    exit 1
fi
