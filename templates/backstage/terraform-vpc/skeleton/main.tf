terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key            = "platform/terraform/stacks/vpc/${{ values.name }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
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

data "aws_availability_zones" "available" { state = "available" }

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, ${{ values.azCount | default(2) }})
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name = "${{ values.name }}"
  cidr = "${{ values.cidr }}"
  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet("${{ values.cidr }}", 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet("${{ values.cidr }}", 8, k + 48)]
  enable_nat_gateway   = ${{ values.enableNatGateway | default(true) }}
  single_nat_gateway   = true
  enable_dns_hostnames = true
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
output "public_subnets" { value = module.vpc.public_subnets }
