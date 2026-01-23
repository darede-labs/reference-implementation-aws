################################################################################
# Karpenter - Node Autoscaling
# Why: Intelligent, fast node provisioning based on actual workload needs
# Replaces: Cluster Autoscaler (slower, less flexible)
################################################################################

locals {
  karpenter_namespace        = "karpenter"
  karpenter_service_account = "karpenter"
}

################################################################################
# Karpenter IAM Role (IRSA)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Enable spot instance support
  enable_spot_termination          = true
  enable_v1_permissions            = true
  
  # Node IAM role
  create_node_iam_role = false # We'll use the EKS module's node role
  node_iam_role_arn    = module.eks.eks_managed_node_groups["bootstrap"].iam_role_arn

  # IRSA for Karpenter controller
  enable_irsa                     = true
  irsa_namespace_service_accounts = ["${local.karpenter_namespace}:${local.karpenter_service_account}"]
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
}

################################################################################
# Karpenter Helm Chart
################################################################################

resource "helm_release" "karpenter" {
  depends_on = [module.eks]

  namespace        = local.karpenter_namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.6" # Latest stable as of Jan 2026

  values = [
    yamlencode({
      serviceAccount = {
        name = local.karpenter_service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }

      settings = {
        clusterName     = module.eks.cluster_name
        clusterEndpoint = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }

      # Run on bootstrap nodes
      tolerations = [{
        key      = "node-role.kubernetes.io/bootstrap"
        operator = "Exists"
        effect   = "NoSchedule"
      }]

      nodeSelector = {
        role = "bootstrap"
      }

      # Resources
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

      # Replica count
      replicas = 1 # Single replica for dev, increase for production
    })
  ]
}

################################################################################
# Karpenter EC2NodeClass
# Defines the EC2 configuration for nodes
################################################################################

resource "kubernetes_manifest" "karpenter_node_class" {
  depends_on = [helm_release.karpenter]

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      # AMI Selection - ARM64 optimized
      amiFamily = "AL2"
      amiSelectorTerms = [{
        alias = "al2@latest"
      }]

      # Subnet selection - use private subnets with Karpenter tag
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = module.eks.cluster_name
        }
      }]

      # Security group selection
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = module.eks.cluster_name
        }
      }]

      # IAM role for nodes
      role = module.eks.eks_managed_node_groups["bootstrap"].iam_role_name

      # User data
      userData = <<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${module.eks.cluster_name}
      EOT

      # Block device mappings
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "50Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]

      # Metadata options
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required" # IMDSv2 required
      }

      # Tags
      tags = merge(
        var.default_tags,
        {
          "karpenter.sh/discovery" = module.eks.cluster_name
        }
      )
    }
  }
}

################################################################################
# Karpenter NodePool
# Defines when and how to provision nodes
################################################################################

resource "kubernetes_manifest" "karpenter_node_pool" {
  depends_on = [kubernetes_manifest.karpenter_node_class]

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      # Template for nodes
      template = {
        metadata = {
          labels = {
            "karpenter.sh/managed" = "true"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }

          # Requirements - what kinds of nodes can be created
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"] # ARM64 only for cost optimization
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"] # On-demand only, no spot for now
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["t", "c", "m"] # General purpose and compute optimized
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["3"] # Gen 4+ only (modern instances)
            }
          ]
        }
      }

      # Limits - prevent runaway scaling
      limits = {
        cpu    = "100" # Max 100 vCPUs across all Karpenter nodes
        memory = "200Gi"
      }

      # Disruption budget
      disruption = {
        consolidationPolicy = "WhenEmpty" # Only consolidate empty nodes
        expireAfter         = "720h"      # 30 days - rotate nodes monthly
        
        budgets = [{
          nodes = "10%" # Allow disrupting 10% of nodes at a time
        }]
      }

      # Weight - lower number = higher priority
      weight = 10
    }
  }
}

################################################################################
# Security Group for Karpenter Nodes
################################################################################

resource "aws_security_group_rule" "karpenter_node_discovery" {
  description              = "Allow Karpenter node discovery"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

# Tag the node security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_node_sg" {
  resource_id = module.eks.node_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}
