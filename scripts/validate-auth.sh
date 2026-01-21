#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

info "=========================================="
info "Validating Authentication Configuration"
info "=========================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config.yaml"

# Load configuration
BASE_DOMAIN=""
KEYCLOAK_SUBDOMAIN=""
ARGOCD_SUBDOMAIN=""
BACKSTAGE_SUBDOMAIN=""

if [[ -f "${CONFIG_FILE}" ]]; then
    info "Loading configuration from ${CONFIG_FILE}..."
    BASE_DOMAIN=$(yq eval '.domain' "${CONFIG_FILE}")
    KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "${CONFIG_FILE}")
    ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "${CONFIG_FILE}")
    BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "${CONFIG_FILE}")
fi

if [[ -z "${BASE_DOMAIN}" ]]; then
    warn "BASE_DOMAIN not found in config.yaml. Using default 'timedevops.click'."
    BASE_DOMAIN="timedevops.click"
fi

if [[ -z "${KEYCLOAK_SUBDOMAIN}" ]]; then
    KEYCLOAK_SUBDOMAIN="keycloak"
fi

if [[ -z "${ARGOCD_SUBDOMAIN}" ]]; then
    ARGOCD_SUBDOMAIN="argocd"
fi

if [[ -z "${BACKSTAGE_SUBDOMAIN}" ]]; then
    BACKSTAGE_SUBDOMAIN="backstage"
fi

KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${BASE_DOMAIN}"
ARGOCD_URL="https://${ARGOCD_SUBDOMAIN}.${BASE_DOMAIN}"
BACKSTAGE_URL="https://${BACKSTAGE_SUBDOMAIN}.${BASE_DOMAIN}"

info "Keycloak URL: ${KEYCLOAK_URL}"
info "ArgoCD URL: ${ARGOCD_URL}"
info "Backstage URL: ${BACKSTAGE_URL}"

# =============================================================================
# 1. Validate Keycloak is accessible
# =============================================================================
info ""
info "1. Validating Keycloak accessibility..."
if curl -sk "${KEYCLOAK_URL}/realms/platform/.well-known/openid-configuration" > /dev/null 2>&1; then
    success "Keycloak is accessible"
else
    error "Keycloak is not accessible"
fi

# =============================================================================
# 2. Get Keycloak admin token
# =============================================================================
info ""
info "2. Getting Keycloak admin token..."
KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 --decode 2>/dev/null)
if [[ -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
    error "Failed to get Keycloak admin password"
fi

TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" 2>/dev/null)

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')

if [[ "${ACCESS_TOKEN}" == "null" || -z "${ACCESS_TOKEN}" ]]; then
    error "Failed to obtain admin token"
fi
success "Admin token obtained"

# =============================================================================
# 3. List users in Keycloak
# =============================================================================
info ""
info "3. Listing users in Keycloak platform realm..."
USERS=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/platform/users" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null)

echo "${USERS}" | jq -r '.[] | "  - \(.username) (\(.email))"'
success "Found $(echo "${USERS}" | jq '. | length') users"

# =============================================================================
# 4. Validate ArgoCD client configuration
# =============================================================================
info ""
info "4. Validating ArgoCD client configuration..."
ARGOCD_CLIENT=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/platform/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null | jq -r '.[] | select(.clientId == "argocd")')

if [[ -z "${ARGOCD_CLIENT}" ]]; then
    error "ArgoCD client not found in Keycloak"
fi

ARGOCD_CLIENT_ID=$(echo "${ARGOCD_CLIENT}" | jq -r '.id')
success "ArgoCD client found (ID: ${ARGOCD_CLIENT_ID})"

# Check client scopes
info "  Checking ArgoCD client scopes..."
CLIENT_SCOPES=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/platform/clients/${ARGOCD_CLIENT_ID}/default-client-scopes" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null)

REQUIRED_SCOPES=("profile" "email" "groups")
for SCOPE_NAME in "${REQUIRED_SCOPES[@]}"; do
    if echo "${CLIENT_SCOPES}" | jq -e ".[] | select(.name == \"${SCOPE_NAME}\")" > /dev/null 2>&1; then
        success "  ✓ Scope '${SCOPE_NAME}' is associated"
    else
        error "  ✗ Scope '${SCOPE_NAME}' is NOT associated"
    fi
done

# =============================================================================
# 5. Validate Backstage client configuration
# =============================================================================
info ""
info "5. Validating Backstage client configuration..."
BACKSTAGE_CLIENT=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/platform/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null | jq -r '.[] | select(.clientId == "backstage")')

if [[ -z "${BACKSTAGE_CLIENT}" ]]; then
    error "Backstage client not found in Keycloak"
fi

BACKSTAGE_CLIENT_ID=$(echo "${BACKSTAGE_CLIENT}" | jq -r '.id')
success "Backstage client found (ID: ${BACKSTAGE_CLIENT_ID})"

# =============================================================================
# 6. Validate Backstage users catalog
# =============================================================================
info ""
info "6. Validating Backstage users catalog..."
BACKSTAGE_USERS=$(kubectl exec -n backstage deployment/backstage -- cat /catalog/users-catalog.yaml 2>&1)

info "  Users in Backstage catalog:"
echo "${BACKSTAGE_USERS}" | yq eval 'select(.kind == "User") | .spec.profile.email' - | while read -r email; do
    echo "    - ${email}"
done

# =============================================================================
# 7. Validate ArgoCD OIDC configuration
# =============================================================================
info ""
info "7. Validating ArgoCD OIDC configuration..."

# Check ArgoCD OIDC config in argocd-cm
OIDC_CONFIG=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.oidc\.config}' 2>/dev/null)
if [[ -n "${OIDC_CONFIG}" ]]; then
    success "✓ ArgoCD OIDC configuration found"
    info "  OIDC Issuer: $(echo "${OIDC_CONFIG}" | yq eval '.issuer' -)"
else
    warn "ArgoCD OIDC configuration not found in argocd-cm"
fi

# Check if ArgoCD client secret exists
ARGOCD_CLIENT_SECRET=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.oidc\.keycloak\.clientSecret}' | base64 --decode 2>/dev/null)
if [[ -n "${ARGOCD_CLIENT_SECRET}" ]]; then
    success "✓ ArgoCD client secret configured"
else
    warn "ArgoCD client secret not found"
fi

# =============================================================================
# 8. Validate Backstage is accessible
# =============================================================================
info ""
info "8. Validating Backstage accessibility..."
if curl -sk "${BACKSTAGE_URL}/api/catalog/entities" > /dev/null 2>&1; then
    success "Backstage API is accessible"
else
    warn "Backstage API is not accessible (this may be expected if auth is required)"
fi

# =============================================================================
# Summary
# =============================================================================
info ""
success "=========================================="
success "✓ Authentication validation complete!"
success "=========================================="
info ""
info "Next steps:"
info "  1. Test ArgoCD login: ${ARGOCD_URL}"
info "     - Click 'LOG IN VIA KEYCLOAK'"
info "     - Use credentials: test-user / <password from secret>"
info ""
info "  2. Test Backstage login: ${BACKSTAGE_URL}"
info "     - Click 'Sign In'"
info "     - Use credentials: test-user / <password from secret>"
info ""
info "To get test-user password:"
info "  kubectl get secret test-user-password -n keycloak -o jsonpath='{.data.password}' | base64 --decode"
