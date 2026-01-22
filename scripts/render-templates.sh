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

# Ensure AWS profile is set for Terraform outputs (same default as install-infra.sh)
if [ -z "${AWS_PROFILE:-}" ]; then
    export AWS_PROFILE="darede"
fi

# Get all Terraform outputs in one call (much faster)
TF_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")

# Get all config.yaml values in one call (much faster)
CONFIG_VALUES=$(yq eval -o=json "$ROOT_DIR/config.yaml" 2>/dev/null || echo "{}")

# Extract values from Terraform outputs (with defaults)
CLUSTER_NAME=$(echo "$TF_OUTPUTS" | jq -r '.cluster_name.value // ""' 2>/dev/null || echo "")
REGION=$(echo "$TF_OUTPUTS" | jq -r '.region.value // ""' 2>/dev/null || echo "")
ACM_CERTIFICATE_ARN=$(echo "$TF_OUTPUTS" | jq -r '.acm_certificate_arn.value // ""' 2>/dev/null || echo "")
EXTERNAL_DNS_ROLE_ARN=$(echo "$TF_OUTPUTS" | jq -r '.external_dns_role_arn.value // ""' 2>/dev/null || echo "")
CROSSPLANE_ROLE_ARN=$(echo "$TF_OUTPUTS" | jq -r '.crossplane_role_arn.value // ""' 2>/dev/null || echo "")
KARPENTER_NODE_ROLE_NAME=$(echo "$TF_OUTPUTS" | jq -r '.karpenter_node_role_name.value // ""' 2>/dev/null || echo "")
KARPENTER_INSTANCE_PROFILE_NAME=$(echo "$TF_OUTPUTS" | jq -r '.karpenter_instance_profile_name.value // ""' 2>/dev/null || echo "")
KEYCLOAK_DB_ADDRESS=$(echo "$TF_OUTPUTS" | jq -r '.keycloak_db_address.value // ""' 2>/dev/null || echo "")
KEYCLOAK_DB_NAME=$(echo "$TF_OUTPUTS" | jq -r '.keycloak_db_name.value // "keycloak"' 2>/dev/null || echo "keycloak")
KEYCLOAK_DB_SECRET_ARN=$(echo "$TF_OUTPUTS" | jq -r '.keycloak_db_secret_arn.value // ""' 2>/dev/null || echo "")
EXTERNAL_SECRETS_ROLE_ARN=$(echo "$TF_OUTPUTS" | jq -r '.external_secrets_role_arn.value // ""' 2>/dev/null || echo "")

# Extract values from config.yaml (with defaults)
DOMAIN=$(echo "$CONFIG_VALUES" | jq -r '.domain // "example.com"' 2>/dev/null || echo "example.com")
GIT_REPO=$(echo "$CONFIG_VALUES" | jq -r '.git_repo_url // "https://github.com/your-org/platform-infra"' 2>/dev/null || echo "https://github.com/your-org/platform-infra")
GIT_BRANCH=$(echo "$CONFIG_VALUES" | jq -r '.git_branch // "main"' 2>/dev/null || echo "main")
GITOPS_REPO_URL=$(echo "$CONFIG_VALUES" | jq -r '.gitops.repo_url // .git_repo_url // "https://github.com/your-org/platform-infra"' 2>/dev/null || echo "https://github.com/your-org/platform-infra")
GITOPS_BRANCH=$(echo "$CONFIG_VALUES" | jq -r '.gitops.revision // .git_branch // "main"' 2>/dev/null || echo "main")
ARGOCD_SUBDOMAIN=$(echo "$CONFIG_VALUES" | jq -r '.subdomains.argocd // "argocd"' 2>/dev/null || echo "argocd")
KEYCLOAK_SUBDOMAIN=$(echo "$CONFIG_VALUES" | jq -r '.subdomains.keycloak // "keycloak"' 2>/dev/null || echo "keycloak")
BACKSTAGE_SUBDOMAIN=$(echo "$CONFIG_VALUES" | jq -r '.subdomains.backstage // "backstage"' 2>/dev/null || echo "backstage")
CLOUD_ECONOMICS_TAG=$(echo "$CONFIG_VALUES" | jq -r '.tags.cloud_economics // "Darede-IDP::devops"' 2>/dev/null || echo "Darede-IDP::devops")
ENV=$(echo "$CONFIG_VALUES" | jq -r '.tags.env // "poc"' 2>/dev/null || echo "poc")
CLOUD_ECONOMICS_TAG_KEY="cloud_economics"
CLOUD_ECONOMICS_TAG_VALUE="$CLOUD_ECONOMICS_TAG"

