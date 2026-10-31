variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "name_prefix" {
  description = "Prefix required by the sandbox on IAM role names."
  type        = string
}

variable "permissions_boundary_name" {
  description = "Name of the IAM policy attached as permissions boundary to every IAM role."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository whose main branch may push to ECR, as it appears in the OIDC subject (owner@owner_id/name@repo_id)."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories that GitHub Actions pushes images and charts to."
  type        = list(string)
}

variable "oidc_provider" {
  description = "EKS OIDC issuer without the https:// scheme, trusted by the IRSA roles."
  type        = string
}

variable "msk_cluster_arn" {
  description = "MSK cluster ARN."
  type        = string
}

variable "msk_topic_arn" {
  description = "ARN of the trades topic."
  type        = string
}

variable "kafka_consumer_group" {
  description = "Kafka consumer group of the consumer."
  type        = string
}

variable "msk_bootstrap_brokers_parameter_arn" {
  description = "SSM parameter holding the SASL/IAM bootstrap brokers."
  type        = string
}

variable "rds_connection_parameter_arns" {
  description = "SSM parameters holding the database address, port and name."
  type        = list(string)
}

variable "rds_instance_arn" {
  description = "DB instance ARN."
  type        = string
}

variable "rds_resource_id" {
  description = "DB resource ID, used in rds-db:connect ARNs."
  type        = string
}

variable "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials."
  type        = string
}

variable "db_user" {
  description = "Database user the consumer connects as with IAM authentication."
  type        = string
}

variable "db_reader_user" {
  description = "Read-only database user the data probe connects as with IAM authentication."
  type        = string
}

variable "db_backfill_user" {
  description = "Database user the backfill connects as with IAM authentication."
  type        = string
}

variable "metrics_namespace" {
  description = "CloudWatch namespace the data probe publishes its metrics to."
  type        = string
}

variable "chart_repository_arns" {
  description = "ECR repositories holding the Helm charts that Argo CD pulls."
  type        = list(string)
}
