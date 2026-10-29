# Runs the bootstrap once per launch template version and fails the apply, with the
# instance's console log, if the bootstrap script fails.
resource "terraform_data" "bootstrap" {
  triggers_replace = [aws_launch_template.bootstrap.id, aws_launch_template.bootstrap.latest_version]

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
