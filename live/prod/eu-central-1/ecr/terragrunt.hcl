include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//ecr"
}

inputs = {
  # charts/* hold each service's Helm chart as an OCI artifact; Argo CD pulls them from there.
  repositories = ["producer", "consumer", "db-bootstrap", "charts/producer", "charts/consumer", "charts/database"]
}
