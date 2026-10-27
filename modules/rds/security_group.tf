module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  # Gets a random suffix: the module replaces the group create-before-destroy.
  name        = "secgroup-rds-${var.name}-${local.suffix}"
  description = "PostgreSQL from EKS nodes"
  vpc_id      = var.vpc_id

  ingress_rules = {
    eks_nodes = {
      description                  = "PostgreSQL from EKS nodes"
      from_port                    = local.port
      to_port                      = local.port
      referenced_security_group_id = var.allowed_security_group_id
    }
  }
}
