# gke-golden-path

GKE の上に、開発者が使う「ゴールデンパス」を備えた、小さな内部開発者プラットフォームを作る学習プロジェクト。
題材のアプリは [OpenTelemetry Demo (Astronomy Shop)](https://opentelemetry.io/docs/demo/)。

> 現在は**フェーズ 1** の作業中。進捗は [docs/progress.md](docs/progress.md) にある。

## 見せたいこと
ツールを並べることではなく、次の流れを通しで動かして見せること。

1. 開発者がテンプレート (ゴールデンパス) から新しいサービスを作る
2. PR を出すと、CI がテスト・脆弱性検査・SBOM 作成・イメージ署名を行う
3. マージすると、ArgoCD が dev にデプロイし、確認後に prod へ昇格する
4. Kyverno が署名のないイメージや方針違反を拒否する
5. ダッシュボードと SLO・アラートが自動で付く
6. 障害を起こすと、アラートが鳴り、トレースで原因を特定でき、ポストモーテムを書ける

## 構成図
(フェーズ 1 の完了時に追加する)

## 選定理由
| 判断 | ADR |
|---|---|
| リージョンは東京 | [0001](docs/adr/0001-region-tokyo.md) |
| GKE はゾーン型 | [0002](docs/adr/0002-zonal-cluster.md) |
| ArgoCD は Terraform で入れて、Terraform が管理し続ける | [0003](docs/adr/0003-argocd-bootstrap-by-terraform.md) |
| Terraform を bootstrap・本体・platform に分ける | [0004](docs/adr/0004-terraform-split.md) |
| ツールはチェックサムとコミット SHA で固定する | [0005](docs/adr/0005-pin-tools-by-checksum-and-sha.md) |

## 再現の手順
(作業中。フェーズ 1 の完了時に、`terraform apply` から画面が開くまでを、ここに書く)

### 0. 前提
- ツール: `gcloud`、[mise](https://mise.jdx.dev/)。terraform・tflint・trivy・gitleaks・pre-commit は、`mise install` で `mise.lock` に記録したもの (チェックサムで固定) が入る
- `pre-commit install` でコミット時の検査を有効にする
- 無料クレジットの付いた GCP の請求先アカウント

### 1. GCP プロジェクト (初回だけ)
```bash
gcloud auth login
gcloud projects create <PROJECT_ID> --name="gke-golden-path"
gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>
gcloud config set project <PROJECT_ID>
gcloud auth application-default login
gcloud auth application-default set-quota-project <PROJECT_ID>
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com
```

### 2. bootstrap: state 用のバケットと予算アラート (初回だけ)
```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # 値を入れる
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

## ディレクトリ構成
```
terraform/
  bootstrap/   state 用のバケットと予算アラート (state はローカル。初回だけ apply する)
  (本体)       VPC、GKE、Artifact Registry、Workload Identity Federation  ※作成予定
  platform/    ArgoCD と、最初の Application  ※作成予定
docs/
  progress.md  進捗・決定事項・落とし穴
  adr/         設計判断の記録
```
