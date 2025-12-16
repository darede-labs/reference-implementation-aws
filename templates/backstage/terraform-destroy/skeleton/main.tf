# This file intentionally empties the Terraform configuration to trigger resource destruction.
# When Atlantis detects this change, it will plan the deletion of all resources.
# After successful apply (destroy), merge the PR to complete the cleanup.

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key          = "platform/terraform/stacks/${{ values.resourceType }}/${{ values.resourceName }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# All resources have been removed - Terraform will destroy them
