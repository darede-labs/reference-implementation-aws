################################################################################
# Crossplane - IRSA for AWS Provider
################################################################################
# IAM Role for Service Accounts (IRSA) for Crossplane to manage AWS resources
# Following least privilege principle - start with S3 and expand as needed
################################################################################

# IAM Policy Document for Crossplane
data "aws_iam_policy_document" "crossplane" {
  # S3 Management (for Phase 3 validation)
  statement {
    sid    = "S3Management"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:HeadBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:ListBucket",
      "s3:PutBucketPolicy",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketTagging",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketAcl",
      "s3:PutBucketAcl",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:GetBucketWebsite",
      "s3:PutBucketWebsite",
      "s3:GetBucketLogging",
      "s3:PutBucketLogging",
      "s3:GetBucketNotification",
      "s3:PutBucketNotification",
      "s3:GetBucketObjectLockConfiguration",
      "s3:PutBucketObjectLockConfiguration"
    ]
    resources = [
      "arn:aws:s3:::crossplane-*",
      "arn:aws:s3:::${local.cluster_name}-*"
    ]
  }

  # S3 List (for discovery)
  statement {
    sid    = "S3List"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets"
    ]
    resources = ["*"]
  }

  # EC2 Management (for future Phase 5)
  statement {
    sid    = "EC2Management"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EC2InstanceManagement"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:RebootInstances"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # RDS Management (for future expansion)
  statement {
    sid    = "RDSManagement"
    effect = "Allow"
    actions = [
      "rds:Describe*",
      "rds:ListTagsForResource",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RDSInstanceManagement"
    effect = "Allow"
    actions = [
      "rds:CreateDBInstance",
      "rds:DeleteDBInstance",
      "rds:ModifyDBInstance",
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBSubnetGroup"
    ]
    resources = [
      "arn:aws:rds:${local.region}:${data.aws_caller_identity.current.account_id}:db:crossplane-*",
      "arn:aws:rds:${local.region}:${data.aws_caller_identity.current.account_id}:subgrp:crossplane-*"
    ]
  }

  # IAM Read (for resource discovery)
  statement {
    sid    = "IAMRead"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies"
    ]
    resources = ["*"]
  }

  # Tags (for cost tracking and organization)
  statement {
    sid    = "TagManagement"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
      "tag:UntagResources"
    ]
    resources = ["*"]
  }
}

# IAM Policy for Crossplane
resource "aws_iam_policy" "crossplane" {
  name        = "${local.cluster_name}-crossplane"
  description = "Policy for Crossplane to manage AWS resources via IRSA"
  policy      = data.aws_iam_policy_document.crossplane.json

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-crossplane"
      Component = "crossplane"
    }
  )
}

# IRSA Module for Crossplane
module "crossplane_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-crossplane"

  role_policy_arns = {
    crossplane = aws_iam_policy.crossplane.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["crossplane-system:crossplane"]
    }
  }

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-crossplane"
      Component = "crossplane"
    }
  )
}
