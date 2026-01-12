output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = local.region
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enabled"
  value       = module.eks.oidc_provider_arn
}

output "auto_mode_enabled" {
  description = "Whether EKS Auto Mode is enabled"
  value       = local.auto_mode
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "iam_auth_method" {
  description = "IAM authentication method being used (irsa or pod-identity)"
  value       = local.iam_auth_method
}

output "external_secrets_role_arn" {
  description = "ARN of the IAM role for External Secrets"
  value       = local.use_irsa ? module.external_secrets_irsa[0].iam_role_arn : "Using Pod Identity"
}

################################################################################
# Cognito Outputs
################################################################################

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for authentication"
  value       = local.use_cognito ? aws_cognito_user_pool.main[0].id : null
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = local.use_cognito ? aws_cognito_user_pool.main[0].arn : null
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool domain for OIDC endpoints"
  value       = local.use_cognito ? aws_cognito_user_pool_domain.main[0].domain : null
}

output "cognito_backstage_client_id" {
  description = "Cognito App Client ID for Backstage"
  value       = local.use_cognito ? aws_cognito_user_pool_client.backstage[0].id : null
}

output "cognito_backstage_client_secret" {
  description = "Cognito App Client Secret for Backstage (sensitive)"
  value       = local.use_cognito ? aws_cognito_user_pool_client.backstage[0].client_secret : null
  sensitive   = true
}

output "cognito_argocd_client_id" {
  description = "Cognito App Client ID for ArgoCD"
  value       = local.use_cognito ? aws_cognito_user_pool_client.argocd[0].id : null
}

output "cognito_argocd_client_secret" {
  description = "Cognito App Client Secret for ArgoCD (sensitive)"
  value       = local.use_cognito ? aws_cognito_user_pool_client.argocd[0].client_secret : null
  sensitive   = true
}

output "cognito_issuer_url" {
  description = "OIDC Issuer URL for Cognito"
  value       = local.use_cognito ? "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main[0].id}" : null
}

################################################################################
# Secrets Manager Outputs
################################################################################

output "github_app_secret_arn" {
  description = "ARN of GitHub App credentials secret in Secrets Manager"
  value       = aws_secretsmanager_secret.github_app.arn
}

output "github_app_secret_name" {
  description = "Name of GitHub App credentials secret"
  value       = aws_secretsmanager_secret.github_app.name
}

################################################################################
# AWS Backup Outputs
################################################################################

output "backup_vault_name" {
  description = "Name of AWS Backup vault"
  value       = aws_backup_vault.main.name
}

output "backup_vault_arn" {
  description = "ARN of AWS Backup vault"
  value       = aws_backup_vault.main.arn
}

output "backup_plan_id" {
  description = "ID of PostgreSQL backup plan"
  value       = aws_backup_plan.postgresql.id
}
