mock_provider "google" {}

run "default_is_empty" {
  command = plan
  variables { project_id = "hammerfall-test-project" }
  assert {
    condition     = length(google_project_service.required) == 0 && length(module.reference) == 0
    error_message = "The default must create no GCP resources or API changes."
  }
}

run "core_excludes_redis_and_kafka" {
  command = plan
  variables {
    project_id                      = "hammerfall-test-project"
    admin_cidr                      = "203.0.113.10/32"
    enable_reference_infrastructure = true
  }
  assert {
    condition     = length(module.reference) == 1 && module.reference[0].kafka_cluster_id == null && module.reference[0].redis_host == null && !contains(keys(google_project_service.required), "managedkafka.googleapis.com")
    error_message = "Core reference must leave separately gated Redis and Kafka absent."
  }
}

run "kafka_requires_separate_gate" {
  command = plan
  variables {
    project_id                      = "hammerfall-test-project"
    admin_cidr                      = "203.0.113.10/32"
    enable_reference_infrastructure = true
    enable_kafka                    = true
  }
  assert {
    condition     = module.reference[0].kafka_cluster_id == "hammerfall-reference-events" && module.reference[0].redis_host == null && contains(keys(google_project_service.required), "managedkafka.googleapis.com")
    error_message = "Kafka's separate gate should model a cluster without enabling Redis."
  }
}

run "reject_open_operator_cidr" {
  command = plan
  variables {
    project_id                      = "hammerfall-test-project"
    admin_cidr                      = "0.0.0.0/0"
    enable_reference_infrastructure = true
  }
  expect_failures = [var.admin_cidr]
}
