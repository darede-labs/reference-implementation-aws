#!/bin/bash
# OIDC and Endpoint Validation Test Script
# Usage: ./scripts/test-oidc.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_ROOT}/config.yaml"

# Load config
DOMAIN=$(yq eval '.domain' "$CONFIG_FILE")
KEYCLOAK_HOST="keycloak.${DOMAIN}"
BACKSTAGE_HOST="backstage.${DOMAIN}"
ARGOCD_HOST="argocd.${DOMAIN}"
REALM=$(yq eval '.keycloak.realm // "cnoe"' "$CONFIG_FILE")

echo -e "${CYAN}=========================================="
echo -e "  OIDC & Endpoint Validation Tests"
echo -e "==========================================${NC}\n"

PASS=0
FAIL=0

test_result() {
  if [ "$1" = "PASS" ]; then
    echo -e "${GREEN}✅ PASS${NC}: $2"
    ((PASS++))
  else
    echo -e "${RED}❌ FAIL${NC}: $2"
    ((FAIL++))
  fi
}

echo -e "${YELLOW}### 1. App Reachability ###${NC}"

# Test Keycloak
KC_STATUS=$(curl -skI --connect-timeout 10 "https://${KEYCLOAK_HOST}/" 2>/dev/null | head -1 | grep -oE "[0-9]{3}" | head -1)
if [[ "$KC_STATUS" =~ ^(200|302|301)$ ]]; then
  test_result "PASS" "Keycloak reachable (HTTP $KC_STATUS)"
else
  test_result "FAIL" "Keycloak not reachable (HTTP ${KC_STATUS:-timeout})"
fi

# Test Backstage
BS_STATUS=$(curl -skI --connect-timeout 10 "https://${BACKSTAGE_HOST}/" 2>/dev/null | head -1 | grep -oE "[0-9]{3}" | head -1)
if [[ "$BS_STATUS" =~ ^(200|302|301)$ ]]; then
  test_result "PASS" "Backstage reachable (HTTP $BS_STATUS)"
else
  test_result "FAIL" "Backstage not reachable (HTTP ${BS_STATUS:-timeout})"
fi

# Test ArgoCD
ARGO_STATUS=$(curl -skI --connect-timeout 10 "https://${ARGOCD_HOST}/" 2>/dev/null | head -1 | grep -oE "[0-9]{3}" | head -1)
if [[ "$ARGO_STATUS" =~ ^(200|302|301|308)$ ]]; then
  test_result "PASS" "ArgoCD reachable (HTTP $ARGO_STATUS)"
else
  test_result "FAIL" "ArgoCD not reachable (HTTP ${ARGO_STATUS:-timeout})"
fi

echo -e "\n${YELLOW}### 2. Keycloak OIDC Discovery ###${NC}"

DISCOVERY=$(curl -sk --connect-timeout 10 "https://${KEYCLOAK_HOST}/realms/${REALM}/.well-known/openid-configuration" 2>/dev/null)
if echo "$DISCOVERY" | grep -q '"issuer"'; then
  ISSUER=$(echo "$DISCOVERY" | grep -o '"issuer":"[^"]*"' | cut -d'"' -f4)
  test_result "PASS" "OIDC Discovery works (issuer: $ISSUER)"

  # Check groups scope
  if echo "$DISCOVERY" | grep -q '"groups"'; then
    test_result "PASS" "Groups scope available"
  else
    test_result "FAIL" "Groups scope not found"
  fi
else
  test_result "FAIL" "OIDC Discovery failed"
fi

echo -e "\n${YELLOW}### 3. ArgoCD OIDC Redirect ###${NC}"

ARGO_AUTH=$(curl -skI --connect-timeout 10 "https://${ARGOCD_HOST}/auth/login" 2>/dev/null)
ARGO_AUTH_STATUS=$(echo "$ARGO_AUTH" | head -1 | grep -oE "[0-9]{3}" | head -1)
ARGO_LOCATION=$(echo "$ARGO_AUTH" | grep -i "^location:" | head -1)

if [[ "$ARGO_AUTH_STATUS" =~ ^(303|302)$ ]] && echo "$ARGO_LOCATION" | grep -qi "keycloak"; then
  test_result "PASS" "ArgoCD redirects to Keycloak (HTTP $ARGO_AUTH_STATUS)"
else
  test_result "FAIL" "ArgoCD OIDC redirect not working (HTTP ${ARGO_AUTH_STATUS:-none})"
fi

echo -e "\n${YELLOW}### 4. Backstage OIDC Redirect ###${NC}"

BS_AUTH=$(curl -skI --connect-timeout 10 "https://${BACKSTAGE_HOST}/api/auth/keycloak-oidc/start?env=development" 2>/dev/null)
BS_AUTH_STATUS=$(echo "$BS_AUTH" | head -1 | grep -oE "[0-9]{3}" | head -1)

if [[ "$BS_AUTH_STATUS" =~ ^(302|303)$ ]]; then
  test_result "PASS" "Backstage OIDC auth start works (HTTP $BS_AUTH_STATUS)"
else
  test_result "FAIL" "Backstage OIDC auth failed (HTTP ${BS_AUTH_STATUS:-timeout})"
fi

echo -e "\n${YELLOW}### 5. TLS Certificate ###${NC}"

CERT_INFO=$(echo | openssl s_client -servername "$KEYCLOAK_HOST" -connect "$KEYCLOAK_HOST:443" 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null)
if echo "$CERT_INFO" | grep -qi "amazon"; then
  test_result "PASS" "ACM certificate in use"
else
  test_result "FAIL" "ACM certificate not detected"
fi

echo -e "\n${CYAN}=========================================="
echo -e "  RESULTS: ${GREEN}$PASS PASS${NC} / ${RED}$FAIL FAIL${NC}"
echo -e "==========================================${NC}"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
