output "cluster_arn" {
  description = "MSK cluster ARN, for kafka-cluster:Connect in IRSA policies."
  value       = module.msk.arn
}

output "cluster_name" {
  description = "MSK cluster name."
  value       = module.msk.cluster_name
}

output "bootstrap_brokers_sasl_iam" {
  description = "Bootstrap broker string for SASL/IAM clients."
  value       = module.msk.bootstrap_brokers_sasl_iam
}

output "bootstrap_brokers_parameter_arn" {
  description = "SSM parameter holding the SASL/IAM bootstrap brokers, for IRSA policies."
  value       = aws_ssm_parameter.bootstrap_brokers.arn
}

output "topic_arns" {
  description = "Topic ARNs keyed by topic name, for IRSA policies."
  value       = { for name, topic in module.msk.topics : name => topic.arn }
}
