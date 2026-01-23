################################################################################
# EKS Cluster
# Uses terraform-aws-modules/eks - community standard
# Why: Proven module, handles IRSA, IAM, security best practices
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint configuration
  # Why: Public + private allows external access while keeping node traffic private
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable IRSA (IAM Roles for Service Accounts)
  # Why: Best practice for pod-level IAM permissions
  enable_irsa = true

  # VPC configuration from remote state
  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # Control plane logging
  # Why: Essential for troubleshooting
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Add-ons - minimal set
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      # Enable prefix delegation for more IPs per node
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
  }

  # Bootstrap node group
  # Why: Karpenter needs existing capacity to run (chicken-egg problem)
  # This node group hosts Karpenter itself, then Karpenter manages all other workloads
  eks_managed_node_groups = {
    bootstrap = {
      name = "${var.cluster_name}-bootstrap"

      # ARM64 Graviton instances
      # Why: Cost-effective, modern, good performance
      ami_type       = "AL2_ARM_64"
      instance_types = ["t4g.medium"]

      # On-demand only for stability
      # Why: Bootstrap nodes must be reliable, no spot interruptions
      capacity_type = "ON_DEMAND"

      # Minimal scaling
      # Why: Only need capacity for core platform tools (Karpenter, CoreDNS, etc.)
      min_size     = 1
      max_size     = 2
      desired_size = 1

      # Taint to prevent workloads from scheduling here
      # Why: Workloads should go to Karpenter-managed nodes
      taints = [{
        key    = "node-role.kubernetes.io/bootstrap"
        value  = "true"
        effect = "NoSchedule"
      }]

      labels = {
        role = "bootstrap"
      }

      # Block device configuration
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Allow SSM for debugging
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  # Allow access from current machine
  cluster_security_group_additional_rules = {
    ingress_workstation = {
      description = "Workstation access"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"] # Consider restricting in production
    }
  }
}

################################################################################
# Bootstrap Node Group Documentation
################################################################################
# The bootstrap node group exists to solve the Karpenter chicken-egg problem:
# - Karpenter needs to run IN the cluster to provision nodes
# - But the cluster needs nodes to run Karpenter
#
# Solution:
# 1. Bootstrap nodes provide initial capacity
# 2. Karpenter deploys to bootstrap nodes (tolerates taint)
# 3. Karpenter provisions nodes for all other workloads
# 4. Bootstrap nodes remain running only for core platform tools
#
# Why ARM64 (Graviton):
# - 20% better price/performance vs x86
# - Good availability
# - Supported by all modern platform tools
#
# Why NoSchedule taint:
# - Forces workloads to use Karpenter-managed nodes
# - Keeps bootstrap nodes available for platform tools
# - Prevents resource contention
################################################################################
