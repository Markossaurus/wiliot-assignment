# The migration Job's init container hands Flyway the RDS master credentials. It looks up the
# master secret through the instance, because RDS generates the secret's name.
module "db_bootstrap_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-db-bootstrap-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.db_bootstrap}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    DescribeInstance = {
      actions   = ["rds:DescribeDBInstances"]
      resources = [var.rds_instance_arn]
    }
    MasterSecret = {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.rds_master_user_secret_arn]
    }
    # The secret uses the AWS-managed aws/secretsmanager key; decrypting is allowed only through Secrets Manager.
    DecryptSecret = {
      actions   = ["kms:Decrypt"]
      resources = [data.aws_kms_alias.secretsmanager.target_key_arn]
      condition = [{
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.region}.amazonaws.com"]
      }]
    }
  }
}
