################################################################################
# RDS PostgreSQL for Keycloak - Cost Optimized
################################################################################
# Ultra-low cost RDS configuration for Keycloak identity provider
# Estimated cost: $12-15/month (db.t4g.micro + 20GB gp3)
#
# Cost breakdown:
# - db.t4g.micro: ~$0.016/hour × 730h = ~$12/month
# - Storage 20GB gp3: ~$0.10/GB = ~$2/month
# - Backup: $0 (1-day retention, minimal overhead)
# Total: ~$14-16/month for POC/dev environment
################################################################################

locals {
  # Keycloak RDS configuration from config.yaml
  keycloak_enabled     = tobool(try(local.config_file.keycloak.enabled, "false"))
  keycloak_db_name     = try(local.config_file.keycloak.database.name, "keycloak")
  keycloak_db_username = try(local.config_file.keycloak.database.username, "keycloak")

  # Instance configuration
  keycloak_db_instance_class    = try(local.config_file.keycloak.database.instance_class, "db.t4g.micro")
  keycloak_db_allocated_storage = try(local.config_file.keycloak.database.allocated_storage, 20)
  keycloak_db_engine_version    = try(local.config_file.keycloak.database.postgres_version, "15.8")

  # High availability (disable for cost savings in dev)
  keycloak_db_multi_az = tobool(try(local.config_file.keycloak.database.multi_az, "false"))

  # Backup configuration (minimal for cost savings)
  keycloak_db_backup_retention = try(local.config_file.keycloak.database.backup_retention_days, 1)
}

################################################################################
# DB Subnet Group
################################################################################

resource "aws_db_subnet_group" "keycloak" {
  count = local.keycloak_enabled ? 1 : 0

  name       = "${local.cluster_name}-keycloak-db"
  subnet_ids = module.vpc.private_subnets

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-keycloak-db"
      Component = "keycloak"
    }
  )
}

################################################################################
# Security Group for RDS
################################################################################

resource "aws_security_group" "keycloak_rds" {
  count = local.keycloak_enabled ? 1 : 0

  name_prefix = "${local.cluster_name}-keycloak-rds-"
  description = "Security group for Keycloak RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-keycloak-rds"
      Component = "keycloak"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow PostgreSQL access from EKS nodes
resource "aws_security_group_rule" "keycloak_rds_ingress_from_eks" {
  count = local.keycloak_enabled ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.keycloak_rds[0].id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Allow PostgreSQL from EKS nodes"
}

# Allow all outbound (for updates, patches, etc)
resource "aws_security_group_rule" "keycloak_rds_egress" {
  count = local.keycloak_enabled ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.keycloak_rds[0].id
  description       = "Allow all outbound"
}

################################################################################
# Random Password for RDS
################################################################################

resource "random_password" "keycloak_db_password" {
  count = local.keycloak_enabled ? 1 : 0

  length  = 32
  special = true
  # Avoid characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}:?"
}

################################################################################
# Store RDS credentials in Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "keycloak_db" {
  count = local.keycloak_enabled ? 1 : 0

  name_prefix             = "${local.cluster_name}-keycloak-db-"
  description             = "Keycloak RDS PostgreSQL credentials"
  recovery_window_in_days = 7

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-keycloak-db"
      Component = "keycloak"
    }
  )
}

resource "aws_secretsmanager_secret_version" "keycloak_db" {
  count = local.keycloak_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.keycloak_db[0].id
  secret_string = jsonencode({
    username = local.keycloak_db_username
    password = random_password.keycloak_db_password[0].result
    host     = aws_db_instance.keycloak[0].address
    port     = aws_db_instance.keycloak[0].port
    dbname   = local.keycloak_db_name
    # JDBC URL for Keycloak
    jdbc_url = "jdbc:postgresql://${aws_db_instance.keycloak[0].address}:${aws_db_instance.keycloak[0].port}/${local.keycloak_db_name}"
  })
}

################################################################################
# RDS PostgreSQL Instance
################################################################################

resource "aws_db_instance" "keycloak" {
  count = local.keycloak_enabled ? 1 : 0

  # Basic configuration
  identifier     = "${local.cluster_name}-keycloak"
  engine         = "postgres"
  engine_version = local.keycloak_db_engine_version

  # Instance type - db.t4g.micro is the cheapest (ARM Graviton2)
  # Alternative: db.t3.micro if ARM not supported in region
  instance_class = local.keycloak_db_instance_class

  # Storage configuration - minimal for cost savings
  allocated_storage     = local.keycloak_db_allocated_storage
  max_allocated_storage = local.keycloak_db_allocated_storage * 2 # Auto-scaling limit
  storage_type          = "gp3"                                   # gp3 is cheaper than gp2 for same performance
  storage_encrypted     = true                                    # Security best practice

  # Database configuration
  db_name  = local.keycloak_db_name
  username = local.keycloak_db_username
  password = random_password.keycloak_db_password[0].result
  port     = 5432

  # High Availability - disabled for cost savings in POC
  multi_az               = local.keycloak_db_multi_az
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.keycloak[0].name
  vpc_security_group_ids = [aws_security_group.keycloak_rds[0].id]

  # Backup configuration - minimal for cost savings
  backup_retention_period   = local.keycloak_db_backup_retention
  backup_window             = "03:00-04:00" # UTC - adjust for your timezone
  maintenance_window        = "mon:04:00-mon:05:00"
  skip_final_snapshot       = true
  final_snapshot_identifier = null
  copy_tags_to_snapshot     = true

  # Performance Insights - disabled for cost savings
  enabled_cloudwatch_logs_exports = [] # Disable logs for cost savings
  performance_insights_enabled    = false

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  # Deletion protection - disabled for POC (enable in production)
  deletion_protection = false

  # Parameter group for PostgreSQL optimization (optional)
  # parameter_group_name = aws_db_parameter_group.keycloak[0].name

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-keycloak"
      Component = "keycloak"
      Purpose   = "identity-provider"
    }
  )

  depends_on = [
    aws_security_group.keycloak_rds
  ]
}

################################################################################
# Optional: DB Parameter Group for Keycloak Optimization
################################################################################

resource "aws_db_parameter_group" "keycloak" {
  count = local.keycloak_enabled ? 1 : 0

  name_prefix = "${local.cluster_name}-keycloak-"
  family      = "postgres15"
  description = "PostgreSQL parameter group for Keycloak"

  # Optimizations for Keycloak workload (mostly reads)
  parameter {
    name  = "max_connections"
    value = "100"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}" # 25% of RAM
  }

  tags = merge(
    local.tags,
    {
      Name      = "${local.cluster_name}-keycloak-params"
      Component = "keycloak"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
