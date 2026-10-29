locals {
  suffix = "${var.region}-${var.env}"
  # Brokers listen for SASL/IAM over TLS on this port.
  port = 9098
}

module "msk" {
  source  = "terraform-aws-modules/msk-kafka-cluster/aws"
  version = "3.3.0"

  name                   = "msk-${var.name}-${local.suffix}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_instance_type   = var.broker_instance_type
  broker_node_client_subnets  = var.subnet_ids
  broker_node_security_groups = [module.security_group.id]
  broker_node_storage_info = {
    ebs_storage_info = { volume_size = var.broker_volume_size }
  }
  enable_storage_autoscaling = false

  client_authentication = {
    sasl = { iam = true }
  }
  encryption_in_transit_client_broker = "TLS"
  encryption_in_transit_in_cluster    = true

  # Gets a random suffix: the module replaces the configuration create-before-destroy.
  configuration_name = "mskconfig-${var.name}-${local.suffix}"
  configuration_server_properties = {
    "auto.create.topics.enable"  = "false"
    "default.replication.factor" = "3"
    "min.insync.replicas"        = "2"
  }

  enhanced_monitoring                    = "DEFAULT"
  cloudwatch_logs_enabled                = true
  cloudwatch_log_group_retention_in_days = 7

  create_schema_registry = false

  # Created through the MSK topic API, so no Kafka admin client has to reach the brokers.
  topics = {
    for name, topic in var.topics : name => {
      partition_count    = topic.partitions
      replication_factor = topic.replication_factor
      configs            = jsonencode(topic.configs)
    }
  }
}
