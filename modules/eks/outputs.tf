output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN, for IRSA role trust policies."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC issuer without the https:// scheme, for IRSA trust conditions."
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Node security group ID, for allowing node traffic to RDS and MSK."
  value       = module.eks.node_security_group_id
}
