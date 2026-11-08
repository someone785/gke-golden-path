# ---------------------------------------------------------------
# ノード用のサービスアカウント
# ---------------------------------------------------------------
# 既定の Compute Engine のサービスアカウントは権限 (編集者) が広すぎるので、最小限の専用のものを作る
resource "google_service_account" "gke_node" {
  account_id   = "gke-node"
  display_name = "GKE node"

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "gke_node" {
  for_each = toset([
    # GKE のノードに最低限必要な権限 (ログ・指標の書き込みなど) をまとめたロール
    "roles/container.defaultNodeServiceAccount",
    # 自分でビルドしたイメージ (フェーズ 3) を Artifact Registry から取得する
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# ---------------------------------------------------------------
# GKE クラスタ (ゾーン型、ADR 0002)
# ---------------------------------------------------------------
# trivy:ignore:AVD-GCP-0061 コントロールプレーンの接続元は IP で絞らず、IAM の認証に任せる。手元の IP が変わるため
resource "google_container_cluster" "this" {
  name     = "gke-golden-path"
  location = var.zone # 【ゾーンを指定するとゾーン型になる。リージョンに変えると作り直し】

  # 【作っては消す運用のため、削除保護を外す】provider の既定は true で、そのままでは destroy できない
  deletion_protection = false

  # ノードは下の node_pool で管理する。既定のノードプールは作らない。
  # initial_node_count も node_config も書かないと、既定のノードプールなしで作られる
  # (GKE 1.36.4-gke.1469000 以上が必要。2026-11-08 に作ったクラスタは 1.36.4-gke.2046003)。
  # 【古い版では remove_default_node_pool = true と initial_node_count = 1 が必要】provider v8.10 では非推奨

  network    = google_compute_network.this.id
  subnetwork = google_compute_subnetwork.gke.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # ノードに外部 IP を付けない。コントロールプレーンは公開のエンドポイントのまま (手元から kubectl を使う)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # Pod から GCP の API へは、鍵ファイルではなく Workload Identity で認証する (CLAUDE.md)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # 監視は OTel Demo 同梱の部品 (Prometheus、Grafana、Jaeger) が担当する。
  # Cloud Logging / Monitoring にはシステムの部品だけを送り、役割の重複と料金を抑える。
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------
# ノードプール (Spot)
# ---------------------------------------------------------------
resource "google_container_node_pool" "spot" {
  name     = "spot"
  location = var.zone
  cluster  = google_container_cluster.this.name

  node_count = var.node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    # 【Spot はいつでも回収されうる】回収されると Pod が止まり、ノードが作り直されるまでデモが落ちる
    spot         = true
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-balanced"

    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"] # 権限は IAM のロールで絞る

    # Pod が Workload Identity を使えるよう、GKE のメタデータサーバーを使う
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [google_project_iam_member.gke_node]
}
