output "cluster_name" {
  description = "gcloud container clusters get-credentials に渡すクラスタ名"
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "クラスタのゾーン"
  value       = google_container_cluster.this.location
}

output "artifact_registry" {
  description = "イメージの push 先 (フェーズ 3)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}
