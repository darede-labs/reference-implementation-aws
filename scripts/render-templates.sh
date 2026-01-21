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
ACM_CERTIFICATE_ARN=$(terraform output -raw acm_certificate_arn 2>/dev/null || echo "")
EXTERNAL_DNS_ROLE_ARN=$(terraform output -raw external_dns_role_arn 2>/dev/null || echo "")
CROSSPLANE_ROLE_ARN=$(terraform output -raw crossplane_role_arn 2>/dev/null || echo "")
KARPENTER_NODE_ROLE_NAME=$(terraform output -raw karpenter_node_role_name 2>/dev/null || echo "")
DOMAIN=$(yq eval '.domain' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "example.com")
GIT_REPO=$(yq eval '.git_repo_url' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "https://github.com/your-org/platform-infra")
GIT_BRANCH=$(yq eval '.git_branch' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "main")
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "argocd")
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "keycloak")
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "backstage")
CLOUD_ECONOMICS_TAG=$(yq eval '.tags.cloud_economics' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "Darede-IDP::devops")
CLOUD_ECONOMICS_TAG_KEY="cloud_economics"
CLOUD_ECONOMICS_TAG_VALUE="$CLOUD_ECONOMICS_TAG"
ENV=$(yq eval '.tags.env' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "poc")

# Karpenter configuration
KARPENTER_LIMITS_CPU=$(yq eval '.karpenter.limits.cpu' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "20")
KARPENTER_LIMITS_MEMORY=$(yq eval '.karpenter.limits.memory' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "80Gi")
KARPENTER_CONSOLIDATION_ENABLED=$(yq eval '.karpenter.consolidation_enabled' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "true")
KARPENTER_TTL_SECONDS=$(yq eval '.karpenter.ttl_seconds_after_empty' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "30")
KARPENTER_DISRUPTION_BUDGET=$(yq eval '.karpenter.disruption_budget' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "10%")

# Set consolidation policy based on config
if [ "$KARPENTER_CONSOLIDATION_ENABLED" = "true" ]; then
    KARPENTER_CONSOLIDATION_POLICY="WhenEmptyOrUnderutilized"
else
    KARPENTER_CONSOLIDATION_POLICY="Never"
fi

