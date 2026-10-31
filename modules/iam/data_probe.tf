locals {
  # RDS has no data source for IAM database users.
  db_reader_user_arn = "arn:aws:rds-db:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:dbuser:${var.rds_resource_id}/${var.db_reader_user}"
}

module "data_probe_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-data-probe-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.data_probe}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    Database = {
      actions   = ["rds-db:connect"]
      resources = [local.db_reader_user_arn]
    }
    # PutMetricData can't be scoped to a resource, only to a namespace.
    Metrics = {
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"]
      condition = [{
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = [var.metrics_namespace]
      }]
    }
    # Read by External Secrets, which authenticates as this service account.
    Parameters = {
      actions   = ["ssm:GetParameter"]
      resources = var.rds_connection_parameter_arns
    }
    DecryptParameters = local.decrypt_parameters
  }
}
