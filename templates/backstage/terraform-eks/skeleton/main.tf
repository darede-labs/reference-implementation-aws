terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "idp-poc-terraform-state-948881762705"
    key            = "platform/terraform/stacks/eks/${{ values.name }}/terraform.tfstate"
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

data "aws_availability_zones" "available" { state = "available" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name = "${{ values.name }}-vpc"
  cidr = "10.0.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name    = "${{ values.name }}"
  cluster_version = "${{ values.kubernetesVersion }}"
  cluster_endpoint_public_access = true
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  eks_managed_node_groups = {
    default = {
      instance_types = ["${{ values.nodeInstanceType }}"]
      min_size     = 1
      max_size     = 4
      desired_size = ${{ values.nodeDesiredSize }}
    }
  }
}

output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_name" { value = module.eks.cluster_name }
