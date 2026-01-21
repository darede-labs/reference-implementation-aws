#!/usr/bin/env bash
# Update GitHub Token for Backstage
# Usage: ./update-github-token.sh <your-github-token>

set -euo pipefail

# Colors
info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config.yaml"

# Check arguments
if [ $# -ne 1 ]; then
    error "Usage: $0 <github-token>"
fi

GITHUB_TOKEN="$1"

# Validate token format
if [[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_) ]]; then
    error "Invalid GitHub token format. Should start with 'ghp_' or 'github_pat_'"
fi

info "Testing GitHub token..."
USER_LOGIN=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login' 2>/dev/null)

if [ "$USER_LOGIN" == "null" ] || [ -z "$USER_LOGIN" ]; then
    error "GitHub token is invalid or doesn't have required permissions"
fi

success "Token valid for user: $USER_LOGIN"

# Update config.yaml
info "Updating config.yaml..."
yq eval ".github_token = \"$GITHUB_TOKEN\"" -i "$CONFIG_FILE"
success "config.yaml updated"

# Recreate Kubernetes secret
info "Updating Kubernetes secret..."
kubectl delete secret backstage-env-vars -n backstage 2>/dev/null || true

kubectl create secret generic backstage-env-vars -n backstage \
  --from-literal=GITHUB_TOKEN="$GITHUB_TOKEN" \
  --from-literal=GITHUB_ORG="$(yq eval '.github_org' "$CONFIG_FILE")" \
  --from-literal=INFRA_REPO="$(yq eval '.infrastructure_repo' "$CONFIG_FILE")" \
  --from-literal=OIDC_CLIENT_SECRET="$(yq eval '.secrets.keycloak.backstage_client_secret' "$CONFIG_FILE")" \
  --from-literal=POSTGRES_PASSWORD="$(yq eval '.secrets.backstage.postgres_password' "$CONFIG_FILE")" \
  --from-literal=AUTH_SESSION_SECRET="$(yq eval '.secrets.backstage.auth_session_secret' "$CONFIG_FILE")" \
  --from-literal=BACKEND_SECRET="$(yq eval '.secrets.backstage.backend_secret' "$CONFIG_FILE")" \
  --from-literal=ARGOCD_ADMIN_PASSWORD="$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$(yq eval '.terraform_backend.bucket' "$CONFIG_FILE")" \
  --from-literal=TERRAFORM_BACKEND_REGION="$(yq eval '.region' "$CONFIG_FILE")"

success "Kubernetes secret updated"

# Restart Backstage pods
info "Restarting Backstage pods..."
kubectl rollout restart deployment/backstage -n backstage
kubectl rollout status deployment/backstage -n backstage --timeout=180s

success "✅ GitHub token configured successfully!"
echo ""
echo "Next steps:"
echo "  1. Wait for DNS propagation (~5 min)"
echo "  2. Access: https://backstage.timedevops.click"
echo "  3. Test GitHub integration in Backstage"
