#!/usr/bin/env bash
################################################################################
# Render Templates
################################################################################
# This script renders all .tpl files using values from Terraform outputs
# and config.yaml
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../cluster/terraform"
ROOT_DIR="${SCRIPT_DIR}/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

info "Rendering templates from Terraform outputs and config.yaml..."

cd "$TERRAFORM_DIR"

# Get values from Terraform
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "")
DOMAIN=$(yq eval '.domain' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "example.com")
GIT_REPO=$(yq eval '.git_repo_url' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "https://github.com/your-org/platform-infra")
GIT_BRANCH=$(yq eval '.git_branch' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "main")
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "argocd")

if [ -z "$CLUSTER_NAME" ]; then
    warn "Terraform outputs not available, using defaults from config.yaml"
    CLUSTER_NAME=$(yq eval '.cluster_name' "$ROOT_DIR/config.yaml")
fi

cd "$ROOT_DIR"

# Function to render a template
render_template() {
    local template_file=$1
    local output_file="${template_file%.tpl}"
    
    info "Rendering: $template_file -> $output_file"
    
    # Simple sed-based templating (for more complex needs, use envsubst or j2)
    sed -e "s|{{ cluster_name }}|$CLUSTER_NAME|g" \
        -e "s|{{ region }}|$REGION|g" \
        -e "s|{{ domain }}|$DOMAIN|g" \
        -e "s|{{ git_repo_url }}|$GIT_REPO|g" \
        -e "s|{{ git_branch }}|$GIT_BRANCH|g" \
        -e "s|{{ argocd_subdomain }}|$ARGOCD_SUBDOMAIN|g" \
        "$template_file" > "$output_file"
}

# Render all .tpl files
info "Searching for .tpl files..."
find platform apps -name "*.tpl" -type f 2>/dev/null | while read -r template; do
    render_template "$template"
done

info "✓ Template rendering complete"
