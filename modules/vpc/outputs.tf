output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs, for EKS nodes and pods."
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs, for RDS and MSK."
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "RDS subnet group spanning the database subnets."
  value       = module.vpc.database_subnet_group_name
}
