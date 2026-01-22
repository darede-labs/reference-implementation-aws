################################################################################
# Input Validations
################################################################################
# This file contains all validation rules to prevent deployment failures
# caused by AWS resource naming constraints.
#
# AWS Resource Name Limits:
# - EKS Cluster: 100 characters
# - Load Balancer: 32 characters
# - IAM Role: 64 characters
# - Security Group: 255 characters
# - KMS Alias: 256 characters (including "alias/" prefix)
# - S3 Bucket: 63 characters
# - Cognito User Pool: 128 characters
# - Secrets Manager: 512 characters
################################################################################

################################################################################
# Cloud Economics Tag Validation (MANDATORY)
################################################################################
# All AWS resources MUST have the cloud_economics tag for cost tracking
# Format: "Darede-<JIRA_CODE>::<vertical>"
# Example: "Darede-RPCNE::netfound", "Darede-IDP::platform"
################################################################################

resource "null_resource" "validate_cloud_economics_tag" {
  triggers = {
    cloud_economics_tag = try(local.config_tags.cloud_economics, "")
  }

  lifecycle {
    precondition {
      condition     = can(local.config_tags.cloud_economics) && length(local.config_tags.cloud_economics) > 0
      error_message = "MANDATORY: 'cloud_economics' tag is missing in config.yaml. Add it with format: 'Darede-<JIRA_CODE>::<vertical>'. Example: 'Darede-IDP::platform'"
    }

    precondition {
      condition     = can(regex("^Darede-[A-Z0-9]+(::.*)?$", local.config_tags.cloud_economics))
      error_message = "INVALID FORMAT: cloud_economics tag '${try(local.config_tags.cloud_economics, "")}' must follow format: 'Darede-<JIRA_CODE>::<vertical>'. Example: 'Darede-RPCNE::devops'"
    }

    precondition {
      condition     = can(regex("::", local.config_tags.cloud_economics))
      error_message = "INCOMPLETE TAG: cloud_economics tag '${try(local.config_tags.cloud_economics, "")}' must include vertical. Format: 'Darede-<JIRA_CODE>::<vertical>'. Example: 'Darede-IDP::platform'"
    }
  }
}

################################################################################
# Cluster Name Validations
################################################################################

resource "null_resource" "validate_cluster_name" {
  lifecycle {
    precondition {
      condition     = length(local.cluster_name) <= 100
      error_message = "Cluster name '${local.cluster_name}' is ${length(local.cluster_name)} characters long. EKS cluster names must be 100 characters or less."
    }

    precondition {
      condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", local.cluster_name))
      error_message = "Cluster name '${local.cluster_name}' is invalid. Must start with a letter and contain only alphanumeric characters and hyphens."
    }

    precondition {
      condition     = !can(regex("--", local.cluster_name))
      error_message = "Cluster name '${local.cluster_name}' is invalid. Cannot contain consecutive hyphens."
    }
  }
}

################################################################################
# Load Balancer Name Validations
################################################################################

resource "null_resource" "validate_nlb_name" {
  count = local.enable_nlb ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-nlb") <= 32
      error_message = "NLB name '${local.cluster_name}-nlb' is ${length("${local.cluster_name}-nlb")} characters long. Load balancer names must be 32 characters or less. Shorten your cluster_name in config.yaml."
    }
  }
}

resource "null_resource" "validate_target_group_names" {
  count = local.enable_nlb ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-http") <= 32
      error_message = "Target group name '${local.cluster_name}-http' is ${length("${local.cluster_name}-http")} characters long. Target group names must be 32 characters or less. Shorten your cluster_name in config.yaml."
    }

    precondition {
      condition     = length("${local.cluster_name}-https") <= 32
      error_message = "Target group name '${local.cluster_name}-https' is ${length("${local.cluster_name}-https")} characters long. Target group names must be 32 characters or less. Shorten your cluster_name in config.yaml."
    }
  }
}

################################################################################
# IAM Role Name Validations
################################################################################

