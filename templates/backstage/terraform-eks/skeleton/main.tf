terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "${{ values.tfBackendBucket }}"
    key          = "platform/terraform/stacks/eks/${{ values.name }}/terraform.tfstate"
    region       = "${{ values.tfBackendRegion }}"
    use_lockfile = true
    encrypt      = true
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
  cidr = "${{ values.vpcCidr | default('10.0.0.0/16') }}"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${{ values.name }}"
  cluster_version = "${{ values.kubernetesVersion | default('1.31') }}"

  cluster_endpoint_public_access = ${{ values.enablePublicAccess | default(true) }}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable IRSA
  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      name = "${{ values.name }}-nodes"

      instance_types = ["${{ values.nodeInstanceType | default('t3.medium') }}"]
      capacity_type  = "${{ values.capacityType | default('ON_DEMAND') }}"

      min_size     = ${{ values.nodeMinSize | default(1) }}
      max_size     = ${{ values.nodeMaxSize | default(4) }}
      desired_size = ${{ values.nodeDesiredSize | default(2) }}

      labels = {
        Environment = "${{ values.environment }}"
      }
    }
  }

  # Cluster access entry for creator
  enable_cluster_creator_admin_permissions = true
}

output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_version" { value = module.eks.cluster_version }
output "cluster_arn" { value = module.eks.cluster_arn }
output "configure_kubectl" {
  value = "aws eks --region us-east-1 update-kubeconfig --name ${{ values.name }}"
}
