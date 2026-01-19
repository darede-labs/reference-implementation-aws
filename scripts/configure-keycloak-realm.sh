#!/usr/bin/env bash
################################################################################
# Configure Keycloak Realm
################################################################################
# This script configures the initial Keycloak realm and OIDC clients
# using Keycloak Admin CLI
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYCLOAK_DIR="${SCRIPT_DIR}/../platform/keycloak"
KEYCLOAK_NAMESPACE="keycloak"

info "Configuring Keycloak realm..."

################################################################################
# Wait for Keycloak to be Ready
################################################################################

info "Waiting for Keycloak pod to be ready..."

POD_NAME=$(kubectl get pod -n "$KEYCLOAK_NAMESPACE" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    error "Keycloak pod not found"
fi

kubectl wait --for=condition=ready --timeout=300s \
    pod/"$POD_NAME" \
    -n "$KEYCLOAK_NAMESPACE"

info "✓ Keycloak pod ready: $POD_NAME"

################################################################################
# Get Admin Credentials
################################################################################

info "Retrieving admin credentials..."

ADMIN_USER=$(yq eval '.keycloak.admin_user' "${SCRIPT_DIR}/../config.yaml" 2>/dev/null || echo "admin")
ADMIN_PASSWORD=$(yq eval '.keycloak.admin_password' "${SCRIPT_DIR}/../config.yaml" 2>/dev/null || echo "")

if [ -z "$ADMIN_PASSWORD" ]; then
    error "Admin password not found in config.yaml"
fi

info "✓ Admin credentials retrieved"

################################################################################
# Import Realm Configuration
################################################################################

if [ ! -f "${KEYCLOAK_DIR}/realm-config.json" ]; then
    warn "realm-config.json not found, skipping realm import"
    exit 0
fi

info "Importing platform realm..."

# Copy realm config to pod
kubectl cp "${KEYCLOAK_DIR}/realm-config.json" \
    "$KEYCLOAK_NAMESPACE/$POD_NAME:/tmp/realm-config.json"

# Import realm using Keycloak CLI
kubectl exec -n "$KEYCLOAK_NAMESPACE" "$POD_NAME" -- bash -c "
    /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:8080 \
        --realm master \
        --user '$ADMIN_USER' \
        --password '$ADMIN_PASSWORD'
    
    # Check if realm already exists
    if /opt/bitnami/keycloak/bin/kcadm.sh get realms/platform 2>/dev/null; then
        echo 'Realm platform already exists, updating...'
        /opt/bitnami/keycloak/bin/kcadm.sh update realms/platform -f /tmp/realm-config.json
    else
        echo 'Creating realm platform...'
        /opt/bitnami/keycloak/bin/kcadm.sh create realms -f /tmp/realm-config.json
    fi
"

info "✓ Platform realm configured"

################################################################################
# Import OIDC Clients
################################################################################

info "Configuring OIDC clients..."

# ArgoCD Client
if [ -f "${KEYCLOAK_DIR}/clients/argocd-client.json" ]; then
    info "Importing ArgoCD OIDC client..."
    
    kubectl cp "${KEYCLOAK_DIR}/clients/argocd-client.json" \
        "$KEYCLOAK_NAMESPACE/$POD_NAME:/tmp/argocd-client.json"
    
    kubectl exec -n "$KEYCLOAK_NAMESPACE" "$POD_NAME" -- bash -c "
        /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
            --server http://localhost:8080 \
            --realm master \
            --user '$ADMIN_USER' \
            --password '$ADMIN_PASSWORD'
        
        # Check if client exists
        CLIENT_ID=\$(/opt/bitnami/keycloak/bin/kcadm.sh get clients -r platform --fields id,clientId | grep '\"clientId\" : \"argocd\"' -B 1 | grep '\"id\"' | cut -d '\"' -f 4)
        
        if [ -n \"\$CLIENT_ID\" ]; then
            echo 'ArgoCD client already exists, updating...'
            /opt/bitnami/keycloak/bin/kcadm.sh update clients/\$CLIENT_ID -r platform -f /tmp/argocd-client.json
        else
            echo 'Creating ArgoCD client...'
            /opt/bitnami/keycloak/bin/kcadm.sh create clients -r platform -f /tmp/argocd-client.json
        fi
    "
    
    info "✓ ArgoCD client configured"
fi

# Backstage Client
if [ -f "${KEYCLOAK_DIR}/clients/backstage-client.json" ]; then
    info "Importing Backstage OIDC client..."
    
    kubectl cp "${KEYCLOAK_DIR}/clients/backstage-client.json" \
        "$KEYCLOAK_NAMESPACE/$POD_NAME:/tmp/backstage-client.json"
    
    kubectl exec -n "$KEYCLOAK_NAMESPACE" "$POD_NAME" -- bash -c "
        /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
            --server http://localhost:8080 \
            --realm master \
            --user '$ADMIN_USER' \
            --password '$ADMIN_PASSWORD'
        
        # Check if client exists
        CLIENT_ID=\$(/opt/bitnami/keycloak/bin/kcadm.sh get clients -r platform --fields id,clientId | grep '\"clientId\" : \"backstage\"' -B 1 | grep '\"id\"' | cut -d '\"' -f 4)
        
        if [ -n \"\$CLIENT_ID\" ]; then
            echo 'Backstage client already exists, updating...'
            /opt/bitnami/keycloak/bin/kcadm.sh update clients/\$CLIENT_ID -r platform -f /tmp/backstage-client.json
        else
            echo 'Creating Backstage client...'
            /opt/bitnami/keycloak/bin/kcadm.sh create clients -r platform -f /tmp/backstage-client.json
        fi
    "
    
    info "✓ Backstage client configured"
fi

################################################################################
# Display Configuration Summary
################################################################################

echo ""
info "=========================================="
info "✓ Keycloak realm configuration complete!"
info "=========================================="
echo ""
info "Realm: platform"
info "Users:"
info "  - admin (platform-admin, platform-team)"
echo ""
info "Groups:"
info "  - platform-team (admins)"
info "  - developers (users)"
echo ""
info "OIDC Clients:"
info "  - argocd"
info "  - backstage"
echo ""
info "Access realm:"
info "https://keycloak.yourdomain.com/realms/platform"
echo ""
