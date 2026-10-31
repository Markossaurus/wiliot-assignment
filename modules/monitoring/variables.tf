variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "metrics_namespace" {
  description = "CloudWatch namespace the data probe publishes freshness and completeness to."
  type        = string
}

variable "msk_cluster_name" {
  description = "MSK cluster name, the dimension of its CloudWatch metrics."
  type        = string
}

variable "kafka_topic" {
  description = "Topic the consumer reads."
  type        = string
}

variable "kafka_consumer_group" {
  description = "Consumer group whose lag is alarmed on."
  type        = string
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier, the dimension of its CloudWatch metrics."
  type        = string
}

variable "freshness_target_seconds" {
  description = "p99 time from a trade executing on Binance to its row being in PostgreSQL."
  type        = number
}

variable "staleness_threshold_seconds" {
  description = "Time since the last trade landed after which the pipeline counts as stopped."
  type        = number
}

variable "consumer_lag_threshold_seconds" {
  description = "Estimated time lag of the consumer group after which it counts as falling behind."
  type        = number
}
