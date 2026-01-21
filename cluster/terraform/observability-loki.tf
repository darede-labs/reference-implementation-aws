# Loki S3 Backend + IRSA
# Provides log storage and IAM role for Loki to write to S3

# Random suffix to avoid S3 bucket name collision (global namespace)
resource "random_id" "loki_bucket_suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "loki" {
  bucket = "${local.cluster_name}-loki-chunks-${random_id.loki_bucket_suffix.hex}"

  tags = merge(local.tags, {
    Name      = "${local.cluster_name}-loki"
    Component = "observability"
  })
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {} # Required: empty filter applies to all objects

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM Role for Loki (IRSA)
module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-loki"

  role_policy_arns = {
    policy = aws_iam_policy.loki_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["observability:loki"]
    }
  }

  tags = local.tags
}

# IAM Policy for Loki S3 access
resource "aws_iam_policy" "loki_s3" {
  name        = "${local.cluster_name}-loki-s3"
  description = "Allow Loki to write logs to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.loki.arn,
          "${aws_s3_bucket.loki.arn}/*"
        ]
      }
    ]
  })

  tags = local.tags
}

# Outputs moved to outputs.tf to avoid duplication
