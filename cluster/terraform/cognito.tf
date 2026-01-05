################################################################################
# Amazon Cognito User Pool for IDP Platform Authentication
# Configuration loaded from config.yaml (identity_provider, cognito sections)
################################################################################

# Only create Cognito resources if identity_provider is "cognito"
locals {
  use_cognito = try(local.config_file.identity_provider, "cognito") == "cognito"

  # Cognito configuration from config.yaml
  cognito_config     = try(local.config_file.cognito, {})
  cognito_admin_email = try(local.cognito_config.admin_email, "admin@example.com")

  # Application hosts (dynamic from config.yaml)
  backstage_host = local.path_routing ? local.domain : "${try(local.subdomains.backstage, "backstage")}.${local.domain}"
  argocd_host    = local.path_routing ? local.domain : "${try(local.subdomains.argocd, "argocd")}.${local.domain}"

  # Cognito domain prefix (globally unique)
  cognito_domain_prefix = "${local.cluster_name}-idp"
}

################################################################################
# Cognito User Pool
################################################################################

resource "aws_cognito_user_pool" "main" {
  count = local.use_cognito ? 1 : 0

  name = "${local.cluster_name}-users"

  # Username configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Schema attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }

  # Email configuration (use Cognito default)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # MFA configuration
  mfa_configuration = "OFF"

  tags = local.tags
}

################################################################################
# Cognito User Pool Domain (for hosted UI)
################################################################################

resource "aws_cognito_user_pool_domain" "main" {
  count = local.use_cognito ? 1 : 0

  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main[0].id
}

################################################################################
# App Client for Backstage
################################################################################

resource "aws_cognito_user_pool_client" "backstage" {
  count = local.use_cognito ? 1 : 0

  name         = "backstage"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # OAuth settings
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # Callback URLs
  callback_urls = [
    "https://${local.backstage_host}/api/auth/oidc/handler/frame"
  ]
  logout_urls = [
    "https://${local.backstage_host}"
  ]

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Generate client secret
  generate_secret = true

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Read/write attributes
  read_attributes  = ["email", "name", "preferred_username"]
  write_attributes = ["email", "name", "preferred_username"]
}

################################################################################
# App Client for ArgoCD
################################################################################

resource "aws_cognito_user_pool_client" "argocd" {
  count = local.use_cognito ? 1 : 0

  name         = "argocd"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # OAuth settings
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # Callback URLs
  callback_urls = [
    "https://${local.argocd_host}/auth/callback"
  ]
  logout_urls = [
    "https://${local.argocd_host}"
  ]

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Generate client secret
  generate_secret = true

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Read/write attributes
  read_attributes  = ["email", "name", "preferred_username"]
  write_attributes = ["email", "name", "preferred_username"]
}
