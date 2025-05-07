variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "cloud_run_resource" {
  description = "One of either service name or job name which will dictate the Cloud Run resource to monitor."
  type = object({
    service_name = optional(string)
    job_name     = optional(string)
  })
  validation {
    condition     = length([for k, v in var.cloud_run_resource : v if v != null]) == 1
    error_message = "Either service_name or job_name must be defined"
  }
}

variable "runbook_urls" {
  description = "URLs of markdown runbook files."
  type = object({
    json_based_logs = optional(string)
  })
  default = {
    json_based_logs = null
  }
}

variable "notification_channels_non_paging" {
  description = "List of notification channels to alert."
  type        = list(string)
  default     = []
}


variable "notification_channels" {
  description = "List of notification channels to alert."
  type        = list(string)
  default     = []
}

variable "enable_advanced_log_based_json_indicators" {
  type        = bool
  description = "A flag to enable or disable the creation of advanced log based JSON indicators."
  default     = false
}

# Advanced json metrics with direct filter definitions
variable "advanced_log_based_json_indicators" {
  description = "Map for advanced log based indicators using JSON payload with custom label extractors and metric descriptors."
  type = map(object({
    name             = string
    description      = optional(string)
    filter           = string
    label_extractors = map(string)
    metric_kind      = string
    value_type       = string
    labels = list(object({
      key         = string
      value_type  = string
      description = string
    }))
    # Alert condition for this specific metric
    alert_condition = optional(object({
      duration        = string
      threshold       = number
      aligner         = string
      reducer         = string
      filter          = optional(string)
      group_by_fields = optional(list(string))
      policy_name     = optional(string)
      policy_severity = optional(string, "ERROR")
      runbook_url     = optional(string)
    }))
  }))
  default = {}

  # Validations inspired by:
  # - Log severity levels: https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#logseverity
  # - Metric naming conventions: https://cloud.google.com/logging/docs/logs-based-metrics/naming-restrictions
  # - Metric kinds and value types: https://cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.metricDescriptors

  # Validation for metric_kind
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      contains(["GAUGE", "DELTA", "CUMULATIVE"], v.metric_kind)
    ])
    error_message = "The 'metric_kind' field must be one of: 'GAUGE', 'DELTA', 'CUMULATIVE'."
  }

  # Validation for value_type
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      contains(["BOOL", "INT64", "DOUBLE", "STRING", "DISTRIBUTION", "MONEY"], v.value_type)
    ])
    error_message = "The 'value_type' field must be one of: 'BOOL', 'INT64', 'DOUBLE', 'STRING', 'DISTRIBUTION', 'MONEY'."
  }

  # Validation for policy_severity (only when alert_condition exists)
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      v.alert_condition == null ? true : (
        v.alert_condition.policy_severity == null ||
        contains(["INFO", "WARNING", "ERROR", "CRITICAL"], v.alert_condition.policy_severity)
      )
    ])
    error_message = "The 'policy_severity' must be one of: 'INFO', 'WARNING', 'ERROR', 'CRITICAL'."
  }

  # Validation for metric name
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", v.name)) &&
      length(v.name) <= 100
    ])
    error_message = "Metric name must start with a letter, contain only alphanumeric characters and underscores, and be <= 100 chars."
  }

  # Separate validation for description
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      v.description == null ? true : length(v.description) <= 256
    ])
    error_message = "Description must be <= 256 chars."
  }

  # Validation for keys and label names
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators : (
        can(regex("^[a-zA-Z0-9-_]+$", k)) &&
        length(keys(v.label_extractors)) == length(distinct(keys(v.label_extractors))) &&
        alltrue([for label_key in keys(v.label_extractors) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", label_key))]) &&
        alltrue([for label in v.labels : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", label.key))])
      )
    ])
    error_message = <<-EOT
       Validation failed for advanced_log_based_json_indicators:
       - Indicator keys must contain only alphanumeric characters, dashes, or underscores.
       - Label keys must be unique, start with a letter, and contain only alphanumeric characters and underscores.
       - All label keys must be valid Google Cloud label names.
     EOT
  }

  # Validation for alert conditions (only when alert_condition exists)
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      v.alert_condition == null ? true : (
        can(regex("^[0-9]+[smhd]$", v.alert_condition.duration)) &&
        v.alert_condition.threshold >= 0 &&
        (v.alert_condition.policy_name == null || can(regex("^[a-zA-Z0-9-_ ]+$", v.alert_condition.policy_name)))
      )
    ])
    error_message = <<-EOT
       Validation failed for alert_condition:
       - duration must be a value like "60s", "5m", "1h", or "1d".
       - threshold must be zero or positive.
       - policy_name (if provided) must contain only alphanumeric characters, spaces, dashes, or underscores.
     EOT
  }

  # Validation for label consistency
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators : (
        length(v.labels) > 0 &&
        length(v.labels) == length(v.label_extractors) &&
        alltrue([for label in v.labels : contains(keys(v.label_extractors), label.key)])
      )
    ])
    error_message = <<-EOT
       Validation failed for label consistency:
       - At least one label must be defined.
       - Each label must have a corresponding label_extractor.
       - Each label_extractor must have a corresponding label definition.
     EOT
  }

  # Validation for aligners and reducers (only when alert_condition exists)
  validation {
    condition = alltrue([
      for k, v in var.advanced_log_based_json_indicators :
      v.alert_condition == null ? true : (
        can(regex("^ALIGN_[A-Z_]+$", v.alert_condition.aligner)) &&
        can(regex("^REDUCE_[A-Z_]+$", v.alert_condition.reducer))
      )
    ])
    error_message = <<-EOT
       Validation failed for aligner and reducer:
       - aligner must start with "ALIGN_" followed by uppercase letters and underscores.
       - reducer must start with "REDUCE_" followed by uppercase letters and underscores.
     EOT
  }
}

