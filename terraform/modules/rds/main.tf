# ──────────────────────────────────────────────
# RDS Module
# Provisions a PostgreSQL RDS instance with encryption,
# multi-AZ support, automated backups, and proper
# security group isolation.
# ──────────────────────────────────────────────

locals {
  common_tags = merge(var.tags, {
    Module    = "rds"
    ManagedBy = "terraform"
  })
}

# ──────────────────────────────────────────────
# DB Subnet Group
# ──────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-db-subnet-group"
  })
}

# ──────────────────────────────────────────────
# RDS PostgreSQL Instance
# ──────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.environment}-postgres"

  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password
  port     = var.database_port

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.database_security_group_id]

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Snapshots
  skip_final_snapshot       = var.environment == "dev"
  final_snapshot_identifier = var.environment != "dev" ? "${var.project}-${var.environment}-final-snapshot" : null
  copy_tags_to_snapshot     = true

  # Performance & monitoring
  performance_insights_enabled          = var.environment != "dev"
  performance_insights_retention_period = var.environment != "dev" ? 7 : 0
  monitoring_interval                   = var.environment != "dev" ? 60 : 0
  monitoring_role_arn                   = var.environment != "dev" ? aws_iam_role.rds_monitoring[0].arn : null

  # Security
  deletion_protection = var.environment == "prod"
  publicly_accessible = false

  # Updates
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = var.environment == "dev"

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-postgres"
  })
}

# ──────────────────────────────────────────────
# Enhanced Monitoring IAM Role (staging/prod only)
# ──────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment != "dev" ? 1 : 0

  name = "${var.project}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.environment != "dev" ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  role       = aws_iam_role.rds_monitoring[0].name
}