resource "null_resource" "validate_iam_role_names" {
  # Trigger on cluster name changes
  triggers = {
    cluster_name = local.cluster_name
  }

  lifecycle {
    # Backstage IRSA role (constant, but needs trigger)
    precondition {
      condition     = local.cluster_name != "" && length("backstage-terraform-irsa") <= 64
      error_message = "IAM role name 'backstage-terraform-irsa' is too long. IAM role names must be 64 characters or less."
    }

    # Karpenter bootstrap node role
    precondition {
      condition     = !local.karpenter_enabled || length("${local.cluster_name}-karpenter-bootstrap-node-role") <= 64
      error_message = "IAM role name '${local.cluster_name}-karpenter-bootstrap-node-role' is ${length("${local.cluster_name}-karpenter-bootstrap-node-role")} characters long. IAM role names must be 64 characters or less. Shorten your cluster_name in config.yaml."
    }

    # Crossplane permissions boundary (constant, but needs trigger)
    precondition {
      condition     = local.cluster_name != "" && length("crossplane-permissions-boundary") <= 128
      error_message = "IAM policy name 'crossplane-permissions-boundary' is too long. IAM policy names must be 128 characters or less."
    }

    # External secrets policy (constant, but needs trigger)
    precondition {
      condition     = !local.use_irsa || (local.cluster_name != "" && length("external-secrets-policy") <= 128)
      error_message = "IAM policy name 'external-secrets-policy' is too long. IAM policy names must be 128 characters or less."
    }

    # Backstage Terraform policy (constant, but needs trigger)
    precondition {
      condition     = local.cluster_name != "" && length("backstage-terraform-policy") <= 128
      error_message = "IAM policy name 'backstage-terraform-policy' is too long. IAM policy names must be 128 characters or less."
    }
  }
}

################################################################################
# VPC Name Validation
################################################################################

resource "null_resource" "validate_vpc_name" {
  count = local.create_vpc ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-vpc") <= 255
      error_message = "VPC name '${local.cluster_name}-vpc' is too long. VPC names (tags) should be under 255 characters."
    }
  }
}

################################################################################
# Security Group Name Validations
################################################################################

resource "null_resource" "validate_security_group_names" {
  count = local.enable_nlb ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-ingress-nginx-") <= 255
      error_message = "Security group name prefix '${local.cluster_name}-ingress-nginx-' is too long. Security group names must be 255 characters or less."
    }
  }
}

################################################################################
# KMS Alias Validation
################################################################################

resource "null_resource" "validate_kms_alias" {
  lifecycle {
    precondition {
      condition     = length("alias/${local.cluster_name}-eks") <= 256
      error_message = "KMS alias 'alias/${local.cluster_name}-eks' is ${length("alias/${local.cluster_name}-eks")} characters long. KMS aliases must be 256 characters or less (including 'alias/' prefix)."
    }
  }
}

################################################################################
# Cognito Resource Name Validations
################################################################################

resource "null_resource" "validate_cognito_names" {
  count = local.use_cognito ? 1 : 0

  lifecycle {
    # User Pool name
    precondition {
      condition     = length("${local.cluster_name}-user-pool") <= 128
      error_message = "Cognito User Pool name '${local.cluster_name}-user-pool' is ${length("${local.cluster_name}-user-pool")} characters long. User Pool names must be 128 characters or less. Shorten your cluster_name in config.yaml."
    }

    # User Pool domain
    precondition {
      condition     = length("${local.cluster_name}-idp") <= 63
      error_message = "Cognito domain '${local.cluster_name}-idp' is ${length("${local.cluster_name}-idp")} characters long. Cognito domains must be 63 characters or less. Shorten your cluster_name in config.yaml."
    }

    # App client names
    precondition {
      condition     = length("${local.cluster_name}-backstage") <= 128
      error_message = "Cognito app client name '${local.cluster_name}-backstage' is too long. App client names must be 128 characters or less."
    }

    precondition {
      condition     = length("${local.cluster_name}-argocd") <= 128
      error_message = "Cognito app client name '${local.cluster_name}-argocd' is too long. App client names must be 128 characters or less."
    }
  }
}

################################################################################
# Secrets Manager Name Validations
################################################################################

