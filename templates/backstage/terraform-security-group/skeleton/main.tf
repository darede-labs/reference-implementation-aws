terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "idp-poc-terraform-state-948881762705"
    key            = "platform/terraform/stacks/security-group/${{ values.name }}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "idp-poc-terraform-locks"
    encrypt        = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Environment = "${{ values.environment }}", ManagedBy = "Terraform", CreatedVia = "Backstage", Owner = "${{ values.owner }}" }
  }
}

data "aws_vpc" "default" { default = true }

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  name        = "${{ values.name }}"
  description = "${{ values.description }}"
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = compact([
    "${{ values.allowSsh }}" == "true" ? "ssh-tcp" : "",
    "${{ values.allowHttp }}" == "true" ? "http-80-tcp" : "",
    "${{ values.allowHttps }}" == "true" ? "https-443-tcp" : ""
  ])
  egress_rules = ["all-all"]
}

output "security_group_id" { value = module.security_group.security_group_id }
