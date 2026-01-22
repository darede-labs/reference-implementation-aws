#!/usr/bin/env bash
################################################################################
# Verify Installation
# Validates platform installation health without using argocd CLI
# Uses kubectl to read Application resources directly
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

ERRORS=0

# Read config using yq (NOT source config.yaml - YAML is not shell)
DOMAIN=$(yq eval '.domain' "$CONFIG_FILE")
CLUSTER_NAME=$(yq eval '.cluster_name' "$CONFIG_FILE")
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "$CONFIG_FILE")
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "$CONFIG_FILE")
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$CONFIG_FILE")
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"

info "=========================================="
info "Verifying Platform Installation"
info "=========================================="
echo ""

# 1. Check ArgoCD Applications using kubectl (preferred over argocd CLI)
info "1. Checking ArgoCD application health..."

APPS=("root-app" "ingress-nginx" "external-dns" "keycloak" "backstage" "kube-prometheus-stack" "loki")

for app in "${APPS[@]}"; do
    # Use kubectl to read Application resource
    APP_STATUS=$(kubectl -n argocd get applications.argoproj.io "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
    SYNC_STATUS=$(kubectl -n argocd get applications.argoproj.io "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")

    if [[ "$APP_STATUS" == "Healthy" && "$SYNC_STATUS" == "Synced" ]]; then
        success "  $app: Healthy & Synced"
    elif [[ "$APP_STATUS" == "NOT_FOUND" ]]; then
        warn "  $app: Not found (may still be syncing)"
    else
        error "  $app: $APP_STATUS / $SYNC_STATUS"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# 2. Check critical pods
info "2. Checking critical pods..."
check_pod_ready() {
    local namespace=$1
    local label=$2
    local name=$3

    READY=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [[ "$READY" == "True" ]]; then
        success "  $name"
    else
        error "  $name (not ready)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_pod_ready "argocd" "app.kubernetes.io/name=argocd-server" "ArgoCD Server"
check_pod_ready "keycloak" "app.kubernetes.io/name=keycloak" "Keycloak"
check_pod_ready "backstage" "app.kubernetes.io/name=backstage" "Backstage" || warn "  Backstage may not be deployed yet"
echo ""

# 3. Check ingresses and endpoints
info "3. Checking ingress endpoints..."
check_endpoint() {
    local url=$1
    local name=$2

    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302|401|403)$ ]]; then
        success "  $name: $url (HTTP $HTTP_CODE)"
    else
        error "  $name: $url (HTTP $HTTP_CODE - not accessible)"
        ERRORS=$((ERRORS + 1))
    fi
}

if kubectl get ingress -n argocd argocd-server >/dev/null 2>&1; then
    success "  ArgoCD ingress present"
else
    error "  ArgoCD ingress missing"
    ERRORS=$((ERRORS + 1))
fi

check_endpoint "https://${ARGOCD_SUBDOMAIN}.${DOMAIN}" "ArgoCD UI"
check_endpoint "https://${KEYCLOAK_SUBDOMAIN}.${DOMAIN}" "Keycloak UI"
check_endpoint "https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN}" "Backstage UI" || warn "  Backstage may not be deployed yet"
echo ""

# 3.1 Backstage catalog sanity check
info "3.1 Checking Backstage catalog entities..."
if kubectl -n backstage get configmap backstage-users >/dev/null 2>&1; then
    success "  Backstage users catalog ConfigMap present"
else
    error "  Backstage users catalog ConfigMap missing"
    ERRORS=$((ERRORS + 1))
fi

CATALOG_RESPONSE=$(curl -sk -w "\n%{http_code}" "https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN}/api/catalog/entities?limit=1" 2>/dev/null || echo "[]\n000")
CATALOG_BODY=$(echo "$CATALOG_RESPONSE" | head -n1)
CATALOG_HTTP=$(echo "$CATALOG_RESPONSE" | tail -n1)

if [[ "$CATALOG_HTTP" == "200" ]]; then
    CATALOG_COUNT=$(echo "$CATALOG_BODY" | jq 'length' 2>/dev/null || echo "0")
    if [[ "$CATALOG_COUNT" -ge 1 ]]; then
        success "  Backstage catalog has entities"
    else
        error "  Backstage catalog is empty"
        ERRORS=$((ERRORS + 1))
    fi
elif [[ "$CATALOG_HTTP" == "401" ]]; then
    warn "  Backstage catalog endpoint requires auth (HTTP 401)"
else
    warn "  Backstage catalog endpoint not reachable (HTTP ${CATALOG_HTTP})"
fi
echo ""

