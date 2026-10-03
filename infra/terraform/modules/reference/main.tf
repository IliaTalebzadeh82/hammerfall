locals {
  name = "hammerfall-${var.environment}"
  labels = {
    project     = "hammerfall"
    environment = var.environment
    managed_by  = "terraform"
  }
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_compute_network" "main" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  name                     = "${local.name}-gke"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = "10.40.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${local.name}-pods"
    ip_cidr_range = "10.44.0.0/16"
  }
  secondary_ip_range {
    range_name    = "${local.name}-services"
    ip_cidr_range = "10.45.0.0/20"
  }
}

resource "google_compute_router" "egress" {
  name    = "${local.name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "egress" {
  name                               = "${local.name}-nat"
  router                             = google_compute_router.egress.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_global_address" "private_services" {
  name          = "${local.name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  address       = "10.48.0.0"
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${local.name}-images"
  description   = "Hammerfall API and web container images"
  format        = "DOCKER"
  labels        = local.labels
}

resource "google_service_account" "gke_nodes" {
  account_id   = "${local.name}-nodes"
  display_name = "Hammerfall GKE node identity"
}

resource "google_project_iam_member" "gke_node_base" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "gke_image_pull" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "app" {
  name                = "${local.name}-gke"
  location            = var.region
  enable_autopilot    = true
  deletion_protection = true
  network             = google_compute_network.main.id
  subnetwork          = google_compute_subnetwork.gke.id
  networking_mode     = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "${local.name}-pods"
    services_secondary_range_name = "${local.name}-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.admin_cidr
      display_name = "operator"
    }
  }

  release_channel { channel = "REGULAR" }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  secret_manager_config { enabled = true }
  gateway_api_config { channel = "CHANNEL_STANDARD" }

  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [google_project_iam_member.gke_node_base, google_artifact_registry_repository_iam_member.gke_image_pull]
}

resource "google_sql_database_instance" "authority" {
  name                = "${local.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_18"
  deletion_protection = true

  settings {
    tier                        = var.sql_tier
    edition                     = "ENTERPRISE"
    availability_type           = var.sql_availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = 20
    disk_autoresize             = true
    deletion_protection_enabled = true
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                     = false
      private_network                  = google_compute_network.main.id
      ssl_mode                         = "ENCRYPTED_ONLY"
      server_ca_mode                   = "GOOGLE_MANAGED_CAS_CA"
      server_certificate_rotation_mode = "AUTOMATIC_ROTATION_DURING_MAINTENANCE"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "app" {
  name     = "hammerfall_production"
  instance = google_sql_database_instance.authority.name
}

resource "google_dns_managed_zone" "cloud_sql_private" {
  name        = "${local.name}-sql-psa"
  dns_name    = "sql-psa.goog."
  description = "Private Cloud SQL PSA certificate hostname resolution"
  visibility  = "private"
  private_visibility_config {
    networks { network_url = google_compute_network.main.id }
  }
}

resource "google_dns_record_set" "cloud_sql_private" {
  managed_zone = google_dns_managed_zone.cloud_sql_private.name
  name         = "${trimsuffix(one([for entry in google_sql_database_instance.authority.dns_names : entry.name if endswith(trimsuffix(entry.name, "."), ".sql-psa.goog")]), ".")}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_sql_database_instance.authority.private_ip_address]
}

# Redis remains derived queue/projection infrastructure. Authentication and
# client TLS integration need completion before this reference can be applied.
resource "google_redis_instance" "derived" {
  count                   = var.enable_redis ? 1 : 0
  name                    = "${local.name}-redis"
  region                  = var.region
  tier                    = var.redis_tier
  memory_size_gb          = var.redis_memory_gb
  redis_version           = "REDIS_7_2"
  authorized_network      = google_compute_network.main.id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  auth_enabled            = false
  labels                  = local.labels
  deletion_protection     = true

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = "${local.name}-database-url"
  labels    = local.labels
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
}

resource "google_secret_manager_secret" "secret_key_base" {
  secret_id = "${local.name}-secret-key-base"
  labels    = local.labels
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
}

resource "google_secret_manager_secret" "cloud_sql_ca_bundle" {
  secret_id = "${local.name}-cloud-sql-ca-bundle"
  labels    = local.labels
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
}

resource "google_secret_manager_secret" "redis_ca_bundle" {
  secret_id = "${local.name}-redis-ca-bundle"
  labels    = local.labels
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
}

locals {
  secret_readers = toset(["api", "worker", "closer", "db-prepare", "kafka-publisher", "kafka-audit", "kafka-projection"])
  redis_readers  = toset(["api", "worker", "kafka-projection"])
  workload_principals = {
    for sa in local.secret_readers : sa => "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/hammerfall/sa/${sa}"
  }
}

resource "google_secret_manager_secret_iam_member" "cloud_sql_ca_read" {
  for_each  = local.workload_principals
  project   = var.project_id
  secret_id = google_secret_manager_secret.cloud_sql_ca_bundle.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

resource "google_secret_manager_secret_iam_member" "redis_ca_read" {
  for_each  = { for sa, principal in local.workload_principals : sa => principal if contains(local.redis_readers, sa) }
  project   = var.project_id
  secret_id = google_secret_manager_secret.redis_ca_bundle.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

resource "google_secret_manager_secret_iam_member" "database_url_read" {
  for_each  = local.workload_principals
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}

resource "google_secret_manager_secret_iam_member" "secret_key_read" {
  for_each  = local.workload_principals
  project   = var.project_id
  secret_id = google_secret_manager_secret.secret_key_base.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value
}
