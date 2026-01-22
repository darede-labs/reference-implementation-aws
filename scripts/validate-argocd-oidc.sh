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
  ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "${PROJECT_ROOT}/config.yaml")
  KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "${PROJECT_ROOT}/config.yaml")
else
  BASE_DOMAIN="${BASE_DOMAIN:-timedevops.click}"
  ARGOCD_SUBDOMAIN="${ARGOCD_SUBDOMAIN:-argocd}"
  KEYCLOAK_SUBDOMAIN="${KEYCLOAK_SUBDOMAIN:-keycloak}"
fi

ARGOCD_URL="https://${ARGOCD_SUBDOMAIN}.${BASE_DOMAIN}"
KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${BASE_DOMAIN}"

# Check required secret (standardized name)
info "Checking Keycloak admin secret..."
if ! kubectl -n keycloak get secret keycloak-admin >/dev/null 2>&1; then
  error "Secret 'keycloak-admin' not found in namespace 'keycloak'"
fi
success "Secret 'keycloak-admin' found"

# Step 1: Verify Keycloak issuer is reachable (both paths)
info "Checking Keycloak issuer discovery endpoint..."
ISSUER_URL=""
for DISCOVERY_URL in \
  "${KEYCLOAK_URL}/realms/platform/.well-known/openid-configuration" \
  "${KEYCLOAK_URL}/auth/realms/platform/.well-known/openid-configuration"; do
  if curl -skf --connect-timeout 5 --max-time 10 "${DISCOVERY_URL}" >/dev/null 2>&1; then
    ISSUER_URL="${DISCOVERY_URL%/.well-known/openid-configuration}"
    break
  fi
done

if [[ -z "${ISSUER_URL}" ]]; then
  error "Keycloak issuer discovery endpoint is not reachable on expected paths"
fi
success "Issuer reachable: ${ISSUER_URL}"

# Step 2: Verify ArgoCD OIDC config matches issuer
info "Checking ArgoCD OIDC config in argocd-cm..."
OIDC_CONFIG=$(kubectl -n argocd get configmap argocd-cm -o jsonpath='{.data.oidc\.config}' 2>/dev/null || true)

if [[ -z "${OIDC_CONFIG}" ]]; then
  error "argocd-cm missing oidc.config"
fi

if echo "${OIDC_CONFIG}" | grep -q "issuer: ${ISSUER_URL}"; then
  success "ArgoCD OIDC issuer matches Keycloak"
else
  CONFIG_ISSUER=$(echo "${OIDC_CONFIG}" | awk '/issuer:/ {print $2}' | head -n1 || true)
  error "ArgoCD OIDC issuer mismatch (found: ${CONFIG_ISSUER:-unknown}, expected: ${ISSUER_URL})"
fi

echo ""
success "ArgoCD OIDC validation complete!"
echo ""
info "Manual test: Open ${ARGOCD_URL} and log in with SSO"
