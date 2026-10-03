# Deliberately empty by default. Enabling this module is a separate, cost-bearing act.
locals {
  required_apis = toset(concat([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
  ], var.enable_kafka ? ["managedkafka.googleapis.com"] : []))
}

resource "google_project_service" "required" {
  for_each           = var.enable_reference_infrastructure ? local.required_apis : toset([])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

module "reference" {
  count  = var.enable_reference_infrastructure ? 1 : 0
  source = "../../modules/reference"

  project_id            = var.project_id
  region                = var.region
  environment           = var.environment
  admin_cidr            = var.admin_cidr
  sql_tier              = var.sql_tier
  sql_availability_type = var.sql_availability_type
  redis_tier            = var.redis_tier
  redis_memory_gb       = var.redis_memory_gb
  enable_redis          = var.enable_redis
  enable_kafka          = var.enable_kafka

  depends_on = [google_project_service.required]
}
