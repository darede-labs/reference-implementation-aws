provider "aws" {
  region = local.region
  # Profile sourced from environment: export AWS_PROFILE=darede
  # This allows multi-operator usage and AWS SSO compatibility
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# Configuration is loaded from config.yaml via locals.tf

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name                   = local.cluster_name
  cluster_version                = "1.33"
  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  # EKS Auto Mode configuration
  # When enabled, EKS automatically manages compute resources and core addons
  # This eliminates the need for managed node groups and manual addon management
  # Note: Commenting out for standard mode (auto_mode=false) as this parameter
  # is only valid for Auto Mode clusters
  # cluster_compute_config = {
  #   enabled    = true
  #   node_pools = ["general-purpose", "system"]
  # }

  # Only create managed node groups when not using Auto Mode
  # Auto Mode handles compute resources automatically
  # Configuration loaded from config.yaml (node_groups section)
  eks_managed_node_groups = local.auto_mode ? {} : {
    configurable_nodes = {
      name = "nodes"

      # Instance types from config.yaml
      instance_types = local.instance_types

      # Capacity type from config.yaml: SPOT or ON_DEMAND
      capacity_type  = local.capacity_type

      # Auto Scaling from config.yaml
      min_size     = local.node_min_size
      max_size     = local.node_max_size
      desired_size = local.node_desired

      # Disk size from config.yaml
      disk_size = local.node_disk_size

      # Labels from config.yaml
      labels = local.node_labels

      # Tags for Cluster Autoscaler
      tags = merge(
        local.tags,
        {
          "k8s.io/cluster-autoscaler/enabled" = "true"
          "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
        }
      )
    }
  }

  # Conditional cluster addons based on Auto Mode
  # Auto Mode automatically manages: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver, AWS Load Balancer Controller, eks-pod-identity-agent
  cluster_addons = local.auto_mode ? {
    # Auto Mode manages all addons automatically - no explicit addon configuration needed
  } : {
    # Standard mode requires all addons to be explicitly managed
    coredns = {}
    eks-pod-identity-agent = {}
    kube-proxy = {}
    vpc-cni = {}
    aws-ebs-csi-driver = {}
  }

  tags = local.tags
}


################################################################################
# IAM Policies
################################################################################

resource "aws_iam_policy" "crossplane_boundary" {
  name   = "crossplane-permissions-boundary"
  policy = local.crossplane_boundary_policy

  tags = local.tags
}

################################################################################
# Pod Identity
################################################################################

# AWS Load Balancer Controller - Only needed when not using Auto Mode
module "aws_load_balancer_controller_pod_identity" {
  count   = local.auto_mode ? 0 : 1
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "aws_load_balancer_controller"
  attach_aws_lb_controller_policy = true
  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = local.tags
}

# External DNS - Required for both Auto Mode and standard mode
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "external-dns"
  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [ "*" ]
  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
  tags = local.tags
}

# EBS CSI Driver - Only needed when not using Auto Mode
module "ebs_csi_driver_pod_identity" {
  count   = local.auto_mode ? 0 : 1
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "ebs-csi-driver"
  attach_aws_ebs_csi_policy = true
  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
  tags = local.tags
}

# Crossplane - Required for both Auto Mode and standard mode
module "crossplane_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "crossplane-provider-aws"

  additional_policy_arns   = {
    admin = "arn:aws:iam::aws:policy/AdministratorAccess"
  }
  permissions_boundary_arn = aws_iam_policy.crossplane_boundary.arn

  associations = {
    crossplane = {
      cluster_name    = module.eks.cluster_name
      namespace       = "crossplane-system"
      service_account = "provider-aws"
    }
  }

  tags = local.tags
}

# External Secrets - Required for both Auto Mode and standard mode
# Using Pod Identity (new method)
module "external_secrets_pod_identity" {
  count   = local.use_pod_identity ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "external-secrets"
  attach_custom_policy = true
  override_policy_documents = [local.external_secret_policy]
  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }

  tags = local.tags
}

# External Secrets - Using IRSA (traditional method, more compatible)
module "external_secrets_irsa" {
  count   = local.use_irsa ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "external-secrets-irsa"

  role_policy_arns = {
    policy = aws_iam_policy.external_secrets_policy[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "external_secrets_policy" {
  count  = local.use_irsa ? 1 : 0
  name   = "external-secrets-policy"
  policy = local.external_secret_policy

  tags = local.tags
}

################################################################################
# Backstage IRSA - For Terraform scaffolder actions
################################################################################

module "backstage_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "backstage-terraform-irsa"

  role_policy_arns = {
    custom_policy = aws_iam_policy.backstage_terraform_policy.arn
    power_user    = "arn:aws:iam::aws:policy/PowerUserAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["backstage:backstage"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "backstage_terraform_policy" {
  name   = "backstage-terraform-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.terraform_state_bucket}",
          "arn:aws:s3:::${local.terraform_state_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/ManagedBy" = "backstage"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "rds:*",
          "dynamodb:*",
          "lambda:*",
          "cloudfront:*",
          "elasticloadbalancing:*",
          "secretsmanager:*",
          "iam:PassRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
          "iam:ListInstanceProfileTags",
          "logs:*",
          "eks:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

################################################################################
# VPC
################################################################################

# VPC Module - Configuration from config.yaml
# Supports: create new VPC or use existing VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # Only create VPC if mode is "create"
  create_vpc = local.create_vpc

  name = "${local.cluster_name}-vpc"
  cidr = local.vpc_cidr

  # Availability Zones from config.yaml
  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  # NAT Gateway configuration from config.yaml
  enable_nat_gateway = true
  single_nat_gateway = local.nat_gateway_single  # true = $32/month, false = $96/month (3 AZs)
  one_nat_gateway_per_az = !local.nat_gateway_single

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