# Karpenter configuration
KARPENTER_LIMITS_CPU=$(echo "$CONFIG_VALUES" | jq -r '.karpenter.limits.cpu // "20"' 2>/dev/null || echo "20")
KARPENTER_LIMITS_MEMORY=$(echo "$CONFIG_VALUES" | jq -r '.karpenter.limits.memory // "80Gi"' 2>/dev/null || echo "80Gi")
KARPENTER_CONSOLIDATION_ENABLED=$(echo "$CONFIG_VALUES" | jq -r '.karpenter.consolidation_enabled // "true"' 2>/dev/null || echo "true")
KARPENTER_TTL_SECONDS=$(echo "$CONFIG_VALUES" | jq -r '.karpenter.ttl_seconds_after_empty // "30"' 2>/dev/null || echo "30")
KARPENTER_DISRUPTION_BUDGET=$(echo "$CONFIG_VALUES" | jq -r '.karpenter.disruption_budget // "10%"' 2>/dev/null || echo "10%")

# Set consolidation policy based on config
if [ "$KARPENTER_CONSOLIDATION_ENABLED" = "true" ]; then
    KARPENTER_CONSOLIDATION_POLICY="WhenEmptyOrUnderutilized"
else
    KARPENTER_CONSOLIDATION_POLICY="Never"
fi

# Keycloak configuration
KEYCLOAK_ADMIN_USER=$(echo "$CONFIG_VALUES" | jq -r '.keycloak.admin_user // "admin"' 2>/dev/null || echo "admin")
KEYCLOAK_ADMIN_PASSWORD=$(echo "$CONFIG_VALUES" | jq -r '.keycloak.admin_password // "changeme"' 2>/dev/null || echo "changeme")
KEYCLOAK_REPLICAS=$(echo "$CONFIG_VALUES" | jq -r '.keycloak.replicas // "2"' 2>/dev/null || echo "2")
KEYCLOAK_IMAGE_TAG=$(echo "$CONFIG_VALUES" | jq -r '.keycloak.image_tag // "16.1.1"' 2>/dev/null || echo "16.1.1")

# Get OIDC client secrets from config.yaml
ARGOCD_CLIENT_SECRET=$(echo "$CONFIG_VALUES" | jq -r '.secrets.keycloak.argocd_client_secret // "change-argocd-secret"' 2>/dev/null || echo "change-argocd-secret")
BACKSTAGE_CLIENT_SECRET=$(echo "$CONFIG_VALUES" | jq -r '.secrets.keycloak.backstage_client_secret // "change-backstage-secret"' 2>/dev/null || echo "change-backstage-secret")
KEYCLOAK_ARGOCD_CLIENT_SECRET="$ARGOCD_CLIENT_SECRET"

# Backstage configuration
GITHUB_ORG=$(echo "$CONFIG_VALUES" | jq -r '.github_org // "your-org"' 2>/dev/null || echo "your-org")
INFRASTRUCTURE_REPO=$(echo "$CONFIG_VALUES" | jq -r '.infrastructure_repo // "infrastructure"' 2>/dev/null || echo "infrastructure")
POSTGRES_HOST=$(echo "$CONFIG_VALUES" | jq -r '.secrets.backstage.postgres_host // "backstage-postgresql"' 2>/dev/null || echo "backstage-postgresql")
POSTGRES_PORT=$(echo "$CONFIG_VALUES" | jq -r '.secrets.backstage.postgres_port // "5432"' 2>/dev/null || echo "5432")
POSTGRES_USER=$(echo "$CONFIG_VALUES" | jq -r '.secrets.backstage.postgres_user // "backstage"' 2>/dev/null || echo "backstage")
TERRAFORM_BACKEND_BUCKET=$(echo "$CONFIG_VALUES" | jq -r '.terraform_backend.bucket // "tfstate-bucket"' 2>/dev/null || echo "tfstate-bucket")
TERRAFORM_VERSION=$(echo "$CONFIG_VALUES" | jq -r '.secrets.backstage.terraform_version // "1.7.5"' 2>/dev/null || echo "1.7.5")

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

