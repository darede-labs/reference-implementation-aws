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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
