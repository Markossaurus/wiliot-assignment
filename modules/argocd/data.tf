data "aws_region" "current" {}

data "aws_default_tags" "current" {}

data "aws_iam_policy" "permissions_boundary" {
  name = var.permissions_boundary_name
}

data "aws_eks_access_policies" "available" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
