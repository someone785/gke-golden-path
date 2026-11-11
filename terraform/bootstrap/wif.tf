# ---------------------------------------------------------------
# Workload Identity Federation (GitHub Actions からの認証、鍵ファイルなし)
# ---------------------------------------------------------------
# GitHub Actions が発行する OIDC トークンを、GCP の短期の認証情報に交換する。
# サービスアカウントは作らず、IAM のロールを GitHub のリポジトリ (principalSet) に直接付ける。
#
# 本体ではなく bootstrap に置く理由 (ADR 0004 の追記):
# - 【削除した pool と provider は 30 日間、同じ ID で作り直せない】本体と一緒に destroy すると、次の apply が失敗する
# - クラスタを消している間も、CI の terraform plan が認証できるようにするため
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # 【この条件がないと、GitHub 上のどのリポジトリの Actions からでも、この pool で認証できてしまう】
  attribute_condition = "assertion.repository == \"${var.github_repository}\""
}

locals {
  github_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# CI の terraform plan 用 (フェーズ 1)。読み取りだけを許可する。
# 下の 3 つ (viewer、serviceUsageConsumer、state バケットの objectUser) で plan が通ることを確認した (2026-11-11、クラスタなしの状態)
# 【クラスタがある状態での plan は未確認】GKE の詳細の読み取りで足りなければ足す
resource "google_project_iam_member" "github_plan" {
  project = var.project_id
  role    = "roles/viewer"
  member  = local.github_principal
}

# 【provider の user_project_override = true は、呼び出し元に serviceusage.services.use を要求する】
# roles/viewer には含まれないので、別に付ける (provider のドキュメント)
resource "google_project_iam_member" "github_plan_serviceusage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = local.github_principal
}

# plan は state を読み、ロックのファイルを書くので、state 用のバケットのオブジェクトの読み書きを許可する
resource "google_storage_bucket_iam_member" "github_tfstate" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = local.github_principal
}
