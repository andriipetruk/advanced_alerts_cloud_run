# Advanced Alerts for Cloud Run

This Terraform module creates advanced alert policies for Google Cloud Run services and jobs based on custom log metrics. It allows you to define advanced JSON-based monitoring with custom labels and create both individual and combined alert policies.

## Features

- Create advanced log-based metrics with custom labels extracted from JSON payloads
- Create individual alert policies for metrics that need specific thresholds and conditions
- Create combined alert policies that can monitor multiple metrics together
- Support for Cloud Run services and jobs

## Example

```terraform
module "cloud_run_advanced_alerts" {
  source = "github.com/andriipetruk/advanced_alerts_cloud_run"

  project_id = "my-project-id"

  cloud_run_resource = {
    service_name = "my-service-name"
  }

  # Enable advanced JSON indicators
  enable_advanced_json_indicators = true

  # Define custom log-based metrics with label extraction
  advanced_json_payload_indicators = {
    database_errors = {
      description = "Counts database connection and query errors"
      filter      = <<EOT
          resource.type="cloud_run_revision"
          AND severity="ERROR"
          AND jsonPayload.message=~"database (connection|query) error"
        EOT
      label_extractors = {
        error_type = "REGEXP_EXTRACT(jsonPayload.message, \"database (connection|query) error\")"
      }
      metric_kind = "DELTA"
      value_type  = "INT64"
      labels = [
        {
          key         = "error_type"
          value_type  = "STRING"
          description = "Type of database error"
        }
      ]
      alert_condition = {
        duration        = "60s"
        threshold       = 1
        aligner         = "ALIGN_RATE"
        reducer         = "REDUCE_SUM"
        policy_name     = "Database-Error-Alert"
        policy_severity = "ERROR"
      }
    }
  }

  # Define combined alert policies
  advanced_json_combined_alert_policies = {
    api_issues = {
      display_name = "API-Issues-Alert"
      severity     = "WARNING"
      metrics      = ["grpc_errors"]
      condition_settings = {
        duration  = "300s"
        threshold = 5
      }
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| google | >= 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| google | >= 6.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_logging_metric.advanced_json_payload_logging_metric](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.advanced_json_combined_alert_policy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.advanced_json_payload_alert_policy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| advanced_json_combined_alert_policies | Map of alert policies that can combine multiple advanced metrics. | `map(object({...}))` | `{}` | no |
| advanced_json_payload_indicators | Map for advanced log based indicators using JSON payload with custom label extractors and metric descriptors. | `map(object({...}))` | `{}` | no |
| cloud_run_resource | One of either service name or job name which will dictate the Cloud Run resource to monitor. | `object({...})` | n/a | yes |
| enable_advanced_json_indicators | A flag to enable or disable the creation of advanced json indicators. | `bool` | `true` | no |
| notification_channels | List of notification channels to alert. | `list(string)` | `[]` | no |
| project_id | The GCP project ID. | `string` | n/a | yes |
| runbook_urls | URLs of markdown runbook files. | `object({...})` | `{...}` | no |

## Outputs

| Name | Description |
|------|-------------|
| advanced_json_combined_alert_policy_names | Names of the created combined alert policies |
| advanced_json_payload_alert_policy_names | Names of the created individual alert policies |
| advanced_json_payload_logging_metric_names | Names of the created custom metrics |
<!-- END_TF_DOCS -->