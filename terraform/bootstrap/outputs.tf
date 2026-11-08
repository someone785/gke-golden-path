output "state_bucket" {
  description = "本体と platform の backend.hcl に書くバケット名"
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "GitHub Actions の google-github-actions/auth に渡す workload_identity_provider"
  value       = google_iam_workload_identity_pool_provider.github.name
}
