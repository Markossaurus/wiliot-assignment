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

variable "github_repository" {
  description = "GitHub repository (owner/name) whose main branch may push to ECR."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories that GitHub Actions pushes images and charts to."
  type        = list(string)
}
