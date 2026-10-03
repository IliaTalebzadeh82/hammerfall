variable "project_id" {
  description = "Dedicated GCP project ID for this reference environment. Required even when disabled."
  type        = string
}

variable "region" {
  description = "Reference region; reviewed service mapping and costs use the Netherlands."
  type        = string
  default     = "europe-west4"
}

variable "environment" {
  type    = string
  default = "reference"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "Use a short lowercase environment name."
  }
}

variable "enable_reference_infrastructure" {
  description = "Explicit cost gate. The default produces no GCP resources or API changes."
  type        = bool
  default     = false
}

variable "admin_cidr" {
  description = "Operator public CIDR allowed to the GKE control endpoint; provide explicitly before enabling."
  type        = string
  default     = ""
  validation {
    condition     = !var.enable_reference_infrastructure || (can(cidrhost(var.admin_cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], var.admin_cidr))
    error_message = "Enabling the reference requires a bounded operator CIDR, not an Internet-wide range."
  }
}

variable "sql_tier" {
  type    = string
  default = "db-custom-2-7680"
}

variable "sql_availability_type" {
  type    = string
  default = "ZONAL"
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.sql_availability_type)
    error_message = "Use ZONAL or REGIONAL."
  }
}

variable "redis_tier" {
  type    = string
  default = "BASIC"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Use BASIC or STANDARD_HA."
  }
}

variable "redis_memory_gb" {
  type    = number
  default = 1
  validation {
    condition     = var.redis_memory_gb >= 1
    error_message = "Redis capacity must be at least 1 GiB."
  }
}

variable "enable_redis" {
  description = "Separate gate while Redis TLS/auth client integration remains unresolved."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_redis || var.enable_reference_infrastructure
    error_message = "Redis can be enabled only with the reference infrastructure."
  }
}

variable "enable_kafka" {
  description = "Separate cost gate for the managed Kafka cluster, topic and ACLs."
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_kafka || var.enable_reference_infrastructure
    error_message = "Kafka can be enabled only with the reference infrastructure."
  }
}
