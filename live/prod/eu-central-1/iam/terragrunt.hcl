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

inputs = {
  github_repository   = "Markossaurus/wiliot-assignment"
  ecr_repository_arns = values(dependency.ecr.outputs.repository_arns)
}