# Advanced combined alert policies
variable "advanced_json_alert_policies" {
  description = "Map of alert policies that can combine multiple advanced metrics."
  type = map(object({
    display_name = string
    severity     = optional(string, "ERROR")
    # List of metrics to include in this policy (optional if filter is provided)
    metrics = optional(list(string), [])
    # Custom filter (overrides automatic metric list creation)
    filter = optional(string)
    # Optional custom settings for all metrics in this policy
    condition_settings = optional(object({
      duration        = optional(string, "60s")
      threshold       = optional(number, 1)
      aligner         = optional(string, "ALIGN_RATE")
      reducer         = optional(string, "REDUCE_SUM")
      group_by_fields = optional(list(string))
    }))
    # Runbook URL for this policy
    runbook_url = optional(string)
  }))
  default = {}

  # Basic validation
  validation {
    condition = alltrue([
      for k, v in var.advanced_json_alert_policies : (
        can(regex("^[a-zA-Z0-9-_]+$", k)) &&
        contains(["INFO", "WARNING", "ERROR", "CRITICAL"], v.severity) &&
        (v.condition_settings == null || (
          v.condition_settings.duration == null || can(regex("^[0-9]+[smhd]$", v.condition_settings.duration))
        ))
      )
    ])
    error_message = <<-EOT
       Validation failed for advanced_json_alert_policies:
       - Policy keys must contain only alphanumeric characters, dashes, or underscores.
       - Severity must be one of: 'INFO', 'WARNING', 'ERROR', 'CRITICAL'.
       - Duration (if provided) must be a value like "60s", "5m", "1h", or "1d".
     EOT
  }

  # Validation to require either metrics or filter
  validation {
    condition = alltrue([
      for k, v in var.advanced_json_alert_policies : (
        length(v.metrics) > 0 || v.filter != null
      )
    ])
    error_message = "Each policy must either specify a list of metrics or provide a custom filter."
  }
}
