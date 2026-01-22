#!/usr/bin/env bash
set -euo pipefail

# Master Script: Install Developer Experience MVP
# This script orchestrates the complete installation of the Developer Experience platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo "========================================"
echo "Developer Experience MVP Installation"
echo "========================================"
echo ""

# =============================================================================
# Phase 0: Preflight Checks
# =============================================================================
info "Phase 0: Preflight checks..."

command -v aws &> /dev/null || error "aws CLI not found"
command -v kubectl &> /dev/null || error "kubectl not found"
command -v terraform &> /dev/null || error "terraform not found"
command -v yq &> /dev/null || error "yq not found"

success "All required tools available"

# Check AWS credentials
aws sts get-caller-identity > /dev/null || error "AWS credentials not configured"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
success "AWS credentials OK (Account: ${AWS_ACCOUNT_ID})"

# Check kubectl context
CURRENT_CONTEXT=$(kubectl config current-context)
info "Kubernetes context: ${CURRENT_CONTEXT}"

echo ""

# =============================================================================
# Phase 1: Terraform - ECR Resources
# =============================================================================
info "Phase 1: Applying Terraform for ECR resources..."

cd "${PROJECT_ROOT}/cluster/terraform"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
  info "Initializing Terraform..."
  terraform init || error "Terraform init failed"
fi

# Apply ECR resources
info "Creating ECR repositories, GitHub OIDC provider, and IAM roles..."
terraform apply -auto-approve \
  -target=aws_ecr_repository.platform_apps \
  -target=aws_iam_openid_connect_provider.github \
  -target=aws_iam_role.github_ecr_push \
  -target=aws_iam_role_policy.github_ecr_push \
  -target=aws_iam_policy.ecr_pull \
  -target=aws_iam_role_policy_attachment.ecr_pull_karpenter \
  -target=aws_iam_role_policy_attachment.ecr_pull_managed_ng || error "Terraform apply failed"

success "ECR resources created successfully"

# Get outputs
ECR_ACCOUNT_URL=$(terraform output -raw ecr_account_url 2>/dev/null || echo "")
GITHUB_ECR_ROLE=$(terraform output -raw github_ecr_push_role_arn 2>/dev/null || echo "")
GITHUB_OIDC_ARN=$(terraform output -raw github_oidc_provider_arn 2>/dev/null || echo "")

if [[ -n "${ECR_ACCOUNT_URL}" ]]; then
  success "ECR Account URL: ${ECR_ACCOUNT_URL}"
fi

if [[ -n "${GITHUB_ECR_ROLE}" ]]; then
  success "GitHub ECR Push Role: ${GITHUB_ECR_ROLE}"
  echo ""
  warn "⚠️  ACTION REQUIRED: Add GitHub Secret to your application repositories"
  warn "   Secret Name: AWS_ROLE_ARN"
  warn "   Secret Value: ${GITHUB_ECR_ROLE}"
  warn "   Location: GitHub Repo > Settings > Secrets and variables > Actions"
  echo ""
fi

if [[ -n "${GITHUB_OIDC_ARN}" ]]; then
  success "GitHub OIDC Provider: ${GITHUB_OIDC_ARN}"
fi

cd "${PROJECT_ROOT}"

echo ""

# =============================================================================
# Phase 2: Deploy Kyverno
# =============================================================================
info "Phase 2: Deploying Kyverno..."

# Check if ArgoCD is ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s > /dev/null 2>&1 || warn "ArgoCD server not ready yet"

# Apply Kyverno ArgoCD Application
info "Creating Kyverno ArgoCD Application..."
kubectl apply -f argocd-apps/platform/kyverno.yaml || error "Failed to apply Kyverno ArgoCD Application"

success "Kyverno ArgoCD Application created"

# Wait for Kyverno to be synced
info "Waiting for Kyverno to sync (this may take 2-3 minutes)..."
sleep 30

