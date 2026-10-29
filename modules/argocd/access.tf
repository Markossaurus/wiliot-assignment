locals {
  cluster_admin_policy_arn = one([
    for policy in data.aws_eks_access_policies.available.access_policies : policy.arn
    if policy.name == "AmazonEKSClusterAdminPolicy"
  ])
}

# Installing Argo CD creates CRDs and cluster roles, so the bootstrap needs cluster-wide admin.
resource "aws_eks_access_entry" "bootstrap" {
  cluster_name  = var.cluster_name
  principal_arn = module.iam_role.arn
}

resource "aws_eks_access_policy_association" "bootstrap" {
  cluster_name  = var.cluster_name
  principal_arn = aws_eks_access_entry.bootstrap.principal_arn
  policy_arn    = local.cluster_admin_policy_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = module.security_group.id
  description                  = "EKS API from the Argo CD bootstrap instance"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = {
    Name = "sgrule-eks-api-from-${local.name}"
  }
}
