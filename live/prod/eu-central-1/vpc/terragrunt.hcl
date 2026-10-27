include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//vpc"
}

inputs = {
  cidr = "10.20.0.0/16"
  azs  = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

  private_subnets  = ["10.20.0.0/19", "10.20.32.0/19", "10.20.64.0/19"]
  public_subnets   = ["10.20.96.0/24", "10.20.97.0/24", "10.20.98.0/24"]
  database_subnets = ["10.20.100.0/24", "10.20.101.0/24", "10.20.102.0/24"]
}
