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
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "keycloak")
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "backstage")

# Keycloak configuration
KEYCLOAK_ADMIN_USER=$(yq eval '.keycloak.admin_user' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "admin")
KEYCLOAK_ADMIN_PASSWORD=$(yq eval '.keycloak.admin_password' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "changeme")
KEYCLOAK_REPLICAS=$(yq eval '.keycloak.replicas' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "2")
KEYCLOAK_DB_ADDRESS=$(terraform output -raw keycloak_db_address 2>/dev/null || echo "")
KEYCLOAK_DB_NAME=$(terraform output -raw keycloak_db_name 2>/dev/null || echo "keycloak")
KEYCLOAK_DB_SECRET_ARN=$(terraform output -raw keycloak_db_secret_arn 2>/dev/null || echo "")
EXTERNAL_SECRETS_ROLE_ARN=$(terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")

# Generate random client secrets if not set
ARGOCD_CLIENT_SECRET=$(openssl rand -base64 32 2>/dev/null || echo "change-argocd-secret")
BACKSTAGE_CLIENT_SECRET=$(openssl rand -base64 32 2>/dev/null || echo "change-backstage-secret")

# Get DB credentials from Secrets Manager (for template rendering)
if [ -n "$KEYCLOAK_DB_SECRET_ARN" ]; then
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$KEYCLOAK_DB_SECRET_ARN" --region "$REGION" --query SecretString --output text 2>/dev/null || echo "{}")
    KEYCLOAK_DB_USERNAME=$(echo "$SECRET_JSON" | jq -r .username 2>/dev/null || echo "keycloak")
    KEYCLOAK_DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r .password 2>/dev/null || echo "")
else
    KEYCLOAK_DB_USERNAME="keycloak"
    KEYCLOAK_DB_PASSWORD=""
fi

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
        -e "s|{{ keycloak_subdomain }}|$KEYCLOAK_SUBDOMAIN|g" \
        -e "s|{{ backstage_subdomain }}|$BACKSTAGE_SUBDOMAIN|g" \
        -e "s|{{ keycloak_admin_user }}|$KEYCLOAK_ADMIN_USER|g" \
        -e "s|{{ keycloak_admin_password }}|$KEYCLOAK_ADMIN_PASSWORD|g" \
        -e "s|{{ keycloak_replicas }}|$KEYCLOAK_REPLICAS|g" \
        -e "s|{{ keycloak_db_address }}|$KEYCLOAK_DB_ADDRESS|g" \
        -e "s|{{ keycloak_db_name }}|$KEYCLOAK_DB_NAME|g" \
        -e "s|{{ keycloak_db_username }}|$KEYCLOAK_DB_USERNAME|g" \
        -e "s|{{ keycloak_db_password }}|$KEYCLOAK_DB_PASSWORD|g" \
        -e "s|{{ keycloak_db_secret_arn }}|$KEYCLOAK_DB_SECRET_ARN|g" \
        -e "s|{{ external_secrets_role_arn }}|$EXTERNAL_SECRETS_ROLE_ARN|g" \
        -e "s|{{ argocd_client_secret }}|$ARGOCD_CLIENT_SECRET|g" \
        -e "s|{{ backstage_client_secret }}|$BACKSTAGE_CLIENT_SECRET|g" \
        "$template_file" > "$output_file"
}

# Render all .tpl files
info "Searching for .tpl files..."
find platform apps -name "*.tpl" -type f 2>/dev/null | while read -r template; do
    render_template "$template"
done

info "✓ Template rendering complete"
