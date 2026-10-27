locals {
  suffix = "${var.region}-${var.env}"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = "eks-${local.suffix}"
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # API reachable only from inside the VPC (via an SSM tunnel); the repo is public.
  endpoint_private_access = true
  endpoint_public_access  = false

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  iam_role_name                 = "${var.name_prefix}-role-eks-cluster-${local.suffix}"
  iam_role_use_name_prefix      = false
  iam_role_permissions_boundary = data.aws_iam_policy.permissions_boundary.arn

  # The module's KMS key policy already grants the cluster role; this would only add a
  # redundant IAM policy, which also needs iam:CreatePolicy.
  attach_encryption_policy        = false
  kms_key_deletion_window_in_days = 7

  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  # SGs, the node group and its launch template get a random suffix after these names:
  # the module replaces them create-before-destroy, so fixed names would collide.
  security_group_name      = "secgroup-eks-cluster-${local.suffix}"
  node_security_group_name = "secgroup-eks-node-${local.suffix}"

  addons = {
    vpc-cni = {
      addon_version            = var.addon_versions["vpc-cni"]
      service_account_role_arn = module.vpc_cni_irsa.arn
      # Installed before the nodes so they join with pod networking ready.
      before_compute       = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    coredns = {
      addon_version = var.addon_versions["coredns"]
    }
    kube-proxy = {
      addon_version = var.addon_versions["kube-proxy"]
    }
    metrics-server = {
      addon_version = var.addon_versions["metrics-server"]
    }
  }

  eks_managed_node_groups = {
    main = {
      name                 = "nodegroup-main-${local.suffix}"
      launch_template_name = "lt-nodegroup-main-${local.suffix}"

      iam_role_name                 = "${var.name_prefix}-role-eks-node-${local.suffix}"
      iam_role_use_name_prefix      = false
      iam_role_permissions_boundary = data.aws_iam_policy.permissions_boundary.arn
      # aws-node gets these permissions from its own IRSA role instead.
      iam_role_attach_cni_policy = false

      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Hop limit 1 stops pods from reaching the node role's credentials through IMDS.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
