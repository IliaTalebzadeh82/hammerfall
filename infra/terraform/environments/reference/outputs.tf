output "activation_warning" {
  value = var.enable_reference_infrastructure ? "COST-BEARING INFRASTRUCTURE ENABLED; review plan before apply" : "No GCP resources configured; set enable_reference_infrastructure only after separate spending authorization"
}

output "cluster_name" {
  value = var.enable_reference_infrastructure ? module.reference[0].cluster_name : null
}

output "sql_private_ip" {
  value = var.enable_reference_infrastructure ? module.reference[0].sql_private_ip : null
}

output "redis_host" {
  value = var.enable_reference_infrastructure ? module.reference[0].redis_host : null
}

output "artifact_repository" {
  value = var.enable_reference_infrastructure ? module.reference[0].artifact_repository : null
}
