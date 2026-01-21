#!/usr/bin/env bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${PROJECT_ROOT}"  # utils.sh expects REPO_ROOT
PHASE=""  # utils.sh expects PHASE

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

info "Creating Keycloak client scopes for ArgoCD..."

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
  error "Failed to obtain admin token. Response: ${TOKEN_RESPONSE}"
fi

success "Admin token obtained"

# Function to create client scope
create_client_scope() {
  local SCOPE_NAME=$1
  local SCOPE_PROTOCOL=${2:-openid-connect}

  info "Creating client scope: ${SCOPE_NAME}"

  # Check if scope already exists
  EXISTING_SCOPE=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
    -H "Authorization: Bearer ${TOKEN}" | jq -r ".[] | select(.name==\"${SCOPE_NAME}\") | .id")

  if [[ -n "$EXISTING_SCOPE" ]]; then
    success "Client scope '${SCOPE_NAME}' already exists (ID: ${EXISTING_SCOPE})"
    echo "$EXISTING_SCOPE"
    return 0
  fi

  # Create scope
  SCOPE_PAYLOAD=$(cat <<EOF
{
  "name": "${SCOPE_NAME}",
  "protocol": "${SCOPE_PROTOCOL}",
  "attributes": {
    "include.in.token.scope": "true",
    "display.on.consent.screen": "true"
  }
}
EOF
)

  HTTP_CODE=$(curl -sk -X POST "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${SCOPE_PAYLOAD}" \
    -w "%{http_code}" -o /dev/null)

  if [[ "$HTTP_CODE" == "201" ]]; then
    # Get the created scope ID
    SCOPE_ID=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/client-scopes" \
      -H "Authorization: Bearer ${TOKEN}" | jq -r ".[] | select(.name==\"${SCOPE_NAME}\") | .id")
    success "Client scope '${SCOPE_NAME}' created (ID: ${SCOPE_ID})"
    echo "$SCOPE_ID"
  else
    error "Failed to create client scope '${SCOPE_NAME}' (HTTP ${HTTP_CODE})"
  fi
}

# Create required scopes
OPENID_SCOPE=$(create_client_scope "openid")
PROFILE_SCOPE=$(create_client_scope "profile")
EMAIL_SCOPE=$(create_client_scope "email")
GROUPS_SCOPE=$(create_client_scope "groups")

echo ""
success "All client scopes created successfully!"
echo ""
info "Next step: Run scripts/associate-argocd-client-scopes.sh"
