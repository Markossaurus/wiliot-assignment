output "health_alarm_name" {
  description = "Composite alarm whose state is the pipeline's health."
  value       = aws_cloudwatch_composite_alarm.health.alarm_name
}

output "alarm_topic_arn" {
  description = "SNS topic that health changes are published to."
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard of the pipeline."
  value       = aws_cloudwatch_dashboard.trades.dashboard_name
}
