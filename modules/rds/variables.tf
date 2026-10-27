variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "name" {
  description = "Logical database name, used in resource names and as the initial database."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Upper limit in GiB for storage autoscaling."
  type        = number
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "db_subnet_group_name" {
  description = "DB subnet group spanning the isolated database subnets."
  type        = string
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect to PostgreSQL (the EKS nodes)."
  type        = string
}
