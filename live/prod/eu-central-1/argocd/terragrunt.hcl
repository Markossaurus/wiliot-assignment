include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//argocd"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    cluster_security_group_id          = "sg-00000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  instance_type = "t3.micro"
  vpc_id        = dependency.vpc.outputs.vpc_id
  subnet_id     = dependency.vpc.outputs.private_subnet_ids[0]

  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_security_group_id          = dependency.eks.outputs.cluster_security_group_id

  kubectl = {
    version = "1.37.1"
    sha256  = "65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8"
  }
  helm = {
    version = "4.3.1"
    sha256  = "0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b"
  }
  argocd_chart_version = "10.11.6"

  repo_url      = "https://github.com/Markossaurus/wiliot-assignment.git"
  repo_revision = "main"
  repo_path     = "deploy/trades"
  app_name      = "trades"
  app_namespace = "trades"
  value_files   = ["values-prod.yaml"]
}
