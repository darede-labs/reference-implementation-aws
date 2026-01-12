################################################################################
# AWS Backup - Native backup solution for EBS volumes
################################################################################

# Backup Vault with encryption
resource "aws_backup_vault" "main" {
  name        = "${local.cluster_name}-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-backup-vault"
    }
  )
}

# KMS key for backup encryption
resource "aws_kms_key" "backup" {
  description             = "KMS key for AWS Backup encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-backup-kms"
    }
  )
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.cluster_name}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

# Backup plan for PostgreSQL volumes
resource "aws_backup_plan" "postgresql" {
  name = "${local.cluster_name}-postgresql-backup"

  # Daily backup at 3 AM UTC
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"
    start_window      = 60  # 1 hour window to start
    completion_window = 120 # 2 hours to complete

    lifecycle {
      delete_after = 30 # Retain for 30 days
    }

    recovery_point_tags = merge(
      local.tags,
      {
        BackupPlan = "daily"
        Component  = "postgresql"
      }
    )
  }

  # Weekly backup on Sunday at 2 AM UTC (longer retention)
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 ? * SUN *)"
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 90 # Retain for 90 days
    }

    recovery_point_tags = merge(
      local.tags,
      {
        BackupPlan = "weekly"
        Component  = "postgresql"
      }
    )
  }

  tags = local.tags
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${local.cluster_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Attach AWS managed backup policy
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup selection - PostgreSQL EBS volumes by tags
resource "aws_backup_selection" "postgresql_volumes" {
  name         = "${local.cluster_name}-postgresql-volumes"
  plan_id      = aws_backup_plan.postgresql.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "kubernetes.io/created-for/pvc/name"
    value = "data-backstage-postgresql-0"
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "kubernetes.io/cluster/${local.cluster_name}"
    value = "owned"
  }
}

################################################################################
# EKS Cluster Full Backup (new capability)
################################################################################
# AWS Backup now supports full EKS cluster backup including:
# - Cluster configuration and Kubernetes resources
# - Persistent volumes (EBS, EFS, S3)
# - Can restore to new or existing cluster

# Additional IAM permissions for EKS backup
resource "aws_iam_role_policy_attachment" "backup_eks" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForEKS"
}

# Backup plan for full EKS cluster
resource "aws_backup_plan" "eks_cluster" {
  name = "${local.cluster_name}-full-cluster-backup"

  # Weekly full cluster backup (Sunday 1 AM UTC)
  rule {
    rule_name         = "weekly-full-cluster"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 1 ? * SUN *)"
    start_window      = 120  # 2 hour window
    completion_window = 240  # 4 hours to complete

    lifecycle {
      delete_after = 90 # Retain for 90 days
    }

    recovery_point_tags = merge(
      local.tags,
      {
        BackupPlan = "weekly-full-cluster"
        Component  = "eks-cluster"
      }
    )
  }

  tags = local.tags
}

# Backup selection for full EKS cluster
resource "aws_backup_selection" "eks_cluster" {
  name         = "${local.cluster_name}-full-cluster"
  plan_id      = aws_backup_plan.eks_cluster.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    module.eks.cluster_arn
  ]
}

# Backup vault lock policy (optional - prevents deletion of backups)
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  min_retention_days  = 7
  max_retention_days  = 365
  changeable_for_days = 3
}

# Backup notifications (optional)
resource "aws_sns_topic" "backup_notifications" {
  name = "${local.cluster_name}-backup-notifications"

  tags = local.tags
}

resource "aws_backup_vault_notifications" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  sns_topic_arn       = aws_sns_topic.backup_notifications.arn
  backup_vault_events = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_FAILED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "RESTORE_JOB_FAILED"
  ]
}
