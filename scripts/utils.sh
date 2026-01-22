#!/usr/bin/env bash
################################################################################
# Utility Functions for Installation Scripts
# Common functions for loading config and environment variables
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Load configuration and set environment variables
load_config_and_secrets() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    local CONFIG_FILE="${REPO_ROOT}/config.yaml"

    if [ ! -f "$CONFIG_FILE" ]; then
        error "config.yaml not found at ${CONFIG_FILE}"
    fi

    # Load GITHUB_TOKEN from config.yaml if not in ENV
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        GITHUB_TOKEN=$(yq eval '.secrets.github_token' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -n "$GITHUB_TOKEN" ] && [ "$GITHUB_TOKEN" != "null" ]; then
            export GITHUB_TOKEN
            info "Loaded GITHUB_TOKEN from config.yaml"
        fi
    fi

    # Generate KEYCLOAK_ADMIN_PASSWORD if not set
    if [ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]; then
        KEYCLOAK_ADMIN_PASSWORD=$(yq eval '.secrets.keycloak_admin_password' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ] || [ "$KEYCLOAK_ADMIN_PASSWORD" == "null" ]; then
            KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)"
            info "Generated KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:0:10}..."
        fi
        export KEYCLOAK_ADMIN_PASSWORD
    fi

    # Generate ARGOCD_CLIENT_SECRET if not set
    if [ -z "${ARGOCD_CLIENT_SECRET:-}" ]; then
        ARGOCD_CLIENT_SECRET=$(yq eval '.secrets.argocd_client_secret' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -z "$ARGOCD_CLIENT_SECRET" ] || [ "$ARGOCD_CLIENT_SECRET" == "null" ]; then
            ARGOCD_CLIENT_SECRET="$(openssl rand -hex 32)"
            info "Generated ARGOCD_CLIENT_SECRET"
        fi
        export ARGOCD_CLIENT_SECRET
    fi

    # Generate BACKSTAGE_CLIENT_SECRET if not set
    if [ -z "${BACKSTAGE_CLIENT_SECRET:-}" ]; then
        BACKSTAGE_CLIENT_SECRET=$(yq eval '.secrets.backstage_client_secret' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -z "$BACKSTAGE_CLIENT_SECRET" ] || [ "$BACKSTAGE_CLIENT_SECRET" == "null" ]; then
            BACKSTAGE_CLIENT_SECRET="$(openssl rand -hex 32)"
            info "Generated BACKSTAGE_CLIENT_SECRET"
        fi
        export BACKSTAGE_CLIENT_SECRET
    fi

    # Ensure AWS uses darede profile (SSO)
    if [ -z "${AWS_PROFILE:-}" ]; then
        # Use darede profile if no profile is set
        export AWS_PROFILE="darede"
        info "Using AWS profile: darede"
    fi
}
