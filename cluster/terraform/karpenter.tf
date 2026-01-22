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
# Karpenter Installation
################################################################################
# NOTE: Karpenter Helm chart and CRDs must be installed AFTER cluster creation.
#
# This is intentionally not managed by Terraform to avoid circular dependencies.
# After cluster creation, install using:
#
# 1. Configure kubectl:
#    aws eks update-kubeconfig --name <cluster-name> --region us-east-1
#
# 2. Install Karpenter:
#    helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
#      --version 1.1.1 \
#      --namespace kube-system \
#      --set settings.clusterName=$(terraform output -raw cluster_name) \
#      --set settings.clusterEndpoint=$(terraform output -raw cluster_endpoint) \
#      --set settings.interruptionQueue=$(terraform output -raw karpenter_queue_name) \
#      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw karpenter_irsa_arn)
#
# 3. Apply NodePool and EC2NodeClass manifests from packages/karpenter/ directory
#
################################################################################

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

  instance_types = ["t3a.small", "t3.small"] # Small instances for Karpenter controller

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  # Labels for identification
  # Note: No taints - allow system pods and Karpenter controller to schedule here
  # Application workloads will prefer Karpenter-provisioned nodes via nodeSelector/affinity
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
