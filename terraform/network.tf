# ---------------------------------------------------------------
# VPC とサブネット
# ---------------------------------------------------------------
# 自動モードの VPC は全リージョンにサブネットを作るので、使うリージョンだけのカスタムモードにする
resource "google_compute_network" "this" {
  name                    = "gke-golden-path"
  auto_create_subnetworks = false

  depends_on = [google_project_service.this]
}

# trivy:ignore:AVD-GCP-0029 VPC フローログは料金がかかり、学習用の環境では見る予定がないため
resource "google_compute_subnetwork" "gke" {
  name    = "gke-${var.region}"
  region  = var.region
  network = google_compute_network.this.id

  # ノードの IP
  ip_cidr_range = "10.0.0.0/20"

  # VPC ネイティブのクラスタ用に、Pod と Service の範囲を別に持つ
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }

  # ノードに外部 IP がないので、Google の API (Artifact Registry など) へは内部の経路で出る
  private_ip_google_access = true
}

# ---------------------------------------------------------------
# Cloud NAT
# ---------------------------------------------------------------
# ノードは外部 IP を持たない (gke.tf の enable_private_nodes)。
# OTel Demo のイメージは ghcr.io などにあるので、外へ出る経路として NAT を置く。
# 【NAT の料金は未確認】使っていない間は destroy で消える。
resource "google_compute_router" "this" {
  name    = "gke-golden-path"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name   = "gke-golden-path"
  router = google_compute_router.this.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # 障害の調査に必要なときだけ見られるよう、エラーだけを記録する
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
