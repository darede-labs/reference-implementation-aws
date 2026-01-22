#!/usr/bin/env bash
################################################################################
# Setup Environment Variables for Installation
# Helper script to set required environment variables
################################################################################

set -euo pipefail

echo "=========================================="
echo "Setting up environment variables..."
echo "=========================================="
echo ""

# Check if GITHUB_TOKEN is already set
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "⚠️  GITHUB_TOKEN not set"
    echo "   Please set it with: export GITHUB_TOKEN=<your-token>"
    echo ""
    read -p "Do you want to set GITHUB_TOKEN now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -sp "Enter GITHUB_TOKEN: " GITHUB_TOKEN
        echo
        export GITHUB_TOKEN
    else
        echo "Skipping GITHUB_TOKEN - installation may fail"
    fi
else
    echo "✓ GITHUB_TOKEN already set"
fi

# Set KEYCLOAK_ADMIN_PASSWORD if not set
if [ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]; then
    echo ""
    read -sp "Enter KEYCLOAK_ADMIN_PASSWORD (or press Enter for random): " KEYCLOAK_ADMIN_PASSWORD
    echo
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)"
        echo "Generated random password: ${KEYCLOAK_ADMIN_PASSWORD:0:10}..."
    fi
    export KEYCLOAK_ADMIN_PASSWORD
else
    echo "✓ KEYCLOAK_ADMIN_PASSWORD already set"
fi

# Set ARGOCD_CLIENT_SECRET if not set
if [ -z "${ARGOCD_CLIENT_SECRET:-}" ]; then
    ARGOCD_CLIENT_SECRET="$(openssl rand -hex 32)"
    export ARGOCD_CLIENT_SECRET
    echo "✓ Generated ARGOCD_CLIENT_SECRET"
else
    echo "✓ ARGOCD_CLIENT_SECRET already set"
fi

# Set BACKSTAGE_CLIENT_SECRET if not set
if [ -z "${BACKSTAGE_CLIENT_SECRET:-}" ]; then
    BACKSTAGE_CLIENT_SECRET="$(openssl rand -hex 32)"
    export BACKSTAGE_CLIENT_SECRET
    echo "✓ Generated BACKSTAGE_CLIENT_SECRET"
else
    echo "✓ BACKSTAGE_CLIENT_SECRET already set"
fi

echo ""
echo "=========================================="
echo "✅ Environment variables configured!"
echo "=========================================="
echo ""
echo "To use these variables in your current shell, run:"
echo ""
echo "export GITHUB_TOKEN=\"${GITHUB_TOKEN:-<not-set>}\""
echo "export KEYCLOAK_ADMIN_PASSWORD=\"${KEYCLOAK_ADMIN_PASSWORD}\""
echo "export ARGOCD_CLIENT_SECRET=\"${ARGOCD_CLIENT_SECRET}\""
echo "export BACKSTAGE_CLIENT_SECRET=\"${BACKSTAGE_CLIENT_SECRET}\""
echo ""
echo "Or source this script: source <(./scripts/setup-env.sh)"
echo ""
