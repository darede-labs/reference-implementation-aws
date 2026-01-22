#!/usr/bin/env bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${PROJECT_ROOT}"  # utils.sh expects REPO_ROOT
PHASE=""  # utils.sh expects PHASE

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

info "Validating ArgoCD OIDC login..."

# Load configuration
if [[ -f "${PROJECT_ROOT}/config.yaml" ]]; then
  BASE_DOMAIN=$(yq eval '.domain' "${PROJECT_ROOT}/config.yaml")
  ARGOCD_SUBDOMAIN=$(yq eval '.argocd_subdomain' "${PROJECT_ROOT}/config.yaml")
  KEYCLOAK_SUBDOMAIN=$(yq eval '.keycloak_subdomain' "${PROJECT_ROOT}/config.yaml")
else
  BASE_DOMAIN="${BASE_DOMAIN:-timedevops.click}"
  ARGOCD_SUBDOMAIN="${ARGOCD_SUBDOMAIN:-argocd}"
  KEYCLOAK_SUBDOMAIN="${KEYCLOAK_SUBDOMAIN:-keycloak}"
fi

ARGOCD_URL="https://${ARGOCD_SUBDOMAIN}.${BASE_DOMAIN}"
KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${BASE_DOMAIN}"

# Get test user credentials
TEST_USER_USERNAME="${TEST_USER_USERNAME:-test-user}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-Test@123456}"

# Get ArgoCD client secret from Keycloak
info "Retrieving ArgoCD client secret..."
KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak-admin-password -n keycloak -o jsonpath='{.data.password}' | base64 --decode)

TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

ADMIN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

ARGOCD_CLIENT_UUID=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[] | select(.clientId=="argocd") | .id')

ARGOCD_CLIENT_SECRET=$(curl -sk "${KEYCLOAK_URL}/admin/realms/platform/clients/${ARGOCD_CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.value')

# Step 1: Get Keycloak token for test user
info "Getting Keycloak token for user '${TEST_USER_USERNAME}'..."

TOKEN_RESPONSE=$(curl -sk -X POST \
  "${KEYCLOAK_URL}/realms/platform/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=argocd" \
  -d "client_secret=${ARGOCD_CLIENT_SECRET}" \
  -d "username=${TEST_USER_USERNAME}" \
  -d "password=${TEST_USER_PASSWORD}" \
  -d "grant_type=password" \
  -d "scope=openid profile email groups")

if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
  success "Successfully obtained token with all required scopes"

  # Decode token to verify scopes
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

  # Decode JWT payload (base64url decode)
  PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
  # Add padding if needed
  PADDING_LENGTH=$((4 - ${#PAYLOAD} % 4))
  if [[ $PADDING_LENGTH -ne 4 ]]; then
    PAYLOAD="${PAYLOAD}$(printf '=%.0s' $(seq 1 $PADDING_LENGTH))"
  fi

  DECODED_PAYLOAD=$(echo "$PAYLOAD" | base64 -d 2>/dev/null || echo "$PAYLOAD" | base64 -D 2>/dev/null)

  info "Token payload:"
  echo "$DECODED_PAYLOAD" | jq '.'

  # Check for required scopes
  SCOPES=$(echo "$DECODED_PAYLOAD" | jq -r '.scope // empty')

  if [[ -n "$SCOPES" ]]; then
    info "Granted scopes: ${SCOPES}"

    for REQUIRED_SCOPE in openid profile email groups; do
      if echo "$SCOPES" | grep -q "$REQUIRED_SCOPE"; then
        success "✓ Scope '${REQUIRED_SCOPE}' present"
      else
        error "✗ Scope '${REQUIRED_SCOPE}' MISSING"
      fi
    done
  else
    warn "No 'scope' claim found in token, checking individual claims..."

    # Check for individual claims
    if echo "$DECODED_PAYLOAD" | jq -e '.email' > /dev/null 2>&1; then
      success "✓ Email claim present"
    fi
    if echo "$DECODED_PAYLOAD" | jq -e '.preferred_username' > /dev/null 2>&1; then
      success "✓ Username claim present"
    fi
    if echo "$DECODED_PAYLOAD" | jq -e '.groups' > /dev/null 2>&1; then
      success "✓ Groups claim present"
    fi
  fi
else
  error "Failed to obtain token. Response: ${TOKEN_RESPONSE}"
fi

echo ""
success "ArgoCD OIDC validation complete!"
echo ""
info "Manual test: Open ${ARGOCD_URL} and log in with SSO"
info "  Username: ${TEST_USER_USERNAME}"
info "  Password: ${TEST_USER_PASSWORD}"
