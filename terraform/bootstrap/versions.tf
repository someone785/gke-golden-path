# bootstrap の state はローカルに置く (ADR 0004)。
# 【この terraform.tfstate を失うと、バケットと予算を Terraform で管理できなくなる】(import すれば戻せる)
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # 【ユーザーの ADC で Billing Budgets API を呼ぶと、quota project がないというエラーになる】
  # そのため、API の利用をこのプロジェクトに付ける。
  user_project_override = true
  billing_project       = var.project_id
}
