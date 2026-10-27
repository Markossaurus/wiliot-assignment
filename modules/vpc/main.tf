locals {
  suffix     = "${var.region}-${var.env}"
  az_letters = [for az in var.azs : substr(az, length(az) - 1, 1)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "vpc-${local.suffix}"
  cidr = var.cidr
  azs  = var.azs

  private_subnets       = var.private_subnets
  private_subnet_names  = [for l in local.az_letters : "subnet-private-${l}-${local.suffix}"]
  public_subnets        = var.public_subnets
  public_subnet_names   = [for l in local.az_letters : "subnet-public-${l}-${local.suffix}"]
  database_subnets      = var.database_subnets
  database_subnet_names = [for l in local.az_letters : "subnet-db-${l}-${local.suffix}"]

  private_route_table_tags  = { Name = "rt-private-${local.suffix}" }
  public_route_table_tags   = { Name = "rt-public-${local.suffix}" }
  database_route_table_tags = { Name = "rt-db-${local.suffix}" }
  default_route_table_name  = "rt-default-${local.suffix}"

  default_security_group_name = "secgroup-default-${local.suffix}"
  default_network_acl_name    = "nacl-default-${local.suffix}"

  igw_tags         = { Name = "igw-main-${local.suffix}" }
  nat_gateway_tags = { Name = "nat-main-${local.suffix}" }
  nat_eip_tags     = { Name = "eip-nat-${local.suffix}" }

  database_subnet_group_name = "subnetgroup-db-${local.suffix}"

  enable_nat_gateway = true
  single_nat_gateway = true

  create_database_subnet_route_table = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}
