output "advanced_json_payload_logging_metric_names" {
  description = "Names of the created custom metrics"
  value = {
    for k, v in google_logging_metric.advanced_json_payload_logging_metric : k => v.name
  }
}

output "advanced_json_payload_alert_policy_names" {
  description = "Names of the created individual alert policies"
  value = {
    for k, v in google_monitoring_alert_policy.advanced_json_payload_alert_policy : k => v.name
  }
}

output "advanced_json_combined_alert_policy_names" {
  description = "Names of the created combined alert policies"
  value = {
    for k, v in google_monitoring_alert_policy.advanced_json_combined_alert_policy : k => v.name
  }
}