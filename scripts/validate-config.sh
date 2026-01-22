#!/usr/bin/env bash
################################################################################
# Validate Configuration
# Validates config.yaml (non-sensitive fields) and required environment variables
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

ERRORS=0

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    error "Config file not found: $CONFIG_FILE"
    echo "  Copy config.yaml.example to config.yaml and fill in your values"
    exit 1
fi

info "Validating configuration..."

# 1. Validate required config.yaml fields (non-sensitive)
REQUIRED_CONFIG_FIELDS=(
    "domain"
    "cluster_name"
    "region"
    "github_org"
    "acm_certificate_arn"
    "route53_hosted_zone_id"
    "subdomains.argocd"
    "subdomains.keycloak"
    "subdomains.backstage"
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

# Validate gitops.repo_url is not a placeholder
GITOPS_REPO_URL=$(yq eval '.gitops.repo_url' "$CONFIG_FILE")
if [[ "$GITOPS_REPO_URL" == *"<org>"* ]] || [[ "$GITOPS_REPO_URL" == *"<repo>"* ]]; then
    error "gitops.repo_url contains placeholder values. Please set actual repository URL."
    ERRORS=$((ERRORS + 1))
fi

# 2. Validate required environment variables (can come from ENV or config.yaml)
# Load utils to check if secrets can be loaded
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true

info "Validating secrets (from ENV or config.yaml)..."

# Check GITHUB_TOKEN (required for private repos)
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$GITHUB_TOKEN" ]; then
    GITHUB_TOKEN=$(yq eval '.secrets.github_token' "$CONFIG_FILE" 2>/dev/null || echo "")
fi
if [[ -z "$GITHUB_TOKEN" || "$GITHUB_TOKEN" == "null" ]]; then
    error "GITHUB_TOKEN not found in ENV or config.yaml"
    error "  Set in config.yaml: secrets.github_token: <token>"
    error "  Or export: export GITHUB_TOKEN=<token>"
    ERRORS=$((ERRORS + 1))
else
    info "✓ GITHUB_TOKEN found"
fi

# Other secrets will be auto-generated if not set, so we don't require them here
# They will be validated during bootstrap

# 3. Validate AWS credentials
info "Validating AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials not configured or invalid"
    echo "  Configure with: aws configure"
    echo "  Or set AWS_PROFILE: export AWS_PROFILE=your-profile"
    ERRORS=$((ERRORS + 1))
fi

# 4. Validate kubectl context
info "Validating kubectl context..."
if ! kubectl cluster-info &>/dev/null; then
    warn "kubectl not configured or cluster not accessible"
    warn "  This is OK if you're installing on a new cluster"
    warn "  Make sure to configure kubectl after cluster creation"
else
    CLUSTER_NAME=$(yq eval '.cluster_name' "$CONFIG_FILE")
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -n "$CURRENT_CONTEXT" ]]; then
        info "  Current kubectl context: $CURRENT_CONTEXT"
    fi
fi

# Summary
if [[ $ERRORS -gt 0 ]]; then
    echo ""
    error "Validation failed with $ERRORS error(s)"
    echo ""
    echo "Required environment variables:"
    echo "  export GITHUB_TOKEN=<token>"
    echo "  export KEYCLOAK_ADMIN_PASSWORD=<password>"
    echo "  export ARGOCD_CLIENT_SECRET=<secret>"
    echo "  export BACKSTAGE_CLIENT_SECRET=<secret>"
    echo ""
    echo "Example:"
    echo "  export ARGOCD_CLIENT_SECRET=\$(openssl rand -hex 32)"
    echo "  export BACKSTAGE_CLIENT_SECRET=\$(openssl rand -hex 32)"
    exit 1
fi

echo ""
info "✅ Configuration validated successfully"
