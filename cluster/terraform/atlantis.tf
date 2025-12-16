################################################################################
# Atlantis - IAM Role for Terraform execution
################################################################################

# IAM Policy for Atlantis - allows managing AWS resources via Terraform templates
# This policy covers all resources that can be created via Backstage templates:
# - S3 buckets
# - EC2 instances
# - Security Groups
# - VPCs
# - EKS clusters
# - Secrets Manager
resource "aws_iam_policy" "atlantis" {
  name        = "${local.cluster_name}-atlantis"
  description = "Policy for Atlantis to manage AWS resources via Terraform"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Backend for Terraform state
      {
        Sid    = "S3Backend"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::poc-idp-tfstate",
          "arn:aws:s3:::poc-idp-tfstate/*"
        ]
      },
      # S3 bucket management (template: terraform-s3)
      {
        Sid    = "S3Management"
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      # EC2 management (template: terraform-ec2)
      {
        Sid    = "EC2Management"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      # Secrets Manager (template: terraform-secrets)
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:DeleteResourcePolicy"
        ]
        Resource = "*"
      },
      # EKS management (template: terraform-eks)
      {
        Sid    = "EKSManagement"
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      # IAM for instance profiles and EKS node roles
      {
        Sid    = "IAMManagement"
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateServiceLinkedRole",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = "*"
      },
      # KMS for encryption
      {
        Sid    = "KMSManagement"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:ScheduleKeyDeletion",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:UpdateAlias"
        ]
        Resource = "*"
      },
      # CloudWatch Logs for EKS
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource"
        ]
        Resource = "*"
      },
      # SSM for EC2 parameter store
      {
        Sid    = "SSMManagement"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# IAM Role for Atlantis - uses EKS Pod Identity
resource "aws_iam_role" "atlantis" {
  name = "${local.cluster_name}-atlantis"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "atlantis" {
  role       = aws_iam_role.atlantis.name
  policy_arn = aws_iam_policy.atlantis.arn
}

# Pod Identity Association for Atlantis
resource "aws_eks_pod_identity_association" "atlantis" {
  cluster_name    = module.eks.cluster_name
  namespace       = "atlantis"
  service_account = "atlantis"
  role_arn        = aws_iam_role.atlantis.arn

  depends_on = [module.eks]
}
