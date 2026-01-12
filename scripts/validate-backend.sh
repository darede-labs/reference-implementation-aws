#!/bin/bash
set -e -o pipefail

# Validate and create Terraform S3 backend bucket if needed
# This script is called before terraform init to ensure backend exists

export REPO_ROOT=$(git rev-parse --show-toplevel)
source ${REPO_ROOT}/scripts/utils.sh

# Read backend config from config.yaml
BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
BACKEND_REGION=$(yq eval '.terraform_backend.region' ${CONFIG_FILE})

if [ -z "$BACKEND_BUCKET" ] || [ "$BACKEND_BUCKET" = "null" ]; then
  echo -e "${RED}❌ ERROR: terraform_backend.bucket not defined in config.yaml${NC}"
  exit 1
fi

if [ -z "$BACKEND_REGION" ] || [ "$BACKEND_REGION" = "null" ]; then
  echo -e "${RED}❌ ERROR: terraform_backend.region not defined in config.yaml${NC}"
  exit 1
fi

echo -e "${CYAN}🔍 Checking Terraform backend bucket: ${BACKEND_BUCKET}${NC}"

# Check if bucket exists
if aws s3api head-bucket --bucket "${BACKEND_BUCKET}" ${AWS_PROFILE:+--profile $AWS_PROFILE} 2>/dev/null; then
  echo -e "${GREEN}✅ Backend bucket exists: ${BACKEND_BUCKET}${NC}"
else
  echo -e "${YELLOW}⚠️  Backend bucket does not exist. Creating...${NC}"

  # Create bucket
  if [ "$BACKEND_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "${BACKEND_BUCKET}" \
      --region "${BACKEND_REGION}" \
      ${AWS_PROFILE:+--profile $AWS_PROFILE}
  else
    aws s3api create-bucket \
      --bucket "${BACKEND_BUCKET}" \
      --region "${BACKEND_REGION}" \
      --create-bucket-configuration LocationConstraint="${BACKEND_REGION}" \
      ${AWS_PROFILE:+--profile $AWS_PROFILE}
  fi

  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "${BACKEND_BUCKET}" \
    --versioning-configuration Status=Enabled \
    ${AWS_PROFILE:+--profile $AWS_PROFILE}

  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "${BACKEND_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }' \
    ${AWS_PROFILE:+--profile $AWS_PROFILE}

  # Block public access
  aws s3api put-public-access-block \
    --bucket "${BACKEND_BUCKET}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    ${AWS_PROFILE:+--profile $AWS_PROFILE}

  echo -e "${GREEN}✅ Backend bucket created with versioning, encryption, and public access block${NC}"
fi

# Export for use by terraform init
export TF_BACKEND_BUCKET="${BACKEND_BUCKET}"
export TF_BACKEND_REGION="${BACKEND_REGION}"
export TF_BACKEND_KEY="cluster-state/terraform.tfstate"

echo -e "${CYAN}📦 Backend configuration:${NC}"
echo -e "  Bucket: ${BACKEND_BUCKET}"
echo -e "  Region: ${BACKEND_REGION}"
echo -e "  Key: ${TF_BACKEND_KEY}"
