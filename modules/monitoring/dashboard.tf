locals {
  dashboard_region = data.aws_region.current.region

  metric_widget = {
    type   = "metric"
    width  = 12
    height = 6
  }
}

resource "aws_cloudwatch_dashboard" "trades" {
  dashboard_name = "dashboard-trades-${local.suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "alarm"
        width  = 24
        height = 3
        properties = {
          title = "Health"
          alarms = [
            aws_cloudwatch_composite_alarm.health.arn,
            aws_cloudwatch_metric_alarm.staleness.arn,
            aws_cloudwatch_metric_alarm.freshness.arn,
            aws_cloudwatch_metric_alarm.completeness.arn,
            aws_cloudwatch_metric_alarm.consumer_lag.arn,
          ]
        }
      },
      merge(local.metric_widget, {
        properties = {
          title       = "Freshness: p99 trade time to row in PostgreSQL (s)"
          region      = local.dashboard_region
          stat        = "Maximum"
          period      = 60
          metrics     = [[var.metrics_namespace, "IngestLatencyP99"]]
          annotations = { horizontal = [{ label = "target", value = var.freshness_target_seconds }] }
        }
      }),
      merge(local.metric_widget, {
        properties = {
          title       = "Seconds since the last trade landed"
          region      = local.dashboard_region
          stat        = "Maximum"
          period      = 60
          metrics     = [[var.metrics_namespace, "SecondsSinceLastTrade"]]
          annotations = { horizontal = [{ label = "stopped", value = var.staleness_threshold_seconds }] }
        }
      }),
      merge(local.metric_widget, {
        properties = {
          title  = "Trades landed per minute, and trades missing in the last 10 minutes"
          region = local.dashboard_region
          stat   = "Maximum"
          period = 60
          metrics = [
            [var.metrics_namespace, "TradesIngested"],
            [var.metrics_namespace, "MissingTrades", { yAxis = "right" }],
          ]
        }
      }),
      merge(local.metric_widget, {
        properties = {
          title       = "Consumer group lag (s)"
          region      = local.dashboard_region
          stat        = "Maximum"
          period      = 60
          metrics     = [concat(["AWS/Kafka", "EstimatedMaxTimeLag"], flatten([for k, v in local.kafka_lag_dimensions : [k, v]]))]
          annotations = { horizontal = [{ label = "alarm", value = var.consumer_lag_threshold_seconds }] }
        }
      }),
      merge(local.metric_widget, {
        properties = {
          title  = "Kafka bytes in, all brokers (B/s)"
          region = local.dashboard_region
          period = 60
          # SEARCH keeps the widget correct whatever the broker count.
          metrics = [[{
            expression = "SUM(SEARCH('{AWS/Kafka,\"Cluster Name\",\"Broker ID\"} MetricName=\"BytesInPerSec\" \"Cluster Name\"=\"${var.msk_cluster_name}\"', 'Average', 60))"
            label      = "bytes in"
          }]]
        }
      }),
      merge(local.metric_widget, {
        properties = {
          title  = "PostgreSQL connections and write IOPS"
          region = local.dashboard_region
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_identifier],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.rds_instance_identifier, { yAxis = "right" }],
          ]
        }
      }),
    ]
  })
}
