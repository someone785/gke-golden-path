variable "project_id" {
  description = "GCP のプロジェクト ID"
  type        = string
}

variable "region" {
  description = "state 用のバケットを置くリージョン (ADR 0001)"
  type        = string
  default     = "asia-northeast1"
}

variable "billing_account" {
  description = "請求先アカウントの ID (XXXXXX-XXXXXX-XXXXXX)。予算アラートの作成に使う"
  type        = string
}

variable "budget_amount" {
  description = "月の予算額。通貨は請求先アカウントの通貨になる (日本の請求先アカウントなら円のはず。未確認)"
  type        = number
  default     = 5000
}
