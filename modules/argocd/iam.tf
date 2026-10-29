# No policies: kubectl and helm authenticate to EKS through the access entry, and the
# token from `aws eks get-token` needs no IAM permission.
module "iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                    = "${var.name_prefix}-role-${local.name}"
  use_name_prefix         = false
  permissions_boundary    = data.aws_iam_policy.permissions_boundary.arn
  create_instance_profile = true

  trust_policy_permissions = {
    ec2 = {
      actions    = ["sts:AssumeRole"]
      principals = [{ type = "Service", identifiers = ["ec2.amazonaws.com"] }]
    }
  }
}
