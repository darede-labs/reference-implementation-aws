# AWS Secrets Manager - Configuration Secret for External Secrets
# This secret is used by Keycloak and other apps via External Secrets Operator

resource "aws_secretsmanager_secret" "config" {
  name        = "cnoe-ref-impl/config"
  description = "CNOE Reference Implementation configuration for External Secrets"

  tags = merge(
    local.tags,
    {
      Name = "cnoe-ref-impl-config"
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
