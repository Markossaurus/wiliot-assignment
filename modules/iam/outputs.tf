output "github_role_arn" {
  description = "IAM role that GitHub Actions on main assumes to push to ECR."
  value       = module.github_role.arn
}

output "producer_role_arn" {
  description = "IRSA role of the producer service account."
  value       = module.producer_role.arn
}

output "consumer_role_arn" {
  description = "IRSA role of the consumer service account."
  value       = module.consumer_role.arn
}

output "db_bootstrap_role_arn" {
  description = "IRSA role of the database bootstrap Job's service account."
  value       = module.db_bootstrap_role.arn
}

output "argocd_role_arn" {
  description = "IRSA role External Secrets uses to mint Argo CD's ECR tokens."
  value       = module.argocd_role.arn
}