# 4. Validate Keycloak realm configuration
info "4. Validating Keycloak realm configuration..."

KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${DOMAIN}"

# Try both issuer formats (new and legacy)
ISSUER_NEW="${KEYCLOAK_URL}/realms/platform"
ISSUER_LEGACY="${KEYCLOAK_URL}/auth/realms/platform"
WORKING_ISSUER=""
KEYCLOAK_BASE_PATH=""

if curl -sf "${ISSUER_NEW}/.well-known/openid-configuration" >/dev/null 2>&1; then
    success "  Keycloak issuer (new format): ${ISSUER_NEW}"
    WORKING_ISSUER="${ISSUER_NEW}"
    KEYCLOAK_BASE_PATH=""
elif curl -sf "${ISSUER_LEGACY}/.well-known/openid-configuration" >/dev/null 2>&1; then
    success "  Keycloak issuer (legacy format): ${ISSUER_LEGACY}"
    WORKING_ISSUER="${ISSUER_LEGACY}"
    KEYCLOAK_BASE_PATH="/auth"
else
    error "  Keycloak issuer not accessible (tried both formats)"
    ERRORS=$((ERRORS + 1))
fi

if [[ -n "$WORKING_ISSUER" ]]; then
    # Get admin token
    if [[ -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
        warn "  KEYCLOAK_ADMIN_PASSWORD not set, skipping realm validation"
    else
        TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}${KEYCLOAK_BASE_PATH}/realms/master/protocol/openid-connect/token" \
          -d "client_id=admin-cli" \
          -d "username=admin" \
          -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
          -d "grant_type=password" 2>/dev/null || echo '{"access_token":null}')

        ADMIN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null || echo "null")

        if [[ "$ADMIN_TOKEN" == "null" || -z "$ADMIN_TOKEN" ]]; then
            error "  Failed to get Keycloak admin token"
            ERRORS=$((ERRORS + 1))
        else
            success "  Keycloak admin authentication successful"

            # Check realm exists
            REALM_EXISTS=$(curl -sk -X GET "${KEYCLOAK_URL}${KEYCLOAK_BASE_PATH}/admin/realms/platform" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}" \
              -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")

            if [[ "$REALM_EXISTS" == "200" ]]; then
                success "  Realm 'platform' exists"
            else
                error "  Realm 'platform' not found (HTTP $REALM_EXISTS)"
                ERRORS=$((ERRORS + 1))
            fi

            # Check ArgoCD client
            ARGOCD_CLIENT=$(curl -sk -X GET "${KEYCLOAK_URL}${KEYCLOAK_BASE_PATH}/admin/realms/platform/clients" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | \
              jq -r '.[] | select(.clientId=="argocd") | .clientId' 2>/dev/null || echo "")

            if [[ "$ARGOCD_CLIENT" == "argocd" ]]; then
                success "  ArgoCD OIDC client configured"
            else
                error "  ArgoCD OIDC client not found"
                ERRORS=$((ERRORS + 1))
            fi

            # Check Backstage client
            BACKSTAGE_CLIENT=$(curl -sk -X GET "${KEYCLOAK_URL}${KEYCLOAK_BASE_PATH}/admin/realms/platform/clients" \
              -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | \
              jq -r '.[] | select(.clientId=="backstage") | .clientId' 2>/dev/null || echo "")

            if [[ "$BACKSTAGE_CLIENT" == "backstage" ]]; then
                success "  Backstage OIDC client configured"
            else
                warn "  Backstage OIDC client not found (may not be deployed yet)"
            fi
        fi
    fi
fi
echo ""

# Summary
echo "=========================================="
if [[ $ERRORS -eq 0 ]]; then
    success "✅ All checks passed!"
    echo ""
    info "Platform URLs:"
    info "  ArgoCD:    https://${ARGOCD_SUBDOMAIN}.${DOMAIN}"
    info "  Keycloak:  https://${KEYCLOAK_SUBDOMAIN}.${DOMAIN}"
    info "  Backstage: https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN}"
    echo ""
    info "Test OIDC login manually:"
    info "  1. Open ArgoCD URL and click 'LOG IN VIA KEYCLOAK'"
    if [[ -n "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
        info "  2. Use credentials: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
    else
        info "  2. Use credentials: admin / (value of KEYCLOAK_ADMIN_PASSWORD env var)"
    fi
    info "  3. Repeat for Backstage"
    exit 0
else
    error "❌ Verification failed with $ERRORS error(s)"
    echo ""
    info "Some components may still be syncing. Wait a few minutes and run 'make verify' again."
    exit 1
fi
