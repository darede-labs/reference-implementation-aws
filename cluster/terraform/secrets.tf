# AWS Secrets Manager - Configuration Secret for External Secrets
# This secret is used by Keycloak and other apps via External Secrets Operator

resource "aws_secretsmanager_secret" "config" {
  name        = "cnoe-ref-impl/config"
  description = "CNOE Reference Implementation configuration for External Secrets"

   recovery_window_in_days = 0

  tags = merge(
    local.tags,
    {
      Name = "cnoe-ref-impl-config"
      DeployedAt = timestamp()
    }
  )
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id = aws_secretsmanager_secret.config.id
  secret_string = jsonencode({
    domain       = local.domain
    path_routing = local.path_routing
  })
}

################################################################################
# GitHub App Credentials Secret
################################################################################
# IMPORTANT: This secret must be populated MANUALLY after creation
# Terraform creates the secret placeholder but does NOT store credentials
#
# To populate the secret after cluster creation:
#   aws secretsmanager put-secret-value \
#     --secret-id github-app-credentials \
#     --secret-string file://github-app-creds.json \
#     --profile darede
#
# Expected JSON format:
# {
#   "appId": "2440565",
#   "clientId": "Iv23...",
#   "clientSecret": "891cd...",
#   "webhookSecret": "452de...",
#   "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n..."
# }
################################################################################

resource "aws_secretsmanager_secret" "github_app" {
  name        = "${local.cluster_name}-github-app-credentials"
  description = "GitHub App credentials for Backstage integration"

   recovery_window_in_days = 0

  tags = merge(
    local.tags,
    {
      Name        = "github-app-credentials"
      Application = "backstage"
      DeployedAt  = timestamp()
    }
  )
}

# Placeholder version - real credentials must be set manually for security
resource "aws_secretsmanager_secret_version" "github_app" {
  secret_id = aws_secretsmanager_secret.github_app.id
  secret_string = jsonencode({
    appId         = "PLACEHOLDER_APP_ID"
    clientId      = "PLACEHOLDER_CLIENT_ID"
    clientSecret  = "PLACEHOLDER_CLIENT_SECRET"
    webhookSecret = "PLACEHOLDER_WEBHOOK_SECRET"
    privateKey    = "PLACEHOLDER_PRIVATE_KEY"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
