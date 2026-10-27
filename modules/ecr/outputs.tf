output "repository_urls" {
  description = "Repository URLs, keyed by repository name."
  value       = { for name, repo in module.ecr : name => repo.repository_url }
}
