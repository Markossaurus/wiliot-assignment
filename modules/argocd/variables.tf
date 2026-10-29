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

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the bootstrap instance; it needs NAT to download tools and the chart."
  type        = string
}

variable "instance_type" {
  description = "Instance type of the bootstrap instance."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API server endpoint."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Cluster security group that guards the EKS API endpoint."
  type        = string
}

variable "kubectl" {
  description = "kubectl release installed on the bootstrap instance, with the SHA-256 of its linux/amd64 binary."
  type = object({
    version = string
    sha256  = string
  })
}

variable "helm" {
  description = "Helm release installed on the bootstrap instance, with the SHA-256 of its linux-amd64 tarball."
  type = object({
    version = string
    sha256  = string
  })
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart."
  type        = string
}

variable "repo_url" {
  description = "Git repository the root Application deploys from."
  type        = string
}

variable "repo_revision" {
  description = "Branch, tag or commit the root Application tracks."
  type        = string
}

variable "repo_path" {
  description = "Path of the Helm chart inside the repository."
  type        = string
}

variable "app_name" {
  description = "Name of the root Argo CD Application."
  type        = string
}

variable "app_namespace" {
  description = "Namespace the root Application deploys into."
  type        = string
}

variable "value_files" {
  description = "Helm values files, relative to the chart path, that the root Application renders with."
  type        = list(string)
}
