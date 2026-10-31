module "producer_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-producer-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.producer}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    # The producer is idempotent, which needs a cluster-level permission.
    KafkaCluster = {
      actions   = ["kafka-cluster:Connect", "kafka-cluster:WriteDataIdempotently"]
      resources = [var.msk_cluster_arn]
    }
    KafkaTopic = {
      actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
      resources = [var.msk_topic_arn]
    }
    # Read by External Secrets, which authenticates as this service account.
    Parameters = {
      actions   = ["ssm:GetParameter"]
      resources = [var.msk_bootstrap_brokers_parameter_arn]
    }
    DecryptParameters = local.decrypt_parameters
  }
}
