include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//monitoring"
}

dependency "msk" {
  config_path = "../msk"

  mock_outputs = {
    cluster_name = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    identifier = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  metrics_namespace       = "Trades"
  msk_cluster_name        = dependency.msk.outputs.cluster_name
  kafka_topic             = "binance.trades"
  kafka_consumer_group    = "trades-writer"
  rds_instance_identifier = dependency.rds.outputs.identifier

  freshness_target_seconds       = 1
  staleness_threshold_seconds    = 60
  consumer_lag_threshold_seconds = 30
}
