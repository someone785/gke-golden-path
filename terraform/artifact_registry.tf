# 自分でビルドしたイメージ (フェーズ 3 のゴールデンパスのサービス) を置く。
# OTel Demo の公開イメージは、ここには置かない (CLAUDE.md)。
resource "google_artifact_registry_repository" "images" {
  repository_id = "images"
  location      = var.region
  format        = "DOCKER"
  description   = "ゴールデンパスのサービスのイメージ"

  # 古いイメージがたまり続けないよう、最新の 10 個だけを残す
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.this]
}
