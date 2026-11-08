data "google_project" "this" {
  project_id = var.project_id
}

# bootstrap で使う API だけを有効にする。クラスタ用の API は本体の Terraform で有効にする。
resource "google_project_service" "this" {
  for_each = toset([
    "storage.googleapis.com",
    "billingbudgets.googleapis.com",
  ])

  service = each.key
  # destroy で API を無効にしない (ほかの Terraform が使っているため)
  disable_on_destroy = false
}

# ---------------------------------------------------------------
# Terraform の state 用バケット (本体と platform の state を置く)
# ---------------------------------------------------------------
# trivy:ignore:AVD-GCP-0066 state に秘密は入れない方針であり、Google 管理の鍵による暗号化で十分。CMEK は鍵の管理コストに見合わない
resource "google_storage_bucket" "tfstate" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  # 公開を禁止し、権限は IAM だけで管理する
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # state を壊したときに戻せるよう、過去の版を残す
  versioning {
    enabled = true
  }

  # 古い版がたまり続けないよう、新しい版が 10 個を超えたら古いものを消す
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # state を誤って消さないため
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------
# 予算アラート
# ---------------------------------------------------------------
# クラスタを destroy している間も残すため、bootstrap に置く (ADR 0004)。
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${var.project_id}-monthly"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
    # 無料クレジットの適用前の金額で判定する (CLAUDE.md)。
    # クレジットを含めると請求額が 0 円に見えて、使いすぎに気づけないため。
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      # currency_code は省略し、請求先アカウントの通貨に合わせる
      units = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  # 月末までの予測で超えそうなときにも、早めに知らせる
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # 通知は、請求先アカウントの管理者と閲覧者へのメール (既定の動作) を使う。
  # 通知チャネル (Cloud Monitoring) を作らずに済むため。
  # 【all_updates_rule は書かない】provider v8.10 では、このブロックを書くと
  # monitoring_notification_channels か pubsub_topic のどちらかが必須になり、plan が失敗する。
  # 省略しても既定のメールは止まらない (止めるのは disable_default_iam_recipients = true だけ)。
  # 2026-11-08 の apply 後に、Console の予算の画面で管理者へのメールが有効なことを確認した。

  depends_on = [google_project_service.this]
}
