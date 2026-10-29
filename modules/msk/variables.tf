variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "name" {
  description = "Logical cluster name, used in resource names."
  type        = string
}

variable "kafka_version" {
  description = "Apache Kafka version as MSK names it (e.g. 3.9.x)."
  type        = string
}

variable "broker_instance_type" {
  description = "MSK broker instance type."
  type        = string
}

variable "broker_count" {
  description = "Number of brokers; must be a multiple of the number of subnets."
  type        = number
}

variable "broker_volume_size" {
  description = "EBS storage per broker in GiB."
  type        = number
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the broker ENIs, one per availability zone."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect to the brokers (the EKS nodes)."
  type        = string
}

variable "topics" {
  description = "Topics to create, keyed by topic name."
  type = map(object({
    partitions         = number
    replication_factor = number
    configs            = optional(map(string), {})
  }))
}
