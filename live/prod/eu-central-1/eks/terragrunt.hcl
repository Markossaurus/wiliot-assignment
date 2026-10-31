include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//eks"
}

dependency "vpc" {
  config_path = "../vpc"

  # Lets validate/plan run before the VPC has been applied.
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  kubernetes_version = "1.37"
  addon_versions = {
    vpc-cni        = "v1.23.2-eksbuild.8"
    coredns        = "v1.14.7-eksbuild.22"
    kube-proxy     = "v1.37.0-eksbuild.32"
    metrics-server = "v0.9.0-eksbuild.14"

    amazon-cloudwatch-observability = "v7.0.0-eksbuild.1"
  }

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids

  node_ami_release_version = "1.37.1-20261026"
  node_instance_types      = ["t3.large"]
  # One node per AZ, so each producer and consumer replica can run in its own zone.
  node_min_size     = 3
  node_max_size     = 4
  node_desired_size = 3
}
