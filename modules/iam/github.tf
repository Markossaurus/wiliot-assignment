# Assumed by GitHub Actions to push to ECR. Only workflows running on main get it, so pull
# requests never reach AWS.
module "github_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-github-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  # Trusts the account's existing GitHub OIDC provider, which is shared and not managed here.
  enable_github_oidc = true
  oidc_subjects      = ["repo:${var.github_repository}:ref:refs/heads/main"]

  create_inline_policy = true
  inline_policy_permissions = {
    # GetAuthorizationToken can't be scoped to a repository.
    Login = {
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    Push = {
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = var.ecr_repository_arns
    }
  }
}
