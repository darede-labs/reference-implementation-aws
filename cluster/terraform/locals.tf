# Read configuration from config.yaml
locals {
  # Load config.yaml from repository root
  config_file = yamldecode(file("${path.module}/../../config.yaml"))

  # Cluster configuration with validation
  cluster_name = local.config_file.cluster_name
  region       = local.config_file.region
  auto_mode    = tobool(local.config_file.auto_mode)

  # Validate cluster_name early
  _validate_cluster_name = (
    length(local.cluster_name) > 0 &&
    length(local.cluster_name) <= 100
  ) ? true : tobool("VALIDATION ERROR: cluster_name must be between 1 and 100 characters. Current: ${length(local.cluster_name)} characters.")

  # IAM authentication method: "irsa" or "pod-identity"
  iam_auth_method  = try(local.config_file.iam_auth_method, "irsa")
  use_irsa         = local.iam_auth_method == "irsa"
  use_pod_identity = local.iam_auth_method == "pod-identity"

  # Note: use_cognito is defined in cognito.tf

  # Validate Cognito names early (only if Cognito is enabled)
  # Note: This validation runs after cognito.tf locals are evaluated
  _validate_cognito_names = (!can(local.use_cognito) || !local.use_cognito || (
    length("${local.cluster_name}-user-pool") <= 128 &&
    length("${local.cluster_name}-idp") <= 63 &&
    length("${local.cluster_name}-backstage") <= 128 &&
    length("${local.cluster_name}-argocd") <= 128
  )) ? true : tobool("VALIDATION ERROR: Cognito resource names too long. User pool: 128, domain: 63, clients: 128. Shorten cluster_name in config.yaml.")

  # VPC configuration
  vpc_config = local.config_file.vpc
  create_vpc = local.vpc_config.mode == "create"
  vpc_cidr   = try(local.vpc_config.cidr, "10.0.0.0/16")
  azs_count  = try(local.vpc_config.availability_zones, 3)
  azs        = slice(data.aws_availability_zones.available.names, 0, local.azs_count)

  # Existing VPC config (only used if mode is "existing")
  existing_vpc_id          = try(local.vpc_config.vpc_id, null)
  existing_private_subnets = try(local.vpc_config.private_subnet_ids, [])
  existing_public_subnets  = try(local.vpc_config.public_subnet_ids, [])

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

  # Validate node scaling configuration
  _validate_node_scaling = (
    local.node_min_size >= 0 &&
    local.node_max_size >= local.node_min_size &&
    local.node_desired >= local.node_min_size &&
    local.node_desired <= local.node_max_size
  ) ? true : tobool("VALIDATION ERROR: Invalid node scaling config. Must satisfy: 0 <= min_size <= desired_size <= max_size. Current: min=${local.node_min_size}, desired=${local.node_desired}, max=${local.node_max_size}")

  # Validate node disk size
  _validate_node_disk = (
    local.node_disk_size >= 20 && local.node_disk_size <= 16384
  ) ? true : tobool("VALIDATION ERROR: node_groups.disk_size must be between 20 and 16384 GB. Current: ${local.node_disk_size}")

  # Domain configuration
  domain                 = local.config_file.domain
  route53_hosted_zone_id = local.config_file.route53_hosted_zone_id
  path_routing           = tobool(try(local.config_file.path_routing, "false"))

  # Terraform state bucket for Backstage scaffolder
  terraform_state_bucket = try(local.config_file.terraform_backend.bucket, "poc-idp-tfstate")

  # Validate S3 bucket name early
  _validate_bucket_name = (
    length(local.terraform_state_bucket) >= 3 &&
    length(local.terraform_state_bucket) <= 63 &&
    can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", local.terraform_state_bucket))
  ) ? true : tobool("VALIDATION ERROR: terraform_backend.bucket must be 3-63 characters, lowercase, start/end with letter or number. Current: '${local.terraform_state_bucket}'")

  # Karpenter configuration
  karpenter_enabled = tobool(try(local.config_file.use_karpenter, "false"))

  # Subdomains
  subdomains = try(local.config_file.subdomains, {})

  # Network Load Balancer for ingress-nginx
  enable_nlb          = tobool(try(local.config_file.enable_nlb, true))
  acm_certificate_arn = try(local.config_file.acm_certificate_arn, "")

  # Validate NLB name early (only if NLB is enabled)
  _validate_nlb_name = !local.enable_nlb ? true : (
    length("${local.cluster_name}-nlb") <= 32
  ) ? true : tobool("VALIDATION ERROR: NLB name '${local.cluster_name}-nlb' is ${length("${local.cluster_name}-nlb")} characters (limit: 32). Shorten cluster_name in config.yaml.")

  # Validate target group names (only if NLB is enabled)
  _validate_tg_names = !local.enable_nlb ? true : (
    length("${local.cluster_name}-http") <= 32 &&
    length("${local.cluster_name}-https") <= 32
  ) ? true : tobool("VALIDATION ERROR: Target group names too long (limit: 32 chars). Shorten cluster_name in config.yaml.")

  # Tags from config
  config_tags = local.config_file.tags

  # Merge with additional tags
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
