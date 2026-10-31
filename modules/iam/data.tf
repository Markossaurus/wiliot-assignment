data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy" "permissions_boundary" {
  name = var.permissions_boundary_name
}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}
