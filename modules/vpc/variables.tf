variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "azs" {
  description = "Availability zones, in the same order as the subnet lists."
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs (nodes and pods), one per AZ."
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDRs (NAT gateway), one per AZ."
  type        = list(string)
}

variable "database_subnets" {
  description = "Isolated database subnet CIDRs (RDS, MSK), one per AZ."
  type        = list(string)
}
