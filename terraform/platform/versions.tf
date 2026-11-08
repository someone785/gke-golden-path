# platform の Terraform (ADR 0003、0004)。ArgoCD と、最初の Application (app-of-apps のルート) を入れる。
# 本体の apply の後に apply し、本体の destroy の前に destroy する。
# 【本体のクラスタがないと plan できない】data source でクラスタを読むため
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # バケット名は本体と同じ backend.hcl で渡す (terraform init -backend-config=../backend.hcl)
  backend "gcs" {
    prefix = "platform"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id
}

# 本体の出力 (terraform_remote_state) ではなく data source でクラスタを読む。
# 本体の state の中身 (出力の名前) に依存しないため。クラスタ名とゾーンは変数で合わせる
data "google_client_config" "this" {}

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.cluster_location
}

provider "helm" {
  kubernetes = {
    host                   = "https://${data.google_container_cluster.this.endpoint}"
    token                  = data.google_client_config.this.access_token # 【有効期限は約 1 時間 (未確認)】apply が長引いたら切れる
    cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  }
}
