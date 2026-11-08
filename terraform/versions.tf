# 本体の Terraform (ADR 0004)。VPC、GKE、Artifact Registry、Workload Identity Federation を作る。
# 作り直すたびに apply / destroy する。state は bootstrap で作った GCS のバケットに置く。
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }

  # バケット名は backend.hcl で渡す (terraform init -backend-config=backend.hcl)。
  # 【backend ブロックには変数を書けない】そのため、プロジェクトごとに変わる値は外に出す。
  backend "gcs" {
    prefix = "main"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # bootstrap と同じ理由 (ユーザーの ADC で一部の API を呼ぶと、quota project がないというエラーになる)
  user_project_override = true
  billing_project       = var.project_id
}
