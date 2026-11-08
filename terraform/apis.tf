# 本体で使う API。bootstrap の API (storage、billingbudgets、WIF 用) は bootstrap が管理する。
resource "google_project_service" "this" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    # iam・iamcredentials・sts (Workload Identity Federation 用) は bootstrap が管理する
  ])

  service = each.key
  # 【destroy で API を無効にしない】無効にすると、次の apply で有効になるまで待たされるうえ、
  # API に紐づくリソースの削除を待たずに無効化して失敗することがあるため
  disable_on_destroy = false
}
