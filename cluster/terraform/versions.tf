terraform {
  required_version = ">= 1.0"

  # S3 backend configuration - values injected from config.yaml
  # Bucket must exist before terraform init
  backend "s3" {
    # These values are provided via:
    # terraform init -backend-config="bucket=..." -backend-config="key=..." -backend-config="region=..."
    # OR via backend.tf file generated at runtime
    # key is fixed to cluster-state for EKS infrastructure
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