# Keycloak configuration
KEYCLOAK_ADMIN_USER=$(yq eval '.keycloak.admin_user' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "admin")
KEYCLOAK_ADMIN_PASSWORD=$(yq eval '.keycloak.admin_password' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "changeme")
KEYCLOAK_REPLICAS=$(yq eval '.keycloak.replicas' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "2")
KEYCLOAK_DB_ADDRESS=$(terraform output -raw keycloak_db_address 2>/dev/null || echo "")
KEYCLOAK_DB_NAME=$(terraform output -raw keycloak_db_name 2>/dev/null || echo "keycloak")
KEYCLOAK_DB_SECRET_ARN=$(terraform output -raw keycloak_db_secret_arn 2>/dev/null || echo "")
EXTERNAL_SECRETS_ROLE_ARN=$(terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")

# Get OIDC client secrets from config.yaml
ARGOCD_CLIENT_SECRET=$(yq eval '.secrets.keycloak.argocd_client_secret' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "change-argocd-secret")
BACKSTAGE_CLIENT_SECRET=$(yq eval '.secrets.keycloak.backstage_client_secret' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "change-backstage-secret")
KEYCLOAK_ARGOCD_CLIENT_SECRET="$ARGOCD_CLIENT_SECRET"

# Backstage configuration
GITHUB_ORG=$(yq eval '.github_org' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "your-org")
INFRASTRUCTURE_REPO=$(yq eval '.infrastructure_repo' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "infrastructure")
POSTGRES_HOST=$(yq eval '.secrets.backstage.postgres_host' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "backstage-postgresql")
POSTGRES_PORT=$(yq eval '.secrets.backstage.postgres_port' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "5432")
POSTGRES_USER=$(yq eval '.secrets.backstage.postgres_user' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "backstage")
TERRAFORM_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' "$ROOT_DIR/config.yaml" 2>/dev/null || echo "tfstate-bucket")

# Build hostnames
ARGOCD_HOSTNAME="${ARGOCD_SUBDOMAIN}.${DOMAIN}"
KEYCLOAK_HOSTNAME="${KEYCLOAK_SUBDOMAIN}.${DOMAIN}"
BACKSTAGE_HOSTNAME="${BACKSTAGE_SUBDOMAIN}.${DOMAIN}"

# Handle empty subdomains (path routing)
if [ -z "$ARGOCD_SUBDOMAIN" ]; then
    ARGOCD_HOSTNAME="$DOMAIN"
fi
if [ -z "$KEYCLOAK_SUBDOMAIN" ]; then
    KEYCLOAK_HOSTNAME="$DOMAIN"
fi
if [ -z "$BACKSTAGE_SUBDOMAIN" ]; then
    BACKSTAGE_HOSTNAME="$DOMAIN"
fi

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
        -e "s|{{ argocd_hostname }}|$ARGOCD_HOSTNAME|g" \
        -e "s|{{ keycloak_hostname }}|$KEYCLOAK_HOSTNAME|g" \
        -e "s|{{ backstage_hostname }}|$BACKSTAGE_HOSTNAME|g" \
        -e "s|{{ keycloak_admin_user }}|$KEYCLOAK_ADMIN_USER|g" \
        -e "s|{{ keycloak_admin_password }}|$KEYCLOAK_ADMIN_PASSWORD|g" \
        -e "s|{{ keycloak_replicas }}|$KEYCLOAK_REPLICAS|g" \
        -e "s|{{ keycloak_db_address }}|$KEYCLOAK_DB_ADDRESS|g" \
        -e "s|{{ keycloak_db_name }}|$KEYCLOAK_DB_NAME|g" \
        -e "s|{{ keycloak_db_username }}|$KEYCLOAK_DB_USERNAME|g" \
        -e "s|{{ keycloak_db_password }}|$KEYCLOAK_DB_PASSWORD|g" \
        -e "s|{{ keycloak_db_secret_arn }}|$KEYCLOAK_DB_SECRET_ARN|g" \
        -e "s|{{ external_secrets_role_arn }}|$EXTERNAL_SECRETS_ROLE_ARN|g" \
        -e "s|{{ external_dns_role_arn }}|$EXTERNAL_DNS_ROLE_ARN|g" \
        -e "s|{{ crossplane_role_arn }}|$CROSSPLANE_ROLE_ARN|g" \
        -e "s|{{ acm_certificate_arn }}|$ACM_CERTIFICATE_ARN|g" \
        -e "s|{{ cloud_economics_tag }}|$CLOUD_ECONOMICS_TAG|g" \
        -e "s|{{ cloud_economics_tag_key }}|$CLOUD_ECONOMICS_TAG_KEY|g" \
        -e "s|{{ cloud_economics_tag_value }}|$CLOUD_ECONOMICS_TAG_VALUE|g" \
        -e "s|{{ karpenter_node_role_name }}|$KARPENTER_NODE_ROLE_NAME|g" \
        -e "s|{{ env }}|$ENV|g" \
        -e "s|{{ karpenter_limits_cpu }}|$KARPENTER_LIMITS_CPU|g" \
        -e "s|{{ karpenter_limits_memory }}|$KARPENTER_LIMITS_MEMORY|g" \
        -e "s|{{ karpenter_consolidation_policy }}|$KARPENTER_CONSOLIDATION_POLICY|g" \
        -e "s|{{ karpenter_ttl_seconds }}|$KARPENTER_TTL_SECONDS|g" \
        -e "s|{{ karpenter_disruption_budget }}|$KARPENTER_DISRUPTION_BUDGET|g" \
        -e "s|{{ argocd_client_secret }}|$ARGOCD_CLIENT_SECRET|g" \
        -e "s|{{ keycloak_argocd_client_secret }}|$KEYCLOAK_ARGOCD_CLIENT_SECRET|g" \
        -e "s|{{ backstage_client_secret }}|$BACKSTAGE_CLIENT_SECRET|g" \
        -e "s|{{ github_org }}|$GITHUB_ORG|g" \
        -e "s|{{ infrastructure_repo }}|$INFRASTRUCTURE_REPO|g" \
        -e "s|{{ postgres_host }}|$POSTGRES_HOST|g" \
        -e "s|{{ postgres_port }}|$POSTGRES_PORT|g" \
        -e "s|{{ postgres_user }}|$POSTGRES_USER|g" \
        -e "s|{{ terraform_backend_bucket }}|$TERRAFORM_BACKEND_BUCKET|g" \
        "$template_file" > "$output_file"
}

# Render all .tpl files
info "Searching for .tpl files..."
find platform apps -name "*.tpl" -type f 2>/dev/null | while read -r template; do
    render_template "$template"
done

# Also render Karpenter templates if they exist
if [ -f "platform/karpenter/ec2nodeclass.yaml.tpl" ]; then
    render_template "platform/karpenter/ec2nodeclass.yaml.tpl"
fi
if [ -f "platform/karpenter/nodepool.yaml.tpl" ]; then
    render_template "platform/karpenter/nodepool.yaml.tpl"
fi

info "✓ Template rendering complete"
