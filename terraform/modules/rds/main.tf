# ============================================================
#  modules/rds/main.tf — RDS MySQL Multi-AZ
# ============================================================

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "DB subnet group for ${var.project_name}"
  tags        = { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
}

resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-mysql-params"
  family      = "mysql8.0"
  description = "Custom MySQL 8.0 parameter group"

  parameter {
    name  = "max_connections"
    value = "200"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = { Name = "${var.project_name}-mysql-params" }
}

resource "aws_db_instance" "main" {
  identifier                 = "${var.project_name}-${var.environment}-mysql"
  engine                     = "mysql"
  engine_version             = var.engine_version
  instance_class             = var.instance_class
  allocated_storage          = 20
  max_allocated_storage      = 100
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = var.db_password
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = var.security_group_ids
  parameter_group_name       = aws_db_parameter_group.main.name
  multi_az                   = var.multi_az
  publicly_accessible        = false
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = "${var.project_name}-${var.environment}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  deletion_protection        = var.deletion_protection
  backup_retention_period    = 7
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  tags = {
    Name = "${var.project_name}-${var.environment}-mysql"
    Tier = "database"
  }

  lifecycle {
    ignore_changes = [password] # password managed by Secrets Manager
  }
}
