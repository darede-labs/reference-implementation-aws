################################################################################
# Karpenter - Dynamic Node Provisioner
################################################################################
# Karpenter automatically provisions right-sized nodes based on pod requirements
# Provides significant cost savings through:
# - Spot instance usage
# - Node consolidation (removes underutilized nodes)
# - Flexible instance type selection
################################################################################
# Note: karpenter_enabled is defined in locals.tf

################################################################################
# Karpenter Module
################################################################################

module "karpenter" {
  count   = local.karpenter_enabled ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.37"

  cluster_name = module.eks.cluster_name

  # Enable IAM Roles for Service Accounts (IRSA) for Karpenter
  enable_irsa            = true
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  # Node IAM role for instances launched by Karpenter
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

################################################################################
# Karpenter Helm Release (installed via Terraform for consistency)
################################################################################

resource "helm_release" "karpenter" {
  count      = local.karpenter_enabled ? 1 : 0
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.1.1" # Latest stable version as of 2026-01

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter[0].queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter[0].iam_role_arn
        }
      }
      # Resource limits for Karpenter controller
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
    })
  ]

  depends_on = [
    module.eks,
    module.karpenter
  ]
}

################################################################################
# Karpenter NodePool (previously Provisioner in v0.x)
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  count = local.karpenter_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      # Template for nodes created by this NodePool
      template = {
        spec = {
          # Node class reference
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }

          # Requirements for node selection
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = [try(local.config_file.karpenter.capacity_type, "spot")]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = try(local.config_file.karpenter.instance_types, ["t3a.medium", "t3.medium", "t2.medium"])
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            }
          ]

          # Taints to apply to nodes (optional)
          # taints = []
        }
      }

      # Resource limits to prevent runaway costs
      limits = {
        cpu    = try(local.config_file.karpenter.limits.cpu, "20")
        memory = try(local.config_file.karpenter.limits.memory, "80Gi")
      }

      # Disruption budget
      disruption = {
        consolidationPolicy = try(local.config_file.karpenter.consolidation_enabled, true) ? "WhenEmptyOrUnderutilized" : "WhenEmpty"
        consolidateAfter    = "${try(local.config_file.karpenter.ttl_seconds_after_empty, 30)}s"
        budgets = [
          {
            nodes = try(local.config_file.karpenter.disruption_budget, "10%")
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.karpenter
  ]
}

################################################################################
# Karpenter EC2NodeClass (AWS-specific configuration)
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  count = local.karpenter_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      # AMI Family
      amiFamily = "AL2023" # Amazon Linux 2023 (recommended)

      # Subnets for node placement
      subnetSelectorTerms = [
        {
          tags = {
            "kubernetes.io/role/internal-elb" = "1"
          }
        }
      ]

      # Security groups for nodes
      securityGroupSelectorTerms = [
        {
          tags = {
            "aws:eks:cluster-name" = module.eks.cluster_name
          }
        }
      ]

      # IAM role for nodes
      role = module.karpenter[0].node_iam_role_name

      # User data (bootstrap script)
      userData = base64encode(<<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${module.eks.cluster_name}
      EOT
      )

      # Block device mappings
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "${try(local.config_file.karpenter.disk_size, 50)}Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]

      # Tags to apply to launched instances
      tags = merge(
        local.tags,
        {
          Name                   = "${local.cluster_name}-karpenter-node"
          "karpenter.sh/cluster" = module.eks.cluster_name
        }
      )

      # Metadata options for IMDSv2
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required" # IMDSv2 only
      }
    }
  })

  depends_on = [
    helm_release.karpenter
  ]
}

################################################################################
# IAM Role for Karpenter Bootstrap Nodes
################################################################################

resource "aws_iam_role" "karpenter_bootstrap_node" {
  count = local.karpenter_enabled ? 1 : 0
  name  = "${local.cluster_name}-karpenter-bootstrap-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Attach required policies for EKS nodes
resource "aws_iam_role_policy_attachment" "karpenter_bootstrap_node_policy" {
  for_each = local.karpenter_enabled ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]) : []

  role       = aws_iam_role.karpenter_bootstrap_node[0].name
  policy_arn = each.value
}

################################################################################
# Initial Node Group for Karpenter Bootstrap
################################################################################
# When using Karpenter, we still need a small managed node group to:
# 1. Run Karpenter controller itself
# 2. Provide initial capacity until Karpenter takes over
# This is a best practice to avoid chicken-and-egg problem
################################################################################

resource "aws_eks_node_group" "karpenter_bootstrap" {
  count = local.karpenter_enabled ? 1 : 0

  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-karpenter-bootstrap"
  node_role_arn   = aws_iam_role.karpenter_bootstrap_node[0].arn
  subnet_ids      = module.vpc.private_subnets

  # Use on-demand for stability (Karpenter controller must always run)
  capacity_type = "ON_DEMAND"

  instance_types = ["t3a.small"] # Small instance for Karpenter controller

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  # Taint to prevent workloads from scheduling here
  # Karpenter will provision separate nodes for application workloads
  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    role                     = "karpenter-bootstrap"
    "karpenter.sh/discovery" = module.eks.cluster_name
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-karpenter-bootstrap"
    }
  )

  # Ensure proper ordering
  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.karpenter_bootstrap_node_policy
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
