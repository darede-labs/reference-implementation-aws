#!/usr/bin/env bash
# Install Backstage with OIDC integration to Keycloak
# Source: reference-implementation-aws

set -euo pipefail

# Colors for output
info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKSTAGE_DIR="${PROJECT_ROOT}/platform/backstage"
NAMESPACE="backstage"

# Prerequisite validation
info "Validating prerequisites..."
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v helm >/dev/null 2>&1 || error "helm not found"
command -v yq >/dev/null 2>&1 || error "yq not found"
kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to Kubernetes cluster"
info "✓ Prerequisites validated"

# Render templates
info "Rendering Backstage templates..."
bash "${SCRIPT_DIR}/render-templates.sh"
info "✓ Templates rendered"

# Create namespace
info "Creating Backstage namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
info "✓ Namespace ready"

# Create Keycloak client for Backstage
info "Creating Keycloak client for Backstage..."
bash "${SCRIPT_DIR}/configure-keycloak-realm.sh" || warn "Keycloak client creation failed (may already exist)"
info "✓ Keycloak client configured"

# Create backstage-env-vars secret
info "Creating Backstage secrets..."
kubectl create secret generic backstage-env-vars -n "$NAMESPACE" \
  --from-literal=GITHUB_TOKEN="$(yq eval '.github_token' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=GITHUB_ORG="$(yq eval '.github_org' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=INFRA_REPO="$(yq eval '.infrastructure_repo' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=OIDC_CLIENT_SECRET="$(yq eval '.secrets.keycloak.backstage_client_secret' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=POSTGRES_PASSWORD="$(yq eval '.secrets.backstage.postgres_password' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=AUTH_SESSION_SECRET="$(yq eval '.secrets.backstage.auth_session_secret' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=BACKEND_SECRET="$(yq eval '.secrets.backstage.backend_secret' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=ARGOCD_ADMIN_PASSWORD="$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$(yq eval '.terraform_backend.bucket' "${PROJECT_ROOT}/config.yaml")" \
  --from-literal=TERRAFORM_BACKEND_REGION="$(yq eval '.region' "${PROJECT_ROOT}/config.yaml")" \
  --dry-run=client -o yaml | kubectl apply -f -
info "✓ Secrets created"

# Apply Token Secret ONLY (ServiceAccount managed by Helm)
info "Applying ServiceAccount Token Secret..."
kubectl apply -f "${BACKSTAGE_DIR}/sa-token-secret.yaml" || error "Failed to apply ServiceAccount token secret"

# Validate secret was created
info "Validating ServiceAccount token secret..."
kubectl wait --for=jsonpath='{.type}'=kubernetes.io/service-account-token \
    secret/backstage-sa-token -n "$NAMESPACE" --timeout=30s \
    || error "ServiceAccount token secret not found after 30s"
info "✓ Token Secret applied and validated"

# Create users ConfigMap
info "Creating users catalog ConfigMap..."
kubectl create configmap backstage-users -n "$NAMESPACE" \
  --from-file=users-catalog.yaml="${PROJECT_ROOT}/catalog/users.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -
info "✓ Users catalog ConfigMap created"

# Create Terraform installer ConfigMap
info "Creating Terraform installer ConfigMap..."
kubectl create configmap terraform-installer -n "$NAMESPACE" \
  --from-file=install.sh="${PROJECT_ROOT}/packages/backstage/fix-terraform.sh" \
  --dry-run=client -o yaml | kubectl apply -f -
info "✓ Terraform installer ConfigMap created"

# Add Backstage Helm repository
info "Adding Backstage Helm repository..."
helm repo add backstage https://backstage.github.io/charts 2>/dev/null || true
helm repo update
info "✓ Helm repository updated"

# Install/Upgrade Backstage
if helm list -n "$NAMESPACE" | grep -q "^backstage"; then
    info "Backstage already installed. Upgrading..."
    HELM_ACTION="upgrade"
else
    info "Installing Backstage (first time)..."
    HELM_ACTION="install"
fi

info "Running: helm $HELM_ACTION backstage..."
helm "$HELM_ACTION" backstage backstage/backstage \
    --namespace "$NAMESPACE" \
    --values "${BACKSTAGE_DIR}/helm-values.yaml" \
    --wait \
    --timeout 180s \
    || error "Helm install/upgrade failed (check logs above)"
info "✓ Backstage installed"

info "Waiting for Backstage deployment to be ready..."
kubectl wait --for=condition=available --timeout=180s \
    deployment/backstage \
    -n "$NAMESPACE" \
    || warn "Backstage deployment not ready within 180s (check pods)"

# Apply RBAC for Backstage (declarative)
info "Applying Backstage RBAC..."
kubectl apply -f "${BACKSTAGE_DIR}/rbac.yaml"
info "✓ RBAC applied"

info "✅ Backstage is ready!"

# Get Backstage URL
BACKSTAGE_URL=$(kubectl get ingress -n "$NAMESPACE" backstage -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "backstage.timedevops.click")

cat << EOF

═══════════════════════════════════════════════════════════════════════════
                    ✅ BACKSTAGE INSTALLATION COMPLETE
═══════════════════════════════════════════════════════════════════════════

📊 Access Backstage:
  URL: https://$BACKSTAGE_URL

🔐 Authentication:
  Method: Keycloak OIDC
  Realm: platform
  Client: backstage

📚 Next Steps:
  1. Access Backstage URL
  2. Click "Sign In" (will redirect to Keycloak)
  3. Login with Keycloak credentials
  4. Explore Software Catalog
  5. Create components using Templates

═══════════════════════════════════════════════════════════════════════════

EOF
