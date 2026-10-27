variable "region" {
  description = "Short region name used in resource names (e.g. euc1)."
  type        = string
}

variable "env" {
  description = "Environment name used in resource names."
  type        = string
}

variable "name_prefix" {
  description = "Prefix required by the sandbox on IAM role names."
  type        = string
}

variable "permissions_boundary_name" {
  description = "Name of the IAM policy attached as permissions boundary to every IAM role."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane ENIs and nodes."
  type        = list(string)
}

variable "addon_versions" {
  description = "Pinned EKS add-on versions, keyed by add-on name. Must match kubernetes_version."
  type        = map(string)
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Desired number of nodes."
  type        = number
}
