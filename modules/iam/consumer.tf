locals {
  # MSK has no data source for group ARNs; they share the cluster ARN's name/UUID path.
  consumer_group_arn = "${replace(var.msk_cluster_arn, ":cluster/", ":group/")}/${var.kafka_consumer_group}"
  # Neither does RDS for IAM database users.
  db_user_arn = "arn:aws:rds-db:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:dbuser:${var.rds_resource_id}/${var.db_user}"
}

module "consumer_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-consumer-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.consumer}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    KafkaCluster = {
      actions   = ["kafka-cluster:Connect"]
      resources = [var.msk_cluster_arn]
    }
    KafkaTopic = {
      actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
      resources = [var.msk_topic_arn]
    }
    KafkaGroup = {
      actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
      resources = [local.consumer_group_arn]
    }
    Database = {
      actions   = ["rds-db:connect"]
      resources = [local.db_user_arn]
    }
    # Read by External Secrets, which authenticates as this service account.
    Parameters = {
      actions   = ["ssm:GetParameter"]
      resources = concat([var.msk_bootstrap_brokers_parameter_arn], var.rds_connection_parameter_arns)
    }
    DecryptParameters = local.decrypt_parameters
  }
}
