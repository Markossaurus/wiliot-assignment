output "github_role_arn" {
  description = "IAM role that GitHub Actions on main assumes to push to ECR."
  value       = module.github_role.arn
}
