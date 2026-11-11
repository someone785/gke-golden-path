variable "project_id" {
  description = "GCP のプロジェクト ID"
  type        = string
}

variable "region" {
  description = "リージョン (ADR 0001)"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "クラスタとノードを置くゾーン (ADR 0002)。Spot が確保できなければ変える"
  type        = string
  default     = "asia-northeast1-a"
}

variable "node_machine_type" {
  description = "ノードのマシンタイプ。OTel Demo の limits の合計は約 8 GiB (docs/progress.md の実測の記録)"
  type        = string
  default     = "e2-standard-4"
}

variable "node_count" {
  description = "ノードの台数 (ゾーン型なので、この台数がそのまま作られる)"
  type        = number
  default     = 1
}

variable "node_disk_size_gb" {
  description = "ノードのブートディスクの大きさ (GB)。【30 GB ではイメージの置き場が約 83% まで埋まった】(docs/progress.md の実測の記録)"
  type        = number
  default     = 50
}
