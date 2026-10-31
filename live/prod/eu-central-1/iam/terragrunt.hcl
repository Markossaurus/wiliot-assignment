include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//iam"
}

dependency "ecr" {
  config_path = "../ecr"

  mock_outputs = {
    repository_arns = { producer = "arn:aws:ecr:eu-central-1:000000000000:repository/producer" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    oidc_provider = "oidc.eks.eu-central-1.amazonaws.com/id/00000000000000000000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "msk" {
  config_path = "../msk"

  mock_outputs = {
    cluster_arn                     = "arn:aws:kafka:eu-central-1:000000000000:cluster/mock/00000000-0000-0000-0000-000000000000-1"
    topic_arns                      = { "binance.trades" = "arn:aws:kafka:eu-central-1:000000000000:topic/mock/00000000-0000-0000-0000-000000000000-1/binance.trades" }
    bootstrap_brokers_parameter_arn = "arn:aws:ssm:eu-central-1:000000000000:parameter/mock/bootstrap-brokers-sasl-iam"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    connection_parameter_arns = { address = "arn:aws:ssm:eu-central-1:000000000000:parameter/mock/address" }
    instance_arn              = "arn:aws:rds:eu-central-1:000000000000:db:mock"
    resource_id               = "db-MOCK"
    master_user_secret_arn    = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  # GitHub's immutable subject format pins owner and repo by ID, so a recreated repo with the
  # same name can't assume the role.
  github_repository   = "Markossaurus@80157279/wiliot-assignment@1440645918"
  ecr_repository_arns = values(dependency.ecr.outputs.repository_arns)

  oidc_provider = dependency.eks.outputs.oidc_provider

  msk_cluster_arn                     = dependency.msk.outputs.cluster_arn
  msk_topic_arn                       = dependency.msk.outputs.topic_arns["binance.trades"]
  msk_bootstrap_brokers_parameter_arn = dependency.msk.outputs.bootstrap_brokers_parameter_arn
  kafka_consumer_group                = "trades-writer"

  rds_connection_parameter_arns = values(dependency.rds.outputs.connection_parameter_arns)
  rds_instance_arn              = dependency.rds.outputs.instance_arn
  rds_resource_id               = dependency.rds.outputs.resource_id
  rds_master_user_secret_arn    = dependency.rds.outputs.master_user_secret_arn
  db_user                       = "trades_writer"

}
