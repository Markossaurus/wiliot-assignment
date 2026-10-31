# External Secrets uses this role to mint ECR tokens for Argo CD's chart repository credentials;
# a token carries the permissions of the role that requested it.
module "argocd_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-argocd-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  enable_oidc        = true
  oidc_provider_urls = [var.oidc_provider]
  oidc_subjects      = ["system:serviceaccount:${local.service_accounts.argocd}"]
  oidc_audiences     = ["sts.amazonaws.com"]

  create_inline_policy = true
  inline_policy_permissions = {
    # GetAuthorizationToken can't be scoped to a repository.
    Login = {
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    # ListImages lets Helm resolve chart versions to tags.
    Pull = {
      actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:ListImages"]
      resources = var.chart_repository_arns
    }
  }
}
