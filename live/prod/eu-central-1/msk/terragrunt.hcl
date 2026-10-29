include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//msk"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id              = "vpc-00000000000000000"
    database_subnet_ids = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name = "trades"
  # kafka.t3.small can't run in KRaft mode, and 3.9 is the last Kafka release with ZooKeeper.
  kafka_version        = "3.9.x"
  broker_instance_type = "kafka.t3.small"
  broker_count         = 3
  broker_volume_size   = 20

  vpc_id                    = dependency.vpc.outputs.vpc_id
  subnet_ids                = dependency.vpc.outputs.database_subnet_ids
  allowed_security_group_id = dependency.eks.outputs.node_security_group_id

  topics = {
    "binance.trades" = {
      partitions         = 6
      replication_factor = 3
      configs            = { "retention.ms" = "604800000" }
    }
  }
}
