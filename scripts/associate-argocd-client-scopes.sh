#!/usr/bin/env bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${PROJECT_ROOT}"  # utils.sh expects REPO_ROOT
PHASE=""  # utils.sh expects PHASE

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

info "Associating client scopes with ArgoCD client..."

# Load configuration
if [[ -f "${PROJECT_ROOT}/config.yaml" ]]; then
  BASE_DOMAIN=$(yq eval '.domain' "${PROJECT_ROOT}/config.yaml")
  KEYCLOAK_SUBDOMAIN=$(yq eval '.keycloak_subdomain' "${PROJECT_ROOT}/config.yaml")
else
  BASE_DOMAIN="${BASE_DOMAIN:-timedevops.click}"
  KEYCLOAK_SUBDOMAIN="${KEYCLOAK_SUBDOMAIN:-keycloak}"
fi

# Get Keycloak admin password
KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak-admin-password -n keycloak -o jsonpath='{.data.password}' | base64 --decode)
KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${BASE_DOMAIN}"

info "Keycloak URL: ${KEYCLOAK_URL}"

# Get admin token
info "Obtaining admin token..."
TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  error "Failed to obtain admin token"
fi

success "Admin token obtained"

# Get ArgoCD client ID
info "Finding ArgoCD client..."
ARGOCD_CLIENT_UUID=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/clients" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.clientId=="argocd") | .id')

if [[ -z "$ARGOCD_CLIENT_UUID" ]]; then
  error "ArgoCD client not found in Keycloak realm 'platform'"
fi

success "ArgoCD client UUID: ${ARGOCD_CLIENT_UUID}"

# Get client scope IDs
info "Retrieving client scope IDs..."
OPENID_SCOPE=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="openid") | .id')
PROFILE_SCOPE=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="profile") | .id')
EMAIL_SCOPE=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="email") | .id')
GROUPS_SCOPE=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[] | select(.name=="groups") | .id')

# Function to add default client scope
add_default_scope() {
  local SCOPE_ID=$1
  local SCOPE_NAME=$2

  if [[ -z "$SCOPE_ID" ]]; then
    warn "Scope '${SCOPE_NAME}' not found, skipping"
    return 0
  fi

  info "Adding default scope: ${SCOPE_NAME}"

  HTTP_CODE=$(curl -sk -X PUT \
    "${KEYCLOAK_URL}/admin/realms/platform/clients/${ARGOCD_CLIENT_UUID}/default-client-scopes/${SCOPE_ID}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -w "%{http_code}" -o /dev/null)

  if [[ "$HTTP_CODE" == "204" ]]; then
    success "Scope '${SCOPE_NAME}' added to ArgoCD client"
  else
    warn "Failed to add scope '${SCOPE_NAME}' (HTTP ${HTTP_CODE}) - may already exist"
  fi
}

# Add all scopes
add_default_scope "$OPENID_SCOPE" "openid"
add_default_scope "$PROFILE_SCOPE" "profile"
add_default_scope "$EMAIL_SCOPE" "email"
add_default_scope "$GROUPS_SCOPE" "groups"

echo ""
success "All scopes associated with ArgoCD client successfully!"
echo ""
info "Next step: Restart ArgoCD server"
info "  kubectl rollout restart deployment argocd-server -n argocd"
