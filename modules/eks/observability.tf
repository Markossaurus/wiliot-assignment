locals {
  container_insights_log_groups = ["application", "dataplane", "host", "performance"]
}

# Created here rather than by the add-on's agents on their first write, so they get a retention
# period and destroying the cluster removes them too.
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(local.container_insights_log_groups)

  name              = "/aws/containerinsights/${module.eks.cluster_name}/${each.value}"
  retention_in_days = 7
}

# Ships container logs (Fluent Bit) and Container Insights metrics (CloudWatch agent) to CloudWatch.
# Outside the eks module so it can wait for the log groups, and for the nodes it runs on.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = var.addon_versions["amazon-cloudwatch-observability"]
  service_account_role_arn = module.cloudwatch_agent_irsa.arn

  configuration_values = jsonencode({
    # The add-on creates the agent's Service only with this on, and Fluent Bit asks that Service
    # which workload each pod belongs to. Idle unless pods are annotated for instrumentation.
    applicationSignals = { enabled = true }
  })

  depends_on = [aws_cloudwatch_log_group.container_insights, module.eks]
}
