# A separate gate is required because a managed broker has material standing cost.
# These IAM service accounts have no keys. Each GKE KSA may impersonate only its
# matching Kafka identity, giving the broker stable User:<email> ACL principals.
locals {
  kafka_roles = toset(["kafka-publisher", "kafka-audit", "kafka-projection"])
  kafka_account_suffix = {
    kafka-publisher  = "kpub"
    kafka-audit      = "kaudit"
    kafka-projection = "kproj"
  }
}

resource "google_service_account" "kafka_client" {
  for_each     = var.enable_kafka ? local.kafka_roles : toset([])
  account_id   = "hf-${var.environment}-${local.kafka_account_suffix[each.key]}"
  display_name = "Hammerfall ${each.key} Kafka client"
}

resource "google_service_account_iam_member" "kafka_ksa_link" {
  for_each           = google_service_account.kafka_client
  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[hammerfall/${each.key}]"
}

resource "google_project_iam_member" "kafka_connect" {
  for_each = google_service_account.kafka_client
  project  = var.project_id
  role     = "roles/managedkafka.client"
  member   = "serviceAccount:${each.value.email}"
}

# The linked GSA is the ADC identity in Kafka pods. The CSI add-on may use the
# KSA principal directly; both paths are scoped to the same required secrets.
resource "google_secret_manager_secret_iam_member" "kafka_database_url_read" {
  for_each  = google_service_account.kafka_client
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.email}"
}

resource "google_secret_manager_secret_iam_member" "kafka_secret_key_read" {
  for_each  = google_service_account.kafka_client
  project   = var.project_id
  secret_id = google_secret_manager_secret.secret_key_base.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.email}"
}

resource "google_secret_manager_secret_iam_member" "kafka_sql_ca_read" {
  for_each  = google_service_account.kafka_client
  project   = var.project_id
  secret_id = google_secret_manager_secret.cloud_sql_ca_bundle.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.email}"
}

resource "google_secret_manager_secret_iam_member" "kafka_projection_redis_ca_read" {
  count     = var.enable_kafka ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.redis_ca_bundle.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.kafka_client["kafka-projection"].email}"
}

resource "google_service_account" "kafka_acl_sentinel" {
  count        = var.enable_kafka ? 1 : 0
  account_id   = "hf-${var.environment}-kacl"
  display_name = "Kafka ACL default-deny sentinel; no pod or key binding"
}

resource "google_managed_kafka_cluster" "events" {
  count      = var.enable_kafka ? 1 : 0
  project    = var.project_id
  cluster_id = "${local.name}-events"
  location   = var.region
  labels     = local.labels

  capacity_config {
    vcpu_count   = "3"
    memory_bytes = "12Gi"
  }

  gcp_config {
    access_config {
      network_configs { subnet = google_compute_subnetwork.gke.id }
    }
  }
}

resource "google_managed_kafka_topic" "auction_events" {
  count              = var.enable_kafka ? 1 : 0
  project            = var.project_id
  location           = var.region
  cluster            = google_managed_kafka_cluster.events[0].cluster_id
  topic_id           = "hammerfall.auction-events.v1"
  partition_count    = 3
  replication_factor = 3
}

resource "google_managed_kafka_acl" "cluster" {
  count    = var.enable_kafka ? 1 : 0
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "cluster"

  acl_entries {
    principal       = "User:${google_service_account.kafka_client["kafka-publisher"].email}"
    operation       = "IDEMPOTENT_WRITE"
    permission_type = "ALLOW"
    host            = "*"
  }
  acl_entries {
    principal       = "User:${google_service_account.kafka_acl_sentinel[0].email}"
    operation       = "ALL"
    permission_type = "ALLOW"
    host            = "*"
  }
}

resource "google_managed_kafka_acl" "topic" {
  count    = var.enable_kafka ? 1 : 0
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "topic/hammerfall.auction-events.v1"

  acl_entries {
    principal       = "User:${google_service_account.kafka_client["kafka-publisher"].email}"
    operation       = "WRITE"
    permission_type = "ALLOW"
    host            = "*"
  }
  dynamic "acl_entries" {
    for_each = toset(["kafka-audit", "kafka-projection"])
    content {
      principal       = "User:${google_service_account.kafka_client[acl_entries.value].email}"
      operation       = "READ"
      permission_type = "ALLOW"
      host            = "*"
    }
  }
  depends_on = [google_managed_kafka_topic.auction_events]
}

resource "google_managed_kafka_acl" "group" {
  for_each = var.enable_kafka ? {
    kafka-audit      = "hammerfall.audit.v1"
    kafka-projection = "hammerfall.projection.v1"
  } : {}
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "consumerGroup/${each.value}"

  acl_entries {
    principal       = "User:${google_service_account.kafka_client[each.key].email}"
    operation       = "READ"
    permission_type = "ALLOW"
    host            = "*"
  }
}

# The service defaults to allow when no ACL matches a resource. Matching
# wildcard ACLs give unknown topics/groups/transactional IDs a deny baseline.
resource "google_managed_kafka_acl" "all_topics" {
  count    = var.enable_kafka ? 1 : 0
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "allTopics"
  acl_entries {
    principal       = "User:${google_service_account.kafka_acl_sentinel[0].email}"
    operation       = "ALL"
    permission_type = "ALLOW"
    host            = "*"
  }
}

resource "google_managed_kafka_acl" "all_groups" {
  count    = var.enable_kafka ? 1 : 0
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "allConsumerGroups"
  acl_entries {
    principal       = "User:${google_service_account.kafka_acl_sentinel[0].email}"
    operation       = "ALL"
    permission_type = "ALLOW"
    host            = "*"
  }
}

resource "google_managed_kafka_acl" "all_transactional_ids" {
  count    = var.enable_kafka ? 1 : 0
  project  = var.project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.events[0].cluster_id
  acl_id   = "allTransactionalIds"
  acl_entries {
    principal       = "User:${google_service_account.kafka_acl_sentinel[0].email}"
    operation       = "ALL"
    permission_type = "ALLOW"
    host            = "*"
  }
}
