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

  # EKS Pod Identity (modern approach, replaces IRSA)
  # Ref: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/karpenter
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Namespace and service account for Karpenter controller
  namespace       = "kube-system"
  service_account = "karpenter"

  # Enable v1+ permissions (Karpenter 1.x)
  enable_v1_permissions = true

  # Node IAM role for instances launched by Karpenter
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# Additional IAM permissions for Karpenter controller (ListInstanceProfiles)
resource "aws_iam_role_policy" "karpenter_additional_permissions" {
  count = local.karpenter_enabled ? 1 : 0

  name = "KarpenterAdditionalPermissions"
  role = module.karpenter[0].iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:ListInstanceProfiles",
          "iam:GetInstanceProfile"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Karpenter Helm Installation (Automated via Terraform)
################################################################################
# Order of operations:
# 1. Cluster created
# 2. Bootstrap node group created (SPOT, Graviton, 1 instance)
# 3. EKS addons installed (wait for nodes)
# 4. Karpenter Helm chart installed (via Helm provider)
# 5. NodePool and EC2NodeClass applied (via kubectl provider)
#
# NOTE: Helm and kubectl providers are configured in providers.tf
# They use dynamic values from module.eks outputs
################################################################################

# Install Karpenter Helm chart
# CRITICAL: Must wait for bootstrap nodes to be ready AND addons installed
resource "helm_release" "karpenter" {
  count = local.karpenter_enabled ? 1 : 0

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.8.0"  # Latest stable version (Jan 2026) - https://karpenter.sh/docs/getting-started/
  namespace  = "kube-system"

  # Use values YAML to configure Karpenter
  # Ref: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
  # CRITICAL FIX for bug in chart 1.8.0: Must explicitly set staticCapacity=false
  # Issues: https://github.com/kubernetes-sigs/karpenter/issues/2566
  #         https://github.com/aws/karpenter-provider-aws/issues/8608
  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter[0].queue_name
        # CRITICAL: Explicitly set feature gates with LOWERCASE 'staticCapacity'
        # The chart has a bug where StaticCapacity (uppercase) becomes empty
        featureGates = {
          staticCapacity          = false  # MUST be lowercase 's' to work
          spotToSpotConsolidation = false
          nodeRepair              = false
          nodeOverlay             = false
        }
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter[0].iam_role_arn
        }
      }
      controller = {
        resources = {
          requests = {
            cpu    = "500m"
            memory = "1Gi"
          }
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
        }
      }
    })
  ]

  # CRITICAL: Set replicas to 1 (not 2) to avoid unnecessary pod pending on bootstrap node
  set {
    name  = "replicas"
    value = "1"
  }

  # CRITICAL: Tolerate bootstrap taint to run on bootstrap node
  set {
    name  = "tolerations[0].key"
    value = "node-role.kubernetes.io/bootstrap"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  # Wait for bootstrap nodes and addons to be ready
  depends_on = [
    time_sleep.wait_for_nodes,
    module.eks.cluster_addons
  ]

  wait    = true
  timeout = 300
}

# Apply Karpenter NodePool and EC2NodeClass
# These are rendered from templates (via render-templates.sh) and applied after Karpenter is installed
# CRITICAL: Templates must be rendered BEFORE terraform apply (done by render-templates.sh)
data "kubectl_path_documents" "karpenter_manifests" {
  count   = local.karpenter_enabled ? 1 : 0
  pattern = "${path.module}/../../platform/karpenter/*.yaml"
}

resource "kubectl_manifest" "karpenter_resources" {
  count = local.karpenter_enabled ? length(data.kubectl_path_documents.karpenter_manifests[0].documents) : 0

  yaml_body = data.kubectl_path_documents.karpenter_manifests[0].documents[count.index]

  depends_on = [
    helm_release.karpenter
  ]

  wait = true
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
#
# CRITICAL: This node group MUST be created BEFORE EKS addons are installed
# Addons (especially CoreDNS) require nodes to run. The module.eks creates
# addons automatically, but we need nodes first. We'll create this node group
# immediately after the cluster is created, before addons are ready.
################################################################################

resource "aws_eks_node_group" "karpenter_bootstrap" {
  count = local.karpenter_enabled ? 1 : 0

  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-karpenter-bootstrap"
  node_role_arn   = aws_iam_role.karpenter_bootstrap_node[0].arn
  subnet_ids      = module.vpc.private_subnets

  # Use SPOT for cost savings - even bootstrap can use Spot
  # If Spot is interrupted, Karpenter will handle replacement
  capacity_type = "SPOT"

  # Use Graviton (ARM64) for cost savings - cheapest option
  # AL2023_ARM_64_STANDARD is the AMI type for Graviton instances
  ami_type = "AL2023_ARM_64_STANDARD"

  # Use Graviton instances (t4g) - cheapest option
  # t4g.medium has 4GB RAM (needed for Karpenter which requires 1Gi)
  # t4g.small (2GB) is insufficient for Karpenter pods
  instance_types = ["t4g.medium"]

  scaling_config {
    desired_size = 1  # Single instance is enough for bootstrap
    min_size     = 1
    max_size     = 2  # Allow scaling to 2 if needed, but start with 1
  }

  update_config {
    max_unavailable = 1
  }

  # Labels for identification and taint to prevent workload scheduling
  labels = {
    role                                = "karpenter-bootstrap"
    "karpenter.sh/discovery"            = module.eks.cluster_name
    "node-role.kubernetes.io/bootstrap" = "true"
  }

  # CRITICAL: Taint to prevent workload pods from scheduling on bootstrap node
  # Only Karpenter controller and critical system pods should run here
  taint {
    key    = "node-role.kubernetes.io/bootstrap"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-karpenter-bootstrap"
    }
  )

  # Ensure proper ordering - create node group immediately after cluster
  # This must happen BEFORE addons are installed (addons need nodes)
  # CRITICAL: Use cluster_id instead of full module.eks to avoid circular dependency
  depends_on = [
    module.eks.cluster_id,
    aws_iam_role_policy_attachment.karpenter_bootstrap_node_policy
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Time delay to ensure node group is fully ready before addons try to use it
# This prevents addons from failing due to missing nodes
# CRITICAL: This ensures nodes are ready before any post-cluster operations
resource "time_sleep" "wait_for_nodes" {
  count = local.karpenter_enabled ? 1 : 0

  depends_on = [aws_eks_node_group.karpenter_bootstrap]

  create_duration = "120s"  # Wait 120 seconds for nodes to be fully ready and join cluster
}
