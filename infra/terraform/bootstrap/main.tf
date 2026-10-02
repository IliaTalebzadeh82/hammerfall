# Bootstrap runs with local state before the GCS backend exists. Never apply
# without a separate spending authorization and an explicit project/bucket.
resource "google_storage_bucket" "terraform_state" {
  count                       = var.enable_state_bucket ? 1 : 0
  name                        = var.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels = {
    project    = "hammerfall"
    managed_by = "terraform"
    purpose    = "terraform-state"
  }
  versioning { enabled = true }
  lifecycle { prevent_destroy = true }
}