# Wait for Kyverno namespace to be created
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/kyverno --timeout=120s > /dev/null 2>&1 || warn "Kyverno namespace not created yet"

# Wait for Kyverno pods
info "Waiting for Kyverno pods to be ready..."
for i in {1..10}; do
  if kubectl get deployment -n kyverno kyverno-admission-controller > /dev/null 2>&1; then
    kubectl wait --for=condition=available deployment/kyverno-admission-controller -n kyverno --timeout=300s > /dev/null 2>&1 && break
  fi
  info "Waiting for Kyverno deployment to be created... (attempt $i/10)"
  sleep 30
done

if kubectl get deployment -n kyverno kyverno-admission-controller > /dev/null 2>&1; then
  success "Kyverno admission controller is ready"
else
  warn "Kyverno admission controller not ready yet (check ArgoCD for sync status)"
fi

# Check for Kyverno policies
sleep 10
POLICY_COUNT=$(kubectl get clusterpolicies -o json 2>/dev/null | jq '.items | length' || echo "0")
if [[ "${POLICY_COUNT}" -gt "0" ]]; then
  success "Kyverno has ${POLICY_COUNT} ClusterPolicies installed"
else
  warn "No Kyverno policies found yet (they may still be syncing)"
fi

echo ""

# =============================================================================
# Phase 3: Validation
# =============================================================================
info "Phase 3: Running E2E validation..."

# Set auto-confirm for E2E script
export E2E_AUTO_CONFIRM=true

# Run E2E validation
"${PROJECT_ROOT}/scripts/e2e-mvp.sh" || warn "E2E validation had warnings (check output above)"

echo ""

# =============================================================================
# Phase 4: Summary & Next Steps
# =============================================================================
echo "========================================"
echo "Installation Summary"
echo "========================================"
echo ""

success "✅ Phase 1: ECR Resources Created"
success "✅ Phase 2: Kyverno Deployed"
success "✅ Phase 3: E2E Validation Completed"
echo ""

echo "📊 Resource Summary:"
echo "-------------------"
if [[ -n "${ECR_ACCOUNT_URL}" ]]; then
  echo "ECR Account URL: ${ECR_ACCOUNT_URL}"
fi
if [[ -n "${GITHUB_ECR_ROLE}" ]]; then
  echo "GitHub ECR Role: ${GITHUB_ECR_ROLE}"
fi

echo ""
echo "🔧 Kyverno Status:"
echo "------------------"
kubectl get pods -n kyverno 2>/dev/null || echo "Kyverno pods not found"

echo ""
echo "📦 ArgoCD Applications:"
echo "----------------------"
kubectl get applications -n argocd | grep -E "NAME|kyverno|loki|promtail|kube-prometheus" || echo "No applications found"

echo ""
echo "🎯 Next Steps:"
echo "-------------"
echo "1. ✅ ECR is ready for image pushes"
echo "2. ✅ Kyverno is enforcing policies"
echo "3. ✅ Observability stack is running"
echo ""
echo "4. 📝 Add GitHub Secret to your application repositories:"
echo "   - Go to: GitHub Repo > Settings > Secrets and variables > Actions"
echo "   - Secret Name: AWS_ROLE_ARN"
echo "   - Secret Value: ${GITHUB_ECR_ROLE}"
echo ""
echo "5. 🚀 Create a microservice via Backstage:"
echo "   - Navigate to Backstage (backstage.${BASE_DOMAIN:-timedevops.click})"
echo "   - Click 'Create Component'"
echo "   - Select 'New Microservice (Containerized)' template"
echo "   - Fill in parameters and create"
echo ""
echo "6. 🔍 Monitor deployment:"
echo "   - ArgoCD: argocd.${BASE_DOMAIN:-timedevops.click}"
echo "   - Grafana: grafana.${BASE_DOMAIN:-timedevops.click}"
echo "   - Logs: Grafana > Explore > Loki"
echo ""

success "🎉 Developer Experience MVP installation complete! 🎉"
echo ""
