#!/usr/bin/env bash
################################################################################
# Render ArgoCD Application Manifests + Platform Ingresses
################################################################################
# This script renders ArgoCD Application manifests and Kubernetes Ingresses
# with dynamic hostnames from config.yaml
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
CONFIG_FILE="${ROOT_DIR}/config.yaml"
ARGOCD_APPS_DIR="${ROOT_DIR}/argocd-apps/platform"
PLATFORM_DIR="${ROOT_DIR}/platform"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

info "Rendering manifests from config.yaml..."

# Read values from config.yaml
DOMAIN=$(yq eval '.domain' "$CONFIG_FILE" 2>/dev/null || echo "example.com")

info "Using domain: ${DOMAIN}"

# ===== ArgoCD Applications =====
# Render kube-prometheus-stack (Grafana)
if [ -f "${ARGOCD_APPS_DIR}/kube-prometheus-stack.yaml.tpl" ]; then
  info "Rendering kube-prometheus-stack.yaml..."
  sed "s|{{ domain }}|${DOMAIN}|g" \
    "${ARGOCD_APPS_DIR}/kube-prometheus-stack.yaml.tpl" \
    > "${ARGOCD_APPS_DIR}/kube-prometheus-stack.yaml"
  info "✅ Rendered ${ARGOCD_APPS_DIR}/kube-prometheus-stack.yaml"
fi

# ===== Platform Ingresses =====
# ArgoCD
if [ -f "${PLATFORM_DIR}/argocd/ingress.yaml.tpl" ]; then
  info "Rendering argocd/ingress.yaml..."
  sed "s|{{ domain }}|${DOMAIN}|g" \
    "${PLATFORM_DIR}/argocd/ingress.yaml.tpl" \
    > "${PLATFORM_DIR}/argocd/ingress.yaml"
  info "✅ Rendered ${PLATFORM_DIR}/argocd/ingress.yaml"
fi

# Backstage (standalone Ingress - not via Helm)
# Note: This requires render-templates.sh to provide {{ backstage_hostname }}
# For now we'll use a simpler version with just domain
if [ -f "${PLATFORM_DIR}/backstage/ingress.yaml.tpl" ]; then
  info "Rendering backstage/ingress.yaml..."
  BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$CONFIG_FILE" 2>/dev/null || echo "backstage")
  BACKSTAGE_HOSTNAME="${BACKSTAGE_SUBDOMAIN}.${DOMAIN}"
  sed "s|{{ backstage_hostname }}|${BACKSTAGE_HOSTNAME}|g" \
    "${PLATFORM_DIR}/backstage/ingress.yaml.tpl" \
    > "${PLATFORM_DIR}/backstage/ingress.yaml"
  info "✅ Rendered ${PLATFORM_DIR}/backstage/ingress.yaml"
fi

# Keycloak (standalone Ingress - not via Helm)
if [ -f "${PLATFORM_DIR}/keycloak/ingress.yaml.tpl" ]; then
  info "Rendering keycloak/ingress.yaml..."
  KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "$CONFIG_FILE" 2>/dev/null || echo "keycloak")
  sed -e "s|{{ keycloak_subdomain }}|${KEYCLOAK_SUBDOMAIN}|g" \
      -e "s|{{ domain }}|${DOMAIN}|g" \
    "${PLATFORM_DIR}/keycloak/ingress.yaml.tpl" \
    > "${PLATFORM_DIR}/keycloak/ingress.yaml"
  info "✅ Rendered ${PLATFORM_DIR}/keycloak/ingress.yaml"
fi

info "✅ All manifests rendered successfully!"
