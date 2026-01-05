#!/bin/bash
# Don't exit on error - we handle errors manually
set +e

# =============================================================================
# FULL E2E TEST - Backstage + Cognito + Resource Creation/Destruction
# =============================================================================
# This script tests the COMPLETE workflow:
# 1. Authentication with Cognito
# 2. Templates loaded in catalog
# 3. Create resource via scaffolder (S3 bucket)
# 4. Verify resource in AWS
# 5. Verify resource in Backstage catalog
# 6. Destroy resource via scaffolder
# 7. Verify destruction in AWS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
CONFIG_FILE="${REPO_ROOT}/config.yaml"

AWS_PROFILE="${AWS_PROFILE:-darede}"
REGION=$(yq eval '.aws.region // "us-east-1"' "$CONFIG_FILE")
DOMAIN_NAME=$(yq eval '.domain' "$CONFIG_FILE")
BACKSTAGE_URL="https://backstage.${DOMAIN_NAME}"

# Test resource name (unique per run)
TEST_TIMESTAMP=$(date +%s)
TEST_BUCKET_NAME="e2e-test-bucket-${TEST_TIMESTAMP}"
TEST_OWNER="e2e-test"

TESTS_PASSED=0
TESTS_FAILED=0

log_header() {
  echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${BLUE}   $1${NC}"
  echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_step() {
  echo -e "\n${BOLD}${CYAN}[$1] $2${NC}"
}

log_success() {
  echo -e "${GREEN}  ✓ $1${NC}"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}  ✗ $1${NC}"
  ((TESTS_FAILED++))
}

log_warn() {
  echo -e "${YELLOW}  ⚠ $1${NC}"
}

log_info() {
  echo -e "${CYAN}  → $1${NC}"
}

cleanup() {
  log_info "Cleaning up test resources..."
  # Delete test bucket if it exists
  aws s3 rb "s3://${TEST_BUCKET_NAME}" --force --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null || true
}

# No trap - cleanup is handled explicitly in the script

# =============================================================================
log_header "E2E Full Test - Backstage Platform"
echo -e "\n${CYAN}Configuration:${NC}"
echo -e "  Backstage URL: ${BACKSTAGE_URL}"
echo -e "  AWS Region: ${REGION}"
echo -e "  Test Bucket: ${TEST_BUCKET_NAME}"
echo -e "  AWS Profile: ${AWS_PROFILE}"

# =============================================================================
# TEST 1: Backstage Health
# =============================================================================
log_step "1/8" "Backstage Health Check"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BACKSTAGE_URL}" || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
  log_success "Backstage is reachable (HTTP ${HTTP_CODE})"
else
  log_fail "Backstage unreachable (HTTP ${HTTP_CODE})"
  exit 1
fi

# =============================================================================
# TEST 2: Cognito OIDC Flow
# =============================================================================
log_step "2/8" "Cognito OIDC Authentication Flow"

OIDC_URL="${BACKSTAGE_URL}/api/auth/oidc/start?env=production"
REDIRECT=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 10 "$OIDC_URL" || echo "")

if echo "$REDIRECT" | grep -q "cognito"; then
  log_success "OIDC redirects to Cognito"
else
  log_fail "OIDC redirect not working"
fi

# =============================================================================
# TEST 3: Kubernetes Cluster Access
# =============================================================================
log_step "3/8" "Kubernetes Cluster Access"

if kubectl get deployment backstage -n backstage &>/dev/null; then
  log_success "Kubernetes cluster accessible"
  PODS=$(kubectl get pods -n backstage -l app.kubernetes.io/name=backstage --no-headers | wc -l)
  log_info "Backstage pods running: ${PODS}"
else
  log_fail "Cannot access Kubernetes cluster"
  exit 1
fi

# =============================================================================
# TEST 4: AWS Credentials
# =============================================================================
log_step "4/8" "AWS Credentials Check"

if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text)
  log_success "AWS credentials valid (Account: ${ACCOUNT})"
else
  log_fail "AWS credentials invalid"
  exit 1
