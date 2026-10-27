data "aws_iam_policy" "permissions_boundary" {
  name = var.permissions_boundary_name
}

data "aws_iam_policy" "eks_cni" {
  name = "AmazonEKS_CNI_Policy"
}
