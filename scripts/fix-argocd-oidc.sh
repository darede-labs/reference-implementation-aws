#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Fix ArgoCD OIDC - Standalone Script
# =============================================================================
# This script fixes the ArgoCD OIDC "invalid_scope" error by creating and
# associating the missing client scopes in Keycloak.
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*"
  exit 1
}

success() {
  echo -e "${BLUE}[SUCCESS]${NC} $*"
}

# Get configuration
KEYCLOAK_URL="https://keycloak.timedevops.click"

info "=========================================="
info "Fixing ArgoCD OIDC Configuration"
info "=========================================="
info "Keycloak URL: ${KEYCLOAK_URL}"

# Get Keycloak admin password
info "Getting Keycloak admin password..."
KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode) || error "Failed to get Keycloak admin password"

# Get admin token
info "Obtaining admin token..."
TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" 2>/dev/null) || error "Failed to obtain admin token"

# Use platform realm for client configuration
REALM="platform"

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')
if [[ -z "${ACCESS_TOKEN}" || "${ACCESS_TOKEN}" == "null" ]]; then
  error "Failed to extract access token"
fi

success "Admin token obtained"

# =============================================================================
# Step 1: Create client scopes
# =============================================================================
info "Creating client scopes..."

for SCOPE_NAME in "profile" "email" "groups"; do
  info "  Checking if scope '${SCOPE_NAME}' exists..."
  
  EXISTING_SCOPE=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null | jq -r ".[] | select(.name == \"${SCOPE_NAME}\") | .id")
  
  if [[ -n "${EXISTING_SCOPE}" && "${EXISTING_SCOPE}" != "null" ]]; then
    success "  Scope '${SCOPE_NAME}' already exists (ID: ${EXISTING_SCOPE})"
  else
    info "  Creating scope '${SCOPE_NAME}'..."
    
    SCOPE_CONFIG=""
    case "${SCOPE_NAME}" in
      "profile")
        SCOPE_CONFIG='{
          "name": "profile",
          "description": "OpenID Connect built-in scope: profile",
          "protocol": "openid-connect",
          "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "true"
          }
        }'
        ;;
      "email")
        SCOPE_CONFIG='{
          "name": "email",
          "description": "OpenID Connect built-in scope: email",
          "protocol": "openid-connect",
          "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "true"
          }
        }'
        ;;
      "groups")
        SCOPE_CONFIG='{
          "name": "groups",
          "description": "Group membership scope",
          "protocol": "openid-connect",
          "attributes": {
            "include.in.token.scope": "true",
            "display.on.consent.screen": "true"
          }
        }'
        ;;
    esac
    
    curl -sk -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${SCOPE_CONFIG}" || error "Failed to create scope '${SCOPE_NAME}'"
    
    success "  Scope '${SCOPE_NAME}' created"
  fi
done

# =============================================================================
# Step 2: Get ArgoCD client ID
# =============================================================================
info "Getting ArgoCD client..."
ARGOCD_CLIENT_ID=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" 2>/dev/null | jq -r '.[] | select(.clientId == "argocd") | .id')

if [[ -z "${ARGOCD_CLIENT_ID}" || "${ARGOCD_CLIENT_ID}" == "null" ]]; then
  error "ArgoCD client not found in Keycloak"
fi

success "ArgoCD client found (ID: ${ARGOCD_CLIENT_ID})"

# =============================================================================
# Step 3: Associate scopes with ArgoCD client
# =============================================================================
info "Associating scopes with ArgoCD client..."

for SCOPE_NAME in "profile" "email" "groups"; do
  info "  Associating scope '${SCOPE_NAME}'..."
  
  # Get scope ID
  SCOPE_ID=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null | jq -r ".[] | select(.name == \"${SCOPE_NAME}\") | .id")
  
  if [[ -z "${SCOPE_ID}" || "${SCOPE_ID}" == "null" ]]; then
    error "Failed to get ID for scope '${SCOPE_NAME}'"
  fi
  
  # Check if already associated
  EXISTING_ASSOC=$(curl -sk -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${ARGOCD_CLIENT_ID}/default-client-scopes" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null | jq -r ".[] | select(.id == \"${SCOPE_ID}\") | .id")
  
  if [[ -n "${EXISTING_ASSOC}" && "${EXISTING_ASSOC}" != "null" ]]; then
    success "  Scope '${SCOPE_NAME}' already associated"
  else
    curl -sk -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${ARGOCD_CLIENT_ID}/default-client-scopes/${SCOPE_ID}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" || error "Failed to associate scope '${SCOPE_NAME}'"
    
    success "  Scope '${SCOPE_NAME}' associated"
  fi
done

# =============================================================================
# Step 4: Restart ArgoCD server
# =============================================================================
info "Restarting ArgoCD server to apply changes..."
kubectl rollout restart deployment argocd-server -n argocd || error "Failed to restart ArgoCD server"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || error "ArgoCD server did not become available"
success "ArgoCD server restarted"

success "=========================================="
success "✓ ArgoCD OIDC configuration fixed!"
success "=========================================="
info "You can now log in to ArgoCD using Keycloak"
