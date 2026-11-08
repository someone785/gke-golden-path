# tflint の設定。pre-commit と CI の両方で使う。
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# GCP 固有の誤り (存在しないマシンタイプなど) を検出するため
plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
