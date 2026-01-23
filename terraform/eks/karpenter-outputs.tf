output "karpenter_role_arn" {
  description = "Karpenter IAM role ARN"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_queue_name" {
  description = "Karpenter SQS queue name for spot interruption handling"
  value       = module.karpenter.queue_name
}

output "karpenter_installed" {
  description = "Karpenter installation status"
  value       = "Karpenter ${helm_release.karpenter.version} installed in namespace ${local.karpenter_namespace}"
}