# Create sed script file for faster processing (single pass)
SED_SCRIPT=$(mktemp)
cat > "$SED_SCRIPT" <<EOF
s|{{ cluster_name }}|$CLUSTER_NAME|g
s|{{ region }}|$REGION|g
s|{{ domain }}|$DOMAIN|g
s|{{ git_repo_url }}|$GIT_REPO|g
s|{{ git_branch }}|$GIT_BRANCH|g
s|{{ gitops_repo_url }}|$GITOPS_REPO_URL|g
s|{{ gitops_branch }}|$GITOPS_BRANCH|g
s|{{ argocd_subdomain }}|$ARGOCD_SUBDOMAIN|g
s|{{ keycloak_subdomain }}|$KEYCLOAK_SUBDOMAIN|g
s|{{ backstage_subdomain }}|$BACKSTAGE_SUBDOMAIN|g
s|{{ argocd_hostname }}|$ARGOCD_HOSTNAME|g
s|{{ keycloak_hostname }}|$KEYCLOAK_HOSTNAME|g
s|{{ backstage_hostname }}|$BACKSTAGE_HOSTNAME|g
s|{{ keycloak_admin_user }}|$KEYCLOAK_ADMIN_USER|g
s|{{ keycloak_admin_password }}|$KEYCLOAK_ADMIN_PASSWORD|g
s|{{ keycloak_replicas }}|$KEYCLOAK_REPLICAS|g
s|{{ keycloak_image_tag }}|$KEYCLOAK_IMAGE_TAG|g
s|{{ keycloak_db_address }}|$KEYCLOAK_DB_ADDRESS|g
s|{{ keycloak_db_name }}|$KEYCLOAK_DB_NAME|g
s|{{ keycloak_db_username }}|$KEYCLOAK_DB_USERNAME|g
s|{{ keycloak_db_password }}|$KEYCLOAK_DB_PASSWORD|g
s|{{ keycloak_db_secret_arn }}|$KEYCLOAK_DB_SECRET_ARN|g
s|{{ external_secrets_role_arn }}|$EXTERNAL_SECRETS_ROLE_ARN|g
s|{{ external_dns_role_arn }}|$EXTERNAL_DNS_ROLE_ARN|g
s|{{ crossplane_role_arn }}|$CROSSPLANE_ROLE_ARN|g
s|{{ acm_certificate_arn }}|$ACM_CERTIFICATE_ARN|g
s|{{ cloud_economics_tag }}|$CLOUD_ECONOMICS_TAG|g
s|{{ cloud_economics_tag_key }}|$CLOUD_ECONOMICS_TAG_KEY|g
s|{{ cloud_economics_tag_value }}|$CLOUD_ECONOMICS_TAG_VALUE|g
s|{{ karpenter_node_role_name }}|$KARPENTER_NODE_ROLE_NAME|g
s|{{ karpenter_instance_profile_name }}|$KARPENTER_INSTANCE_PROFILE_NAME|g
s|{{ env }}|$ENV|g
s|{{ karpenter_limits_cpu }}|$KARPENTER_LIMITS_CPU|g
s|{{ karpenter_limits_memory }}|$KARPENTER_LIMITS_MEMORY|g
s|{{ karpenter_consolidation_policy }}|$KARPENTER_CONSOLIDATION_POLICY|g
s|{{ karpenter_ttl_seconds }}|$KARPENTER_TTL_SECONDS|g
s|{{ karpenter_disruption_budget }}|$KARPENTER_DISRUPTION_BUDGET|g
s|{{ argocd_client_secret }}|$ARGOCD_CLIENT_SECRET|g
s|{{ keycloak_argocd_client_secret }}|$KEYCLOAK_ARGOCD_CLIENT_SECRET|g
s|{{ backstage_client_secret }}|$BACKSTAGE_CLIENT_SECRET|g
s|{{ github_org }}|$GITHUB_ORG|g
s|{{ infrastructure_repo }}|$INFRASTRUCTURE_REPO|g
s|{{ postgres_host }}|$POSTGRES_HOST|g
s|{{ postgres_port }}|$POSTGRES_PORT|g
s|{{ postgres_user }}|$POSTGRES_USER|g
s|{{ terraform_backend_bucket }}|$TERRAFORM_BACKEND_BUCKET|g
s|{{ terraform_version }}|$TERRAFORM_VERSION|g
EOF

# Function to render a template (optimized - single sed pass)
render_template() {
    local template_file=$1
    local output_file="${template_file%.tpl}"
    sed -f "$SED_SCRIPT" "$template_file" > "$output_file"
}

# Cleanup function
cleanup() {
    rm -f "$SED_SCRIPT"
}
trap cleanup EXIT

# Render all .tpl files (single pass, much faster)
info "Rendering templates..."
TEMPLATE_COUNT=0
while read -r template; do
    render_template "$template"
    TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
done < <(find platform apps packages argocd-apps -name "*.tpl" -type f 2>/dev/null)

# Special handling for realm-configmap.yaml - inject realm-config.json content
if [ -f "platform/keycloak/manifests/realm-configmap.yaml" ] && [ -f "platform/keycloak/realm-config.json" ]; then
    info "Injecting realm config into ConfigMap..."
    # Create a temporary file with the ConfigMap header
    grep -B 100 "REALM_CONFIG_PLACEHOLDER" platform/keycloak/manifests/realm-configmap.yaml | grep -v "REALM_CONFIG_PLACEHOLDER" > platform/keycloak/manifests/realm-configmap.yaml.tmp
    # Add the realm.json key with proper YAML literal block syntax
    echo "  realm.json: |" >> platform/keycloak/manifests/realm-configmap.yaml.tmp
    # Indent the JSON content by 4 spaces for YAML
    sed 's/^/    /' platform/keycloak/realm-config.json >> platform/keycloak/manifests/realm-configmap.yaml.tmp
    # Move the temp file to the final location
    mv platform/keycloak/manifests/realm-configmap.yaml.tmp platform/keycloak/manifests/realm-configmap.yaml
fi

info "✓ Rendered templates complete"
