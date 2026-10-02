output "state_bucket_name" {
  value = var.enable_state_bucket ? google_storage_bucket.terraform_state[0].name : null
}
