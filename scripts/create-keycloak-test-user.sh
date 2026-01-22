#!/usr/bin/env bash
set -euo pipefail

# Create Test User in Keycloak via API
# This script creates a test user for E2E validation of Backstage login

KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.timedevops.click}"
REALM="${KEYCLOAK_REALM:-platform}"
ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-changeme}"

# Test user credentials
TEST_USER_USERNAME="${TEST_USER_USERNAME:-test-user}"
TEST_USER_EMAIL="${TEST_USER_EMAIL:-test-user@timedevops.click}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-Test@123456}"
TEST_USER_FIRSTNAME="${TEST_USER_FIRSTNAME:-Test}"
TEST_USER_LASTNAME="${TEST_USER_LASTNAME:-User}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

info "Creating test user in Keycloak..."
info "Keycloak URL: ${KEYCLOAK_URL}"
info "Realm: ${REALM}"
info "Username: ${TEST_USER_USERNAME}"

# Step 1: Get admin access token
info "Step 1: Getting admin access token..."
TOKEN_RESPONSE=$(curl -k -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

if ! echo "${TOKEN_RESPONSE}" | jq -e '.access_token' > /dev/null 2>&1; then
  error "Failed to get admin token"
  echo "Response: ${TOKEN_RESPONSE}"
  exit 1
fi

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')
success "Admin token obtained"

# Step 2: Check if user already exists
info "Step 2: Checking if user already exists..."
USERS_RESPONSE=$(curl -k -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${TEST_USER_USERNAME}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

USER_COUNT=$(echo "${USERS_RESPONSE}" | jq -r 'length')

if [ "${USER_COUNT}" -gt "0" ]; then
  USER_ID=$(echo "${USERS_RESPONSE}" | jq -r '.[0].id')
  warn "User already exists (ID: ${USER_ID})"

  # Step 3a: Update existing user
  info "Step 3: Updating existing user..."
  UPDATE_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${USER_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${TEST_USER_USERNAME}\",
      \"email\": \"${TEST_USER_EMAIL}\",
      \"firstName\": \"${TEST_USER_FIRSTNAME}\",
      \"lastName\": \"${TEST_USER_LASTNAME}\",
      \"enabled\": true,
      \"emailVerified\": true
    }")

  HTTP_CODE=$(echo "${UPDATE_RESPONSE}" | tail -n1)

  if [ "${HTTP_CODE}" = "204" ]; then
    success "User updated successfully"
  else
    warn "User update returned HTTP ${HTTP_CODE}"
  fi

  # Step 4a: Reset password
  info "Step 4: Resetting user password..."
  PASSWORD_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${USER_ID}/reset-password" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"password\",
      \"value\": \"${TEST_USER_PASSWORD}\",
      \"temporary\": false
    }")

  HTTP_CODE=$(echo "${PASSWORD_RESPONSE}" | tail -n1)

  if [ "${HTTP_CODE}" = "204" ]; then
    success "Password reset successfully"
  else
    warn "Password reset returned HTTP ${HTTP_CODE}"
  fi

else
  # Step 3b: Create new user
  info "Step 3: Creating new user..."
  CREATE_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${TEST_USER_USERNAME}\",
      \"email\": \"${TEST_USER_EMAIL}\",
      \"firstName\": \"${TEST_USER_FIRSTNAME}\",
      \"lastName\": \"${TEST_USER_LASTNAME}\",
      \"enabled\": true,
      \"emailVerified\": true,
      \"credentials\": [{
        \"type\": \"password\",
        \"value\": \"${TEST_USER_PASSWORD}\",
        \"temporary\": false
      }]
    }")

  HTTP_CODE=$(echo "${CREATE_RESPONSE}" | tail -n1)

  if [ "${HTTP_CODE}" = "201" ]; then
    success "User created successfully"

    # Get user ID from location header or query again
    USERS_RESPONSE=$(curl -k -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${TEST_USER_USERNAME}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json")
    USER_ID=$(echo "${USERS_RESPONSE}" | jq -r '.[0].id')
  else
    error "Failed to create user (HTTP ${HTTP_CODE})"
    echo "${CREATE_RESPONSE}" | head -n -1
    exit 1
  fi
fi

success "Test user ready!"
echo ""
echo "📝 Test User Credentials:"
echo "   Username: ${TEST_USER_USERNAME}"
echo "   Email:    ${TEST_USER_EMAIL}"
echo "   Password: ${TEST_USER_PASSWORD}"
echo "   User ID:  ${USER_ID}"
echo ""

# Step 5: Verify login works
info "Step 5: Verifying user can login..."
LOGIN_RESPONSE=$(curl -k -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${TEST_USER_USERNAME}" \
  -d "password=${TEST_USER_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=backstage" \
  -d "client_secret=$(kubectl get secret -n backstage backstage-env-vars -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d)")

if echo "${LOGIN_RESPONSE}" | jq -e '.access_token' > /dev/null 2>&1; then
  success "User login verified!"

  # Decode and show token claims
  ACCESS_TOKEN_USER=$(echo "${LOGIN_RESPONSE}" | jq -r '.access_token')
  CLAIMS=$(echo "${ACCESS_TOKEN_USER}" | awk -F. '{print $2}' | base64 -d 2>/dev/null | jq -r '.')

  echo ""
  echo "🎫 Token Claims:"
  echo "${CLAIMS}" | jq -r '{preferred_username, email, name, groups}'
  echo ""
else
  error "User login failed!"
  echo "Response: ${LOGIN_RESPONSE}"
  exit 1
fi

success "✅ Test user is ready for E2E testing!"
