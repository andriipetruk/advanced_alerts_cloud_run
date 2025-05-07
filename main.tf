# Advanced alerts for Cloud Run services
# This module creates custom log-based metrics and alert policies for Cloud Run

locals {
  metric_root = "run.googleapis.com"
  is_job      = var.cloud_run_resource.job_name != null

  metric_root_prefix = local.is_job ? "${local.metric_root}/job" : local.metric_root

  user_metric_root_prefix = "logging.googleapis.com/user"

  resource_type  = local.is_job ? "cloud_run_job" : "cloud_run_revision"
  resource_label = local.is_job ? "job_name" : "service_name"
  resource_value = local.is_job ? var.cloud_run_resource.job_name : var.cloud_run_resource.service_name

  default_group_by_fields = ["resource.label.location"]

  second = 1
  minute = 60 * local.second
  hour   = 60 * local.minute
  day    = 24 * local.hour
}

# Advanced log based metrics with custom labels
resource "google_logging_metric" "advanced_json_payload_logging_metric" {
  for_each = var.advanced_log_based_json_indicators

  project = var.project_id

  name        = "${local.resource_value}-${each.key}"
  description = each.value.description != null ? each.value.description : "Custom metric for ${each.key}"

  # Use the dynamic resource type
  filter = replace(
    each.value.filter,
    "resource.type=\"cloud_run_revision\"",
    "resource.type=\"${local.resource_type}\""
  )

  metric_descriptor {
    metric_kind = each.value.metric_kind
    value_type  = each.value.value_type
    dynamic "labels" {
      for_each = each.value.labels
      content {
        key         = labels.value.key
        value_type  = labels.value.value_type
        description = labels.value.description
      }
    }
  }

  label_extractors = each.value.label_extractors
}

# Alert policies for individual advanced JSON metrics
# This creates alerts for metrics with alert_condition defined directly in the metric
resource "google_monitoring_alert_policy" "advanced_json_payload_alert_policy" {
  for_each = {
    for k, v in var.advanced_log_based_json_indicators : k => v
    if v.alert_condition != null && var.enable_advanced_log_based_json_indicators
  }

  project = var.project_id

  display_name = each.value.alert_condition.policy_name != null ? each.value.alert_condition.policy_name : "Metric-${local.resource_value}-${each.key}"
  severity     = each.value.alert_condition.policy_severity
  combiner     = "OR"

  conditions {
    display_name = "${each.key} monitoring"

    condition_threshold {
      filter = each.value.alert_condition.filter != null ? replace(each.value.alert_condition.filter, "resource.type=\"cloud_run_revision\"", "resource.type=\"${local.resource_type}\"") : <<-EOT
         metric.type="${local.user_metric_root_prefix}/${local.resource_value}-${each.key}"
         resource.type="${local.resource_type}"
         resource.label.${local.resource_label}="${local.resource_value}"
       EOT

      duration        = each.value.alert_condition.duration
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.alert_condition.threshold

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = each.value.alert_condition.aligner
        cross_series_reducer = each.value.alert_condition.reducer
        group_by_fields      = each.value.alert_condition.group_by_fields != null ? each.value.alert_condition.group_by_fields : local.default_group_by_fields
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "${local.day}s"

    notification_channel_strategy {
      renotify_interval = "${local.day}s"
    }
  }

  dynamic "documentation" {
    for_each = each.value.alert_condition.runbook_url != null ? [1] : (var.runbook_urls.json_based_logs != null ? [1] : [])

    content {
      content   = each.value.alert_condition.runbook_url != null ? each.value.alert_condition.runbook_url : var.runbook_urls.json_based_logs
      mime_type = "text/markdown"
    }
  }

  notification_channels = var.notification_channels_non_paging

  depends_on = [
    google_logging_metric.advanced_json_payload_logging_metric
  ]
}

# Alert policies for combined advanced JSON metrics
# This creates policies that can monitor multiple metrics in a single alert
resource "google_monitoring_alert_policy" "advanced_json_combined_alert_policy" {
  for_each = var.enable_advanced_log_based_json_indicators ? var.advanced_json_alert_policies : {}

  project = var.project_id

  display_name = each.value.display_name
  severity     = each.value.severity
  combiner     = "OR"

  # If a custom filter is provided, use a single condition with that filter
  dynamic "conditions" {
    for_each = each.value.filter != null ? [1] : []
    content {
      display_name = "Combined condition"

      condition_threshold {
        filter = replace(
          each.value.filter,
          "resource.type=\"cloud_run_revision\"",
          "resource.type=\"${local.resource_type}\""
        )

        duration        = each.value.condition_settings != null && each.value.condition_settings.duration != null ? each.value.condition_settings.duration : "60s"
        comparison      = "COMPARISON_GT"
        threshold_value = each.value.condition_settings != null && each.value.condition_settings.threshold != null ? each.value.condition_settings.threshold : 1

        aggregations {
          alignment_period     = "60s"
          per_series_aligner   = each.value.condition_settings != null && each.value.condition_settings.aligner != null ? each.value.condition_settings.aligner : "ALIGN_RATE"
          cross_series_reducer = each.value.condition_settings != null && each.value.condition_settings.reducer != null ? each.value.condition_settings.reducer : "REDUCE_SUM"
          group_by_fields      = each.value.condition_settings != null && each.value.condition_settings.group_by_fields != null ? each.value.condition_settings.group_by_fields : local.default_group_by_fields
        }

        trigger {
          count = 1
        }
      }
    }
  }

  # If no custom filter, create a condition for each metric in the metrics list
  dynamic "conditions" {
    for_each = each.value.filter == null ? each.value.metrics : []

    content {
      display_name = "${conditions.value} monitoring"

      condition_threshold {
        filter = <<-EOT
           metric.type="${local.user_metric_root_prefix}/${local.resource_value}-${conditions.value}"
           resource.type="${local.resource_type}"
           resource.label.${local.resource_label}="${local.resource_value}"
         EOT

        duration        = each.value.condition_settings != null && each.value.condition_settings.duration != null ? each.value.condition_settings.duration : "60s"
        comparison      = "COMPARISON_GT"
        threshold_value = each.value.condition_settings != null && each.value.condition_settings.threshold != null ? each.value.condition_settings.threshold : 1

        aggregations {
          alignment_period     = "60s"
          per_series_aligner   = each.value.condition_settings != null && each.value.condition_settings.aligner != null ? each.value.condition_settings.aligner : "ALIGN_RATE"
          cross_series_reducer = each.value.condition_settings != null && each.value.condition_settings.reducer != null ? each.value.condition_settings.reducer : "REDUCE_SUM"
          group_by_fields      = each.value.condition_settings != null && each.value.condition_settings.group_by_fields != null ? each.value.condition_settings.group_by_fields : local.default_group_by_fields
        }

        trigger {
          count = 1
        }
      }
    }
  }

  alert_strategy {
    auto_close = "${local.day}s"

    notification_channel_strategy {
      renotify_interval = "${local.day}s"
    }
  }

  dynamic "documentation" {
    for_each = each.value.runbook_url != null ? [1] : (var.runbook_urls.json_based_logs != null ? [1] : [])

    content {
      content   = each.value.runbook_url != null ? each.value.runbook_url : var.runbook_urls.json_based_logs
      mime_type = "text/markdown"
    }
  }

  notification_channels = var.notification_channels_non_paging

  depends_on = [
    google_logging_metric.advanced_json_payload_logging_metric
  ]
}
