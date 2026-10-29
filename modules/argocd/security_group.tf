module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  # Gets a random suffix: the module replaces the group create-before-destroy.
  name        = "secgroup-${local.name}"
  description = "Argo CD bootstrap instance: no inbound, HTTPS out"
  vpc_id      = var.vpc_id

  egress_rules = {
    https = {
      description = "EKS API, tool downloads and the Argo CD chart"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 443
      to_port     = 443
    }
  }
}
