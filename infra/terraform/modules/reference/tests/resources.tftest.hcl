mock_provider "google" {}

run "optional_services_absent" {
  command = plan
  variables {
    project_id            = "hammerfall-test-project"
    region                = "europe-west4"
    environment           = "reference"
    admin_cidr            = "203.0.113.10/32"
    sql_tier              = "db-custom-2-7680"
    sql_availability_type = "ZONAL"
    redis_tier            = "BASIC"
    redis_memory_gb       = 1
    enable_redis          = false
    enable_kafka          = false
  }
  assert {
    condition     = length(google_redis_instance.derived) == 0 && length(google_managed_kafka_cluster.events) == 0 && length(google_managed_kafka_topic.auction_events) == 0 && length(google_managed_kafka_acl.topic) == 0
    error_message = "Optional Redis and Kafka resources must be absent."
  }
}

run "kafka_models_topic_and_acl_boundary" {
  command = plan
  variables {
    project_id            = "hammerfall-test-project"
    region                = "europe-west4"
    environment           = "reference"
    admin_cidr            = "203.0.113.10/32"
    sql_tier              = "db-custom-2-7680"
    sql_availability_type = "ZONAL"
    redis_tier            = "BASIC"
    redis_memory_gb       = 1
    enable_redis          = false
    enable_kafka          = true
  }
  assert {
    condition     = length(google_managed_kafka_cluster.events) == 1 && length(google_managed_kafka_topic.auction_events) == 1 && length(google_managed_kafka_acl.topic) == 1 && length(google_managed_kafka_acl.group) == 2 && length(google_managed_kafka_acl.all_topics) == 1 && length(google_service_account.kafka_client) == 3
    error_message = "Kafka gate must include cluster, topic, two groups, ACL baseline and distinct client identities."
  }
}
