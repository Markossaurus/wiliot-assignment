include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//rds"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                     = "vpc-00000000000000000"
    database_subnet_group_name = "mock"
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
  name           = "trades"
  engine_version = "18.6"
  instance_class = "db.t4g.medium"

  allocated_storage     = 20
  max_allocated_storage = 100

  vpc_id                    = dependency.vpc.outputs.vpc_id
  db_subnet_group_name      = dependency.vpc.outputs.database_subnet_group_name
  allowed_security_group_id = dependency.eks.outputs.node_security_group_id
}
