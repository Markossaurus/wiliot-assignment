output "address" {
  description = "Database hostname."
  value       = module.rds.db_instance_address
}

output "port" {
  description = "Database port."
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Initial database name."
  value       = module.rds.db_instance_name
}

output "connection_parameter_arns" {
  description = "SSM parameters holding the connection details, keyed by attribute, for IRSA policies."
  value       = { for key, parameter in aws_ssm_parameter.connection : key => parameter.arn }
}

output "resource_id" {
  description = "DB resource ID, used in rds-db:connect ARNs for IAM authentication."
  value       = module.rds.db_instance_resource_id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials."
  value       = module.rds.db_instance_master_user_secret_arn
}

output "instance_arn" {
  description = "DB instance ARN, for rds:DescribeDBInstances in IRSA policies."
  value       = module.rds.db_instance_arn
}

output "identifier" {
  description = "DB instance identifier, the dimension of its CloudWatch metrics."
  value       = module.rds.db_instance_identifier
}