resource "null_resource" "validate_secrets_manager_names" {
  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-github-app-credentials") <= 512
      error_message = "Secrets Manager secret name '${local.cluster_name}-github-app-credentials' is ${length("${local.cluster_name}-github-app-credentials")} characters long. Secret names must be 512 characters or less."
    }

    precondition {
      condition     = length("${local.cluster_name}-cognito-credentials") <= 512
      error_message = "Secrets Manager secret name '${local.cluster_name}-cognito-credentials' is ${length("${local.cluster_name}-cognito-credentials")} characters long. Secret names must be 512 characters or less."
    }
  }
}

################################################################################
# Backstage DB Secret Validations
################################################################################
resource "null_resource" "validate_backstage_db_secret" {
  lifecycle {
    precondition {
      condition     = length(trimspace(local.backstage_db_host)) > 0
      error_message = "Backstage DB host is empty. Set secrets.backstage.postgres_host in config.yaml."
    }

    precondition {
      condition     = length(trimspace(local.backstage_db_pass)) > 0
      error_message = "Backstage DB password is empty. Set secrets.backstage.postgres_password via ENV or config.yaml."
    }

    precondition {
      condition     = !can(regex("\\$\\{", local.backstage_db_pass))
      error_message = "Backstage DB password looks like a placeholder. Provide a real value via ENV or config.yaml."
    }
  }
}

################################################################################
# S3 Bucket Name Validation
################################################################################

resource "null_resource" "validate_s3_bucket_name" {
  lifecycle {
    precondition {
      condition     = length(local.terraform_state_bucket) <= 63
      error_message = "S3 bucket name '${local.terraform_state_bucket}' is ${length(local.terraform_state_bucket)} characters long. S3 bucket names must be 63 characters or less. Update terraform_backend.bucket in config.yaml."
    }

    precondition {
      condition     = length(local.terraform_state_bucket) >= 3
      error_message = "S3 bucket name '${local.terraform_state_bucket}' is too short. S3 bucket names must be at least 3 characters long."
    }

    precondition {
      condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", local.terraform_state_bucket))
      error_message = "S3 bucket name '${local.terraform_state_bucket}' is invalid. Must contain only lowercase letters, numbers, and hyphens. Must start and end with a letter or number."
    }

    precondition {
      condition     = !can(regex("\\.\\.|\\.\\-|\\-\\.", local.terraform_state_bucket))
      error_message = "S3 bucket name '${local.terraform_state_bucket}' is invalid. Cannot contain consecutive periods, or periods adjacent to hyphens."
    }
  }
}

################################################################################
# EKS Node Group Name Validations
################################################################################

resource "null_resource" "validate_node_group_names" {
  count = !local.auto_mode && !local.karpenter_enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-nodes") <= 63
      error_message = "Node group name '${local.cluster_name}-nodes' is ${length("${local.cluster_name}-nodes")} characters long. Node group names must be 63 characters or less. Shorten your cluster_name in config.yaml."
    }
  }
}

resource "null_resource" "validate_karpenter_node_group_name" {
  count = local.karpenter_enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name}-karpenter-bootstrap") <= 63
      error_message = "Node group name '${local.cluster_name}-karpenter-bootstrap' is ${length("${local.cluster_name}-karpenter-bootstrap")} characters long. Node group names must be 63 characters or less. Shorten your cluster_name in config.yaml."
    }
  }
}

################################################################################
# Domain Name Validations
################################################################################

resource "null_resource" "validate_domain" {
  lifecycle {
    precondition {
      condition     = length(local.domain) <= 255
      error_message = "Domain name '${local.domain}' is too long. Domain names must be 255 characters or less."
    }

    precondition {
      condition     = can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", local.domain))
      error_message = "Domain name '${local.domain}' is invalid. Must be a valid domain name (e.g., example.com)."
    }
  }
}

################################################################################
# Validation Summary Output
################################################################################

output "validation_summary" {
  description = "Summary of all naming validations"
  value = {
    cluster_name_length     = length(local.cluster_name)
    cluster_name_limit      = 100
    nlb_name_length         = local.enable_nlb ? length("${local.cluster_name}-nlb") : null
    nlb_name_limit          = 32
    terraform_bucket_length = length(local.terraform_state_bucket)
    terraform_bucket_limit  = 63
    all_validations_passed  = true
    recommendation          = length(local.cluster_name) > 20 ? "Consider using a shorter cluster_name to avoid hitting name length limits for derived resources." : "Cluster name length is optimal."
  }
}
