locals {
  suffix = "${var.region}-${var.env}"
  port   = 5432
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier = "rds-${var.name}-${local.suffix}"

  engine         = "postgres"
  engine_version = var.engine_version
  # Off so the pinned engine_version never drifts from what is running.
  auto_minor_version_upgrade = false
  instance_class             = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.name
  username = "postgres"
  port     = local.port
  # RDS generates the master password and keeps it in Secrets Manager; it never reaches state.
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  multi_az               = false
  publicly_accessible    = false
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [module.security_group.id]

  create_db_parameter_group = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  # Apply modifications on terraform apply rather than in the next maintenance window.
  apply_immediately = true
}
