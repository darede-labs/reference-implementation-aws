terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "${{ values.tfBackendBucket }}"
    key            = "platform/terraform/stacks/s3/${{ values.name }}/terraform.tfstate"
    region         = "${{ values.tfBackendRegion }}"
    dynamodb_table = "${{ values.tfLocksTable }}"
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
