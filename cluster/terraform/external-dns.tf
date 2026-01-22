################################################################################
# External DNS - IRSA for Route53 Management
################################################################################

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                  = "${local.cluster_name}-external-dns"
  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [
    "arn:aws:route53:::hostedzone/${local.route53_hosted_zone_id}"
  ]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

  tags = local.tags
}
