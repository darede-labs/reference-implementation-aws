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

output "nlb_dns_name" {
  description = "DNS name of the NLB for ingress-nginx"
  value       = length(aws_lb.ingress_nginx) > 0 ? aws_lb.ingress_nginx[0].dns_name : null
}

output "nlb_arn" {
  description = "ARN of the NLB for ingress-nginx"
  value       = length(aws_lb.ingress_nginx) > 0 ? aws_lb.ingress_nginx[0].arn : null
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB for Route53"
  value       = length(aws_lb.ingress_nginx) > 0 ? aws_lb.ingress_nginx[0].zone_id : null
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
# Karpenter Outputs
################################################################################

output "karpenter_enabled" {
  description = "Whether Karpenter is enabled for node provisioning"
  value       = local.karpenter_enabled
}

output "karpenter_irsa_arn" {
  description = "ARN of Karpenter IRSA role"
  value       = local.karpenter_enabled ? module.karpenter[0].iam_role_arn : null
}

output "karpenter_queue_name" {
  description = "Name of Karpenter SQS interruption queue"
  value       = local.karpenter_enabled ? module.karpenter[0].queue_name : null
}

output "karpenter_version" {
  description = "Karpenter Helm chart version (from config.yaml)"
  value       = local.karpenter_version
}

################################################################################
# Keycloak RDS Outputs
################################################################################

output "keycloak_enabled" {
  description = "Whether Keycloak is enabled as identity provider"
  value       = local.keycloak_enabled
}

output "keycloak_db_endpoint" {
  description = "Keycloak RDS endpoint"
  value       = local.keycloak_enabled ? aws_db_instance.keycloak[0].endpoint : null
}

output "keycloak_db_address" {
  description = "Keycloak RDS address (hostname)"
  value       = local.keycloak_enabled ? aws_db_instance.keycloak[0].address : null
}

output "keycloak_db_port" {
  description = "Keycloak RDS port"
  value       = local.keycloak_enabled ? aws_db_instance.keycloak[0].port : null
}

output "keycloak_db_name" {
  description = "Keycloak database name"
  value       = local.keycloak_enabled ? local.keycloak_db_name : null
}

output "keycloak_db_secret_arn" {
  description = "ARN of Keycloak database credentials in Secrets Manager"
  value       = local.keycloak_enabled ? aws_secretsmanager_secret.keycloak_db[0].arn : null
}

output "keycloak_jdbc_url" {
  description = "JDBC URL for Keycloak database connection"
  value       = local.keycloak_enabled ? "jdbc:postgresql://${aws_db_instance.keycloak[0].address}:${aws_db_instance.keycloak[0].port}/${local.keycloak_db_name}" : null
  sensitive   = false
}
