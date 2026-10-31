include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//argocd"
}

locals {
  env                = read_terragrunt_config(find_in_parent_folders("account.hcl")).locals.env
  argocd_application = yamldecode(file("${get_repo_root()}/argocd/${local.env}/apps/argocd.yaml"))
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
  # Argo CD manages itself from these files once bootstrapped; installing the same chart version
  # and values makes the hand-over a no-op.
  argocd_chart_repository = local.argocd_application.spec.sources[0].repoURL
  argocd_chart_version    = local.argocd_application.spec.sources[0].targetRevision
  argocd_values           = file("${get_repo_root()}/argocd/${local.env}/values/argocd.yaml")
  root_application        = file("${get_repo_root()}/argocd/roots/${local.env}.yaml")
}
