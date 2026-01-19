#!/usr/bin/env bash
################################################################################
# Install Keycloak
################################################################################
# This script installs Keycloak using Bitnami Legacy Helm chart
# connected to external RDS PostgreSQL database
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../cluster/terraform"
KEYCLOAK_DIR="${SCRIPT_DIR}/../platform/keycloak"
KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-24.0.4}"
KEYCLOAK_NAMESPACE="keycloak"

info "Starting Keycloak installation..."

################################################################################
# Validate Prerequisites
################################################################################

info "Validating prerequisites..."

if ! command -v helm &> /dev/null; then
    error "helm is not installed"
fi

if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed"
fi

if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
fi

info "✓ Prerequisites validated"

################################################################################
# Get Terraform Outputs
################################################################################

info "Fetching Terraform outputs..."

cd "$TERRAFORM_DIR"

KEYCLOAK_ENABLED=$(terraform output -raw keycloak_enabled 2>/dev/null || echo "false")

if [ "$KEYCLOAK_ENABLED" != "true" ]; then
    warn "Keycloak not enabled in config.yaml, skipping installation"
    exit 0
fi

KEYCLOAK_DB_ADDRESS=$(terraform output -raw keycloak_db_address 2>/dev/null || echo "")
KEYCLOAK_DB_NAME=$(terraform output -raw keycloak_db_name 2>/dev/null || echo "")
KEYCLOAK_DB_SECRET_ARN=$(terraform output -raw keycloak_db_secret_arn 2>/dev/null || echo "")
EXTERNAL_SECRETS_ROLE_ARN=$(terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")

if [ -z "$KEYCLOAK_DB_ADDRESS" ]; then
    error "Keycloak database not provisioned. Run terraform apply first."
fi

info "✓ Terraform outputs retrieved"
info "  Database: $KEYCLOAK_DB_ADDRESS"
info "  Secret: $KEYCLOAK_DB_SECRET_ARN"

cd "$SCRIPT_DIR/.."

################################################################################
# Render Templates
################################################################################

info "Rendering Keycloak templates..."

if [ -f "${SCRIPT_DIR}/render-templates.sh" ]; then
    bash "${SCRIPT_DIR}/render-templates.sh"
else
    error "render-templates.sh not found"
fi

if [ ! -f "${KEYCLOAK_DIR}/helm-values.yaml" ]; then
    error "Keycloak helm-values.yaml not found after template rendering"
fi

info "✓ Templates rendered"

################################################################################
# Create Namespace
################################################################################

info "Creating Keycloak namespace..."

kubectl create namespace "$KEYCLOAK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

info "✓ Namespace ready"

################################################################################
# Fetch Database Credentials from Secrets Manager
################################################################################

info "Fetching database credentials from AWS Secrets Manager..."

# Fetch credentials directly using AWS CLI
info "Retrieving secret from AWS Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$KEYCLOAK_DB_SECRET_ARN" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null)

if [ -z "$SECRET_JSON" ]; then
    error "Failed to retrieve database credentials from Secrets Manager"
fi

# Parse JSON and extract values
DB_USERNAME=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r .password)
DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
DB_PORT=$(echo "$SECRET_JSON" | jq -r .port)
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)

if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "null" ]; then
    error "Failed to parse database credentials"
fi

# Create Kubernetes Secret
info "Creating Kubernetes secret for database credentials..."
kubectl create secret generic keycloak-db-credentials \
    --namespace="$KEYCLOAK_NAMESPACE" \
    --from-literal=username="$DB_USERNAME" \
    --from-literal=password="$DB_PASSWORD" \
    --from-literal=host="$DB_HOST" \
    --from-literal=port="$DB_PORT" \
    --from-literal=database="$DB_NAME" \
    --from-literal=jdbc-url="jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME" \
    --dry-run=client -o yaml | kubectl apply -f -

info "✓ Database credentials retrieved and secret created"

################################################################################
# Add Bitnami Helm Repository
################################################################################

info "Adding Bitnami Helm repository..."

# Use bitnami repository (has all versions available)
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

info "✓ Helm repository updated"

################################################################################
# Install/Upgrade Keycloak
################################################################################

if helm list -n "$KEYCLOAK_NAMESPACE" | grep -q "^keycloak"; then
    info "Keycloak already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing Keycloak for the first time..."
    HELM_ACTION="install"
fi

info "Running: helm $HELM_ACTION keycloak..."

helm "$HELM_ACTION" keycloak bitnami/keycloak \
    --namespace "$KEYCLOAK_NAMESPACE" \
    --version "$KEYCLOAK_VERSION" \
    --values "${KEYCLOAK_DIR}/helm-values.yaml" \
    --wait \
    --timeout 10m

info "✓ Keycloak Helm chart installed"

################################################################################
# Wait for Keycloak to be Ready
################################################################################

info "Waiting for Keycloak to be ready..."

kubectl wait --for=condition=available --timeout=600s \
    statefulset/keycloak \
    -n "$KEYCLOAK_NAMESPACE" 2>/dev/null || \
kubectl wait --for=condition=available --timeout=600s \
    deployment/keycloak \
    -n "$KEYCLOAK_NAMESPACE" 2>/dev/null || \
    warn "Timeout waiting for Keycloak (may still be starting)"

info "✓ Keycloak is ready"

################################################################################
# Configure Realm
################################################################################

info "Configuring Keycloak realm..."

if [ -f "${SCRIPT_DIR}/configure-keycloak-realm.sh" ]; then
    bash "${SCRIPT_DIR}/configure-keycloak-realm.sh"
else
    warn "configure-keycloak-realm.sh not found, skipping realm configuration"
fi

################################################################################
# Display Status
################################################################################

info "Keycloak installation summary:"
kubectl get statefulset,pod,svc,ingress -n "$KEYCLOAK_NAMESPACE"

echo ""
info "=========================================="
info "✓ Keycloak installation completed successfully!"
info "=========================================="
echo ""
info "Access Keycloak:"
info "1. URL: https://keycloak.yourdomain.com"
info "2. Admin Console: https://keycloak.yourdomain.com/admin"
info "3. Username: admin"
info "4. Password: (from config.yaml)"
echo ""
info "Database:"
info "- Host: $KEYCLOAK_DB_ADDRESS"
info "- Database: $KEYCLOAK_DB_NAME"
info "- Connection: External RDS PostgreSQL"
echo ""
