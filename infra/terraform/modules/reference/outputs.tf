output "cluster_name" { value = google_container_cluster.app.name }
output "sql_private_ip" { value = google_sql_database_instance.authority.private_ip_address }
output "redis_host" { value = var.enable_redis ? google_redis_instance.derived[0].host : null }
output "artifact_repository" { value = google_artifact_registry_repository.images.id }
