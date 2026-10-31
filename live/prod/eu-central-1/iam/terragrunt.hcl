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
  # GitHub's immutable subject format pins owner and repo by ID, so a recreated repo with the
  # same name can't assume the role.
  github_repository   = "Markossaurus@80157279/wiliot-assignment@1440645918"
  ecr_repository_arns = values(dependency.ecr.outputs.repository_arns)
}
