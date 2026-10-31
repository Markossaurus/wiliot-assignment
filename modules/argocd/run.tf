# Runs the bootstrap once per cluster and fails the apply, with the instance's console log, if the
# bootstrap script fails. Afterwards Argo CD manages itself from Git, so a normal apply never
# re-runs it; `terragrunt apply -replace=terraform_data.bootstrap` does, as a break-glass.
resource "terraform_data" "bootstrap" {
  # The endpoint is unique to each cluster, unlike its name or ARN.
  triggers_replace = [var.cluster_endpoint]

  provisioner "local-exec" {
    command = join(" ", [
      "bash ${path.module}/scripts/run_bootstrap.sh",
      aws_launch_template.bootstrap.id,
      aws_launch_template.bootstrap.latest_version,
      data.aws_region.current.region,
    ])
  }

  # The instance must only boot once it can reach and authenticate to the API.
  depends_on = [
    aws_eks_access_policy_association.bootstrap,
    aws_vpc_security_group_ingress_rule.cluster_api,
  ]
}
