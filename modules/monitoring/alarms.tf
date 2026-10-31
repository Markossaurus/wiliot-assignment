# Missing datapoints count as breaching: a stopped probe or pipeline must not look healthy.
resource "aws_cloudwatch_metric_alarm" "staleness" {
  alarm_name          = "alarm-trades-staleness-${local.suffix}"
  alarm_description   = "No trade has landed in PostgreSQL for ${var.staleness_threshold_seconds}s, or the data probe stopped reporting."
  namespace           = var.metrics_namespace
  metric_name         = "SecondsSinceLastTrade"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.staleness_threshold_seconds
  treat_missing_data  = "breaching"
}

# The freshness target. A minute without trades has no latency datapoint; staleness covers that.
resource "aws_cloudwatch_metric_alarm" "freshness" {
  alarm_name          = "alarm-trades-freshness-${local.suffix}"
  alarm_description   = "p99 of trade time to row in PostgreSQL is above ${var.freshness_target_seconds}s for 5 minutes."
  namespace           = var.metrics_namespace
  metric_name         = "IngestLatencyP99"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.freshness_target_seconds
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "completeness" {
  alarm_name          = "alarm-trades-completeness-${local.suffix}"
  alarm_description   = "Trade IDs are missing in PostgreSQL: trades were lost and not yet backfilled."
  namespace           = var.metrics_namespace
  metric_name         = "MissingTrades"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
}

# Measured by the brokers, so it holds even when the consumer can't report about itself.
resource "aws_cloudwatch_metric_alarm" "consumer_lag" {
  alarm_name          = "alarm-trades-consumer-lag-${local.suffix}"
  alarm_description   = "The consumer group is more than ${var.consumer_lag_threshold_seconds}s behind the topic for 3 minutes."
  namespace           = "AWS/Kafka"
  metric_name         = "EstimatedMaxTimeLag"
  dimensions          = local.kafka_lag_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.consumer_lag_threshold_seconds
  treat_missing_data  = "notBreaching"
}

# The single health signal: OK only while every alarm above is OK.
resource "aws_cloudwatch_composite_alarm" "health" {
  alarm_name        = "alarm-trades-health-${local.suffix}"
  alarm_description = "The trades pipeline is unhealthy: stale, slow, incomplete or lagging."
  alarm_rule = join(" OR ", [for alarm in [
    aws_cloudwatch_metric_alarm.staleness,
    aws_cloudwatch_metric_alarm.freshness,
    aws_cloudwatch_metric_alarm.completeness,
    aws_cloudwatch_metric_alarm.consumer_lag,
  ] : "ALARM(\"${alarm.alarm_name}\")"])
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
