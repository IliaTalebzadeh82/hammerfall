variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west4"
}
variable "bucket_name" {
  type    = string
  default = ""
  validation {
    condition     = !var.enable_state_bucket || length(var.bucket_name) >= 3
    error_message = "Set an explicit globally unique bucket name before enabling bootstrap."
  }
}
variable "enable_state_bucket" {
  description = "Explicit cost gate; never enable without separate spending authorization."
  type        = bool
  default     = false
}
