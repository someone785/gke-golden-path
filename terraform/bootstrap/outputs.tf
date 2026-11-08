output "state_bucket" {
  description = "本体と platform の backend.hcl に書くバケット名"
  value       = google_storage_bucket.tfstate.name
}
