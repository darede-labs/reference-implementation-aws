# Read configuration from config.yaml
locals {
  # Load config.yaml from repository root
  config_file = yamldecode(file("${path.module}/../../config.yaml"))

  # Cluster configuration
  cluster_name = local.config_file.cluster_name
  region       = local.config_file.region
  auto_mode    = tobool(local.config_file.auto_mode)

  # IAM authentication method: "irsa" or "pod-identity"
  iam_auth_method  = try(local.config_file.iam_auth_method, "irsa")
  use_irsa         = local.iam_auth_method == "irsa"
  use_pod_identity = local.iam_auth_method == "pod-identity"

  # Note: use_cognito is defined in cognito.tf

  # VPC configuration
  vpc_config = local.config_file.vpc
  create_vpc = local.vpc_config.mode == "create"
  vpc_cidr   = try(local.vpc_config.cidr, "10.0.0.0/16")
  azs_count  = try(local.vpc_config.availability_zones, 3)
  azs        = slice(data.aws_availability_zones.available.names, 0, local.azs_count)

  # NAT Gateway mode: single or one_per_az
  nat_gateway_single = try(local.vpc_config.nat_gateway_mode, "single") == "single"

  # Node groups configuration
  node_config    = try(local.config_file.node_groups, {})
  capacity_type  = try(local.node_config.capacity_type, "SPOT")
  instance_types = try(local.node_config.instance_types, ["t3.medium", "t3a.medium", "t2.medium"])
  node_min_size  = try(local.node_config.scaling.min_size, 1)
  node_max_size  = try(local.node_config.scaling.max_size, 3)
  node_desired   = try(local.node_config.scaling.desired_size, 1)
  node_disk_size = try(local.node_config.disk_size, 50)
  node_labels    = try(local.node_config.labels, {})

  # Domain configuration
  domain       = local.config_file.domain
  path_routing = tobool(try(local.config_file.path_routing, "false"))

  # Terraform state bucket for Backstage scaffolder
  terraform_state_bucket = try(local.config_file.terraform_backend.bucket, "poc-idp-tfstate")

  # Karpenter configuration
  karpenter_enabled = tobool(try(local.config_file.use_karpenter, "false"))
  karpenter_config  = try(local.config_file.karpenter, {})
  karpenter_version = try(local.karpenter_config.version, "1.8.5")

  # Subdomains
  subdomains = try(local.config_file.subdomains, {})

  # Network Load Balancer for ingress-nginx
  enable_nlb          = tobool(try(local.config_file.enable_nlb, true))
  acm_certificate_arn = try(local.config_file.acm_certificate_arn, "")

  # Tags from config
  config_tags = local.config_file.tags

  # Merge with additional tags
  # cloud_economics tag is MANDATORY for all resources (Cloud Economics policy)
  # Validation is performed in validations.tf
  tags = merge(
    local.config_tags,
    {
      ManagedBy    = "terraform"
      ConfigSource = "config.yaml"
    }
  )

  # IAM policies (existing logic)
  crossplane_boundary_policy = templatefile("${path.module}/../iam-policies/crossplane-permissions-boundry.json", {
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
  })

  external_secret_policy = templatefile("${path.module}/../iam-policies/external-secrets.json", {
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
  })
}
