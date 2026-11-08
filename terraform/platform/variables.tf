variable "project_id" {
  description = "GCP のプロジェクト ID"
  type        = string
}

variable "region" {
  description = "リージョン (ADR 0001)"
  type        = string
  default     = "asia-northeast1"
}

variable "cluster_name" {
  description = "本体で作ったクラスタの名前 (本体の出力 cluster_name)"
  type        = string
  default     = "gke-golden-path"
}

variable "cluster_location" {
  description = "本体で作ったクラスタのゾーン (本体の出力 cluster_location)"
  type        = string
  default     = "asia-northeast1-a"
}

variable "gitops_repo_url" {
  description = "ArgoCD が読む Git のリポジトリ。【public であること】private だと認証の設定が要る"
  type        = string
  default     = "https://github.com/someone785/gke-golden-path.git"
}

variable "gitops_revision" {
  description = "ArgoCD が追いかけるブランチ"
  type        = string
  default     = "main"
}
