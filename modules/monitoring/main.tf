locals {
  suffix = "${var.region}-${var.env}"

  kafka_lag_dimensions = {
    "Cluster Name"   = var.msk_cluster_name
    "Consumer Group" = var.kafka_consumer_group
    "Topic"          = var.kafka_topic
  }
}

# Alarm notifications; subscriptions (email, SMS) are added per operator, outside this repo.
# Unencrypted on purpose: CloudWatch can't publish to topics encrypted with the AWS-managed SNS key.
resource "aws_sns_topic" "alarms" {
  name = "sns-trades-alarms-${local.suffix}"
}