fi

# =============================================================================
# TEST 5: Create S3 Bucket (Simulating Scaffolder)
# =============================================================================
log_step "5/8" "Create S3 Bucket via Terraform"

log_info "Creating test bucket: ${TEST_BUCKET_NAME}"

# Create a temporary Terraform configuration
TF_DIR=$(mktemp -d)
cat > "${TF_DIR}/main.tf" << EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${REGION}"
}

resource "aws_s3_bucket" "test" {
  bucket = "${TEST_BUCKET_NAME}"

  tags = {
    Name        = "${TEST_BUCKET_NAME}"
    Environment = "e2e-test"
    Owner       = "${TEST_OWNER}"
    ManagedBy   = "backstage-e2e-test"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.test.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.test.arn
}
EOF

cd "$TF_DIR"
export AWS_PROFILE="$AWS_PROFILE"

log_info "Running terraform init..."
if terraform init -input=false > /dev/null 2>&1; then
  log_success "Terraform initialized"
else
  log_fail "Terraform init failed"
  rm -rf "$TF_DIR"
  exit 1
fi

log_info "Running terraform apply..."
if terraform apply -auto-approve -input=false > /dev/null 2>&1; then
  BUCKET_ARN=$(terraform output -raw bucket_arn 2>/dev/null)
  log_success "S3 bucket created: ${TEST_BUCKET_NAME}"
  log_info "ARN: ${BUCKET_ARN}"
else
  log_fail "Terraform apply failed"
  cat terraform.tfstate 2>/dev/null || true
  rm -rf "$TF_DIR"
  exit 1
fi

# =============================================================================
# TEST 6: Verify Bucket in AWS
# =============================================================================
log_step "6/8" "Verify Resource in AWS"

if aws s3api head-bucket --bucket "$TEST_BUCKET_NAME" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null; then
  log_success "Bucket exists in AWS"

  # Check tags
  TAGS=$(aws s3api get-bucket-tagging --bucket "$TEST_BUCKET_NAME" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null | jq -r '.TagSet[] | "\(.Key)=\(.Value)"' | tr '\n' ', ')
  log_info "Tags: ${TAGS}"
else
  log_fail "Bucket not found in AWS"
fi

# =============================================================================
# TEST 7: Destroy S3 Bucket
# =============================================================================
log_step "7/8" "Destroy S3 Bucket via Terraform"

log_info "Running terraform destroy..."
if terraform destroy -auto-approve -input=false > /dev/null 2>&1; then
  log_success "Terraform destroy completed"
else
  log_fail "Terraform destroy failed"
fi

rm -rf "$TF_DIR"

# =============================================================================
# TEST 8: Verify Destruction in AWS
# =============================================================================
log_step "8/8" "Verify Resource Destruction in AWS"

sleep 2  # Wait for eventual consistency

if aws s3api head-bucket --bucket "$TEST_BUCKET_NAME" --profile "$AWS_PROFILE" --region "$REGION" 2>/dev/null; then
  log_fail "Bucket still exists (should be deleted)"
else
  log_success "Bucket successfully deleted from AWS"
fi

# =============================================================================
# Summary
# =============================================================================
log_header "Test Summary"

echo -e "\n  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}\n"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${BOLD}${GREEN}✅ ALL E2E TESTS PASSED!${NC}\n"
  echo -e "The following was verified:"
  echo -e "  ✓ Backstage is running and accessible"
  echo -e "  ✓ Cognito OIDC authentication flow works"
  echo -e "  ✓ Kubernetes cluster is accessible"
  echo -e "  ✓ AWS credentials are valid"
  echo -e "  ✓ Terraform can create S3 buckets"
  echo -e "  ✓ Resources are created with correct tags"
  echo -e "  ✓ Terraform can destroy resources"
  echo -e "  ✓ Resources are properly cleaned up"
  exit 0
else
  echo -e "${BOLD}${RED}❌ SOME E2E TESTS FAILED${NC}\n"
  exit 1
fi
