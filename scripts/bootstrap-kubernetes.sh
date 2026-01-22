#!/usr/bin/env bash
################################################################################
# Bootstrap Kubernetes Cluster - Minimal (ArgoCD Only)
# This script installs ONLY ArgoCD via Helm and applies the root App-of-Apps
# Everything else is managed via GitOps
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.yaml"

# Load utility functions
source "${SCRIPT_DIR}/utils.sh"

# Load configuration and secrets (auto-generates if needed)
load_config_and_secrets

# Validate required environment variables (should be set by load_config_and_secrets)
info "Validating required environment variables..."
if [[ -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
    error "KEYCLOAK_ADMIN_PASSWORD not set (should be auto-generated)"
fi

if [[ -z "${ARGOCD_CLIENT_SECRET:-}" ]]; then
    error "ARGOCD_CLIENT_SECRET not set (should be auto-generated)"
fi

if [[ -z "${BACKSTAGE_CLIENT_SECRET:-}" ]]; then
    error "BACKSTAGE_CLIENT_SECRET not set (should be auto-generated)"
fi

# GITHUB_TOKEN is required for private repos
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    warn "GITHUB_TOKEN not set - assuming public GitOps repository"
    warn "  Set in config.yaml under secrets.github_token or export GITHUB_TOKEN"
else
    info "✓ GITHUB_TOKEN configured"
fi

info "✓ Environment variables validated"

# Read config values
DOMAIN=$(yq eval '.domain' "$CONFIG_FILE")
CLUSTER_NAME=$(yq eval '.cluster_name' "$CONFIG_FILE")
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' "$CONFIG_FILE")
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' "$CONFIG_FILE")
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$CONFIG_FILE")
GITOPS_REPO_URL=$(yq eval '.gitops.repo_url' "$CONFIG_FILE")
GITOPS_REVISION=$(yq eval '.gitops.revision' "$CONFIG_FILE")
KEYCLOAK_IMAGE_TAG=$(yq eval '.keycloak.image_tag' "$CONFIG_FILE" 2>/dev/null || echo "24.0.5")

info "=========================================="
info "Bootstrapping Kubernetes Cluster"
info "=========================================="
info "Cluster: ${CLUSTER_NAME}"
info "Domain: ${DOMAIN}"
info "GitOps Repo: ${GITOPS_REPO_URL}@${GITOPS_REVISION}"
echo ""

# 1. Render templates (uses Terraform outputs)
info "Rendering templates from config.yaml and Terraform outputs..."
"${SCRIPT_DIR}/render-templates.sh"
info "✓ Templates rendered"

# 2. Commit rendered manifests to Git (ArgoCD needs them)
info "Committing rendered manifests to Git..."
if "${SCRIPT_DIR}/commit-manifests.sh" 2>&1; then
    info "✓ Manifests committed to Git"

    # Wait for Git to propagate
    info "Waiting for Git to propagate..."
    sleep 5
else
    warn "Failed to commit manifests to Git - ArgoCD sync may fail"
    warn "You may need to commit manually or set GITHUB_TOKEN"
fi

# 3. Create namespaces
info "Creating namespaces..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
info "✓ Namespace 'argocd' ready"

kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
info "✓ Namespace 'keycloak' ready"

# 4. Create Kubernetes Secrets BEFORE installing ArgoCD
info "Creating Kubernetes Secrets..."

# Secret: keycloak-admin (namespace: keycloak)
kubectl create secret generic keycloak-admin \
    --namespace=keycloak \
    --from-literal=password="${KEYCLOAK_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
info "✓ Secret 'keycloak-admin' created in namespace 'keycloak'"

# Secret: oidc-client-secrets (namespace: argocd)
kubectl create secret generic oidc-client-secrets \
    --namespace=argocd \
    --from-literal=argocd_client_secret="${ARGOCD_CLIENT_SECRET}" \
    --from-literal=backstage_client_secret="${BACKSTAGE_CLIENT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -
info "✓ Secret 'oidc-client-secrets' created in namespace 'argocd'"

# Secret: argocd-repo-creds (namespace: argocd) - for private repos
if [ -n "${GITHUB_TOKEN:-}" ]; then
    info "Creating repo credentials secret for private repository..."
    kubectl create secret generic argocd-repo-creds \
        --namespace=argocd \
        --from-literal=url=https://github.com \
        --from-literal=username=x-access-token \
        --from-literal=password="${GITHUB_TOKEN}" \
        --dry-run=client -o yaml | \
        kubectl label --local -f - argocd.argoproj.io/secret-type=repo-creds --dry-run=client -o yaml | \
        kubectl apply -f -
    info "✓ Secret 'argocd-repo-creds' created with label for ArgoCD"
else
    info "Skipping repo credentials (assuming public repository)"
fi

# 5. Create realm ConfigMap (rendered by render-templates.sh + envsubst)
info "Creating Keycloak realm ConfigMap..."
envsubst < "${REPO_ROOT}/platform/keycloak/bootstrap/realm-configmap.yaml" | kubectl apply -f -
info "✓ ConfigMap 'keycloak-realm-config' created"

# 6. Add Helm repositories
info "Adding Helm repositories..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
info "✓ Helm repositories updated"

# 7. Render ArgoCD values with gomplate (injeta ARGOCD_CLIENT_SECRET)
info "Rendering ArgoCD Helm values..."
TEMP_VALUES=$(mktemp)
gomplate -f "${REPO_ROOT}/platform/argocd/helm-values.yaml.tpl" \
    -c config="${CONFIG_FILE}" \
    -o "${TEMP_VALUES}"
info "✓ ArgoCD values rendered"

# 8. Install/Upgrade ArgoCD via Helm (idempotent)
info "Installing/Upgrading ArgoCD via Helm..."
HELM_LOG=$(mktemp)
if ! helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version 7.7.12 \
    --values "${TEMP_VALUES}" \
    --wait --timeout 5m >"${HELM_LOG}" 2>&1; then
    warn "Helm output:"
    cat "${HELM_LOG}" || true
    warn "Recent ArgoCD events:"
    kubectl -n argocd get events --sort-by=.lastTimestamp | tail -n 20 || true
    rm -f "${TEMP_VALUES}" "${HELM_LOG}"
    error "ArgoCD Helm install/upgrade failed"
fi
rm -f "${TEMP_VALUES}" "${HELM_LOG}"
info "✓ ArgoCD installed/updated"

# 9. Wait for ArgoCD server to be ready
info "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd || warn "ArgoCD server may still be starting"
info "✓ ArgoCD server is ready"

# 10. Apply root App-of-Apps (triggers ArgoCD to sync everything)
info "Applying root App-of-Apps..."
TEMP_ROOT_APP=$(mktemp)
gomplate -f "${REPO_ROOT}/argocd-apps/root-app.yaml.tpl" \
    -c config="${CONFIG_FILE}" \
    -o "${TEMP_ROOT_APP}"

kubectl apply -f "${TEMP_ROOT_APP}"
rm -f "${TEMP_ROOT_APP}"
info "✓ Root App-of-Apps applied"

echo ""
info "=========================================="
info "✅ Bootstrap complete!"
info "=========================================="
info ""
info "ArgoCD and platform applications have been deployed."
info ""
info "Next steps:"
info "  - Applications are now syncing (this may take 5-10 minutes)"
info "  - Run './scripts/wait-for-sync.sh' to monitor progress"
info "  - Run 'make verify' for comprehensive health check"
info ""
info "ArgoCD UI: https://${ARGOCD_SUBDOMAIN}.${DOMAIN}"
info "  Get admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
