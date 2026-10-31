# KEDA's operator reads the consumer group's lag to scale the consumer. It can describe the topic
# and the group, but not read or write any message.
module "keda_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-keda-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.keda}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    KafkaCluster = {
      actions   = ["kafka-cluster:Connect"]
      resources = [var.msk_cluster_arn]
    }
    KafkaTopic = {
      actions   = ["kafka-cluster:DescribeTopic"]
      resources = [var.msk_topic_arn]
    }
    KafkaGroup = {
      actions   = ["kafka-cluster:DescribeGroup"]
      resources = [local.consumer_group_arn]
    }
  }
}
