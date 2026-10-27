module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-vpc-cni-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  # AWS-managed policy rather than attach_vpc_cni_policy, which would create a custom policy.
  policies = {
    AmazonEKS_CNI_Policy = data.aws_iam_policy.eks_cni.arn
  }
}
