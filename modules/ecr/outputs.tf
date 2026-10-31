output "repository_urls" {
  description = "Repository URLs, keyed by repository name."
  value       = { for name, repo in module.ecr : name => repo.repository_url }
}

output "repository_arns" {
  description = "Repository ARNs, keyed by repository name, for push and pull policies."
  value       = { for name, repo in module.ecr : name => repo.repository_arn }
}
