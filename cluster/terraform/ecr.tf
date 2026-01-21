# =============================================================================
# ECR Repositories for Application Images
# =============================================================================
#
# This module creates ECR repositories for application images.
# Repositories are created on-demand by the CI/CD pipeline if they don't exist.
#
# Best Practices:
# - Image scanning on push enabled
# - Lifecycle policies to manage image retention
# - Encryption at rest with KMS (optional, can be changed to AES256)
# - Immutable tags for production images

# ECR Repository for platform applications
# This is a sample repository that can be used by the Backstage scaffolder
# In production, repositories are created dynamically by the CI/CD pipeline
resource "aws_ecr_repository" "platform_apps" {
  for_each = toset(try(local.config_file.ecr.repositories, []))

  name                 = each.value
  image_tag_mutability = "MUTABLE" # Use IMMUTABLE for production

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256" # Use KMS for production
  }

  tags = merge(local.tags, {
    Name      = each.value
    Component = "ecr"
    ManagedBy = "terraform"
  })
}

# Lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "platform_apps" {
  for_each = aws_ecr_repository.platform_apps

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 staging images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["staging-", "dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM policy for EKS nodes to pull images from ECR
# This is attached to the EKS node role
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid    = "ECRPullAccess"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_pull" {
  name        = "${local.cluster_name}-ecr-pull"
  description = "Allow EKS nodes to pull images from ECR"
  policy      = data.aws_iam_policy_document.ecr_pull.json

  tags = merge(local.tags, {
    Name      = "${local.cluster_name}-ecr-pull"
    Component = "ecr"
  })
}

# Attach ECR pull policy to EKS node role
# For Karpenter: attach to Karpenter node role
# For managed node groups: attach to managed node group role
resource "aws_iam_role_policy_attachment" "ecr_pull_karpenter" {
  count = local.karpenter_enabled ? 1 : 0

  role       = module.karpenter[0].node_iam_role_name
  policy_arn = aws_iam_policy.ecr_pull.arn
}

resource "aws_iam_role_policy_attachment" "ecr_pull_managed_ng" {
  count = local.karpenter_enabled ? 0 : 1

  role       = module.eks.eks_managed_node_groups["default"].iam_role_name
  policy_arn = aws_iam_policy.ecr_pull.arn
}

# =============================================================================
# GitHub Actions OIDC Provider for ECR Push
# =============================================================================
#
# This allows GitHub Actions to authenticate to AWS without static credentials
# and push images to ECR repositories.

# GitHub OIDC provider (if not already exists)
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name      = "${local.cluster_name}-github-oidc"
    Component = "iam"
  })
}

# IAM role for GitHub Actions to push to ECR
data "aws_iam_policy_document" "github_ecr_push_assume" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Allow any repo in the GitHub org to assume this role
      values = [
        "repo:${try(local.config_file.github.org, "*")}/*:*"
      ]
    }
  }
}

data "aws_iam_policy_document" "github_ecr_push" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  statement {
    sid    = "ECRAuthToken"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]

    # Allow push to any repository in the account
    # In production, you may want to restrict this to specific repositories
    resources = ["arn:aws:ecr:${local.region}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  statement {
    sid    = "ECRCreateRepository"
    effect = "Allow"

    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "github_ecr_push" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  name               = "${local.cluster_name}-github-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_ecr_push_assume[0].json

  tags = merge(local.tags, {
    Name      = "${local.cluster_name}-github-ecr-push"
    Component = "iam"
  })
}

resource "aws_iam_role_policy" "github_ecr_push" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  name   = "ecr-push"
  role   = aws_iam_role.github_ecr_push[0].id
  policy = data.aws_iam_policy_document.github_ecr_push[0].json
}
