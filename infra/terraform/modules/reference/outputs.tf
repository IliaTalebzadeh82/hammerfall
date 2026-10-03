output "cluster_name" { value = google_container_cluster.app.name }
output "sql_private_ip" { value = google_sql_database_instance.authority.private_ip_address }
output "redis_host" { value = var.enable_redis ? google_redis_instance.derived[0].host : null }
output "kafka_cluster_id" { value = var.enable_kafka ? google_managed_kafka_cluster.events[0].cluster_id : null }
output "sql_psa_dns_name" { value = google_dns_record_set.cloud_sql_private.name }
output "artifact_repository" { value = google_artifact_registry_repository.images.id }
