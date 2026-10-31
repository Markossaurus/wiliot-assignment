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

# Shared by the CloudWatch agent and Fluent Bit, which both run as amazon-cloudwatch/cloudwatch-agent.
module "cloudwatch_agent_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.8.2"

  name                 = "${var.name_prefix}-role-irsa-cloudwatch-agent-${local.suffix}"
  use_name_prefix      = false
  permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:cloudwatch-agent"]
    }
  }

  policies = {
    CloudWatchAgentServerPolicy = data.aws_iam_policy.cloudwatch_agent_server.arn
  }
}
