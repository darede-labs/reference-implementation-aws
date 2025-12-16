terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "idp-poc-terraform-state-948881762705"
    key            = "platform/terraform/stacks/s3/${{ values.name }}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "idp-poc-terraform-locks"
    encrypt        = true
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

  default_tags {
    tags = {
      Environment = "${{ values.environment }}"
      ManagedBy   = "Terraform"
      CreatedVia  = "Backstage"
      Owner       = "${{ values.owner }}"
    }
  }
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "${{ values.name }}"

  versioning = {
    enabled = ${{ values.enableVersioning }}
  }

  force_destroy = ${{ values.forceDestroy }}

  tags = merge(
    {
      Name        = "${{ values.name }}"
      Environment = "${{ values.environment }}"
    },
    {
      {%- for tag in values.tags %}
      "${{ tag.key }}" = "${{ tag.value }}"
      {%- endfor %}
    }
  )
}

output "bucket_id" {
  value = module.s3_bucket.s3_bucket_id
}

output "bucket_arn" {
  value = module.s3_bucket.s3_bucket_arn
}
