# CLAUDE.md

GKE の上に、開発者が使う「ゴールデンパス」を備えた小さな内部開発者プラットフォームを作る、個人の学習プロジェクト。
題材のアプリは OpenTelemetry Demo (Astronomy Shop)。

最初に `README.md` → `docs/progress.md` (決定事項・現在のフェーズ・落とし穴。最優先) の順に読むこと。
設計判断の理由は `docs/adr/` にある。

## このプロジェクトで示したいこと
ツールを並べることではなく、**次の一連の流れを通しで動かして見せること**。
新しいことを足すときは、この流れのどこに入るかを先に説明できるものだけを足す。

1. 開発者がテンプレート (ゴールデンパス) から新しいサービスを作る
2. PR を出すと、CI がテスト・脆弱性検査・SBOM 作成・イメージ署名を行う
3. マージすると、ArgoCD が dev にデプロイし、確認後に prod へ昇格する
4. Kyverno が署名のないイメージや方針違反を拒否する
5. ダッシュボードと SLO・アラートが自動で付く
6. 障害を起こすと、アラートが鳴り、トレースで原因を特定でき、ポストモーテムを書ける

## 作業ルール
- **返信は日本語**。ユーザーはローマ字で書くことが多い。
- **`terraform apply` / `destroy`、`kubectl apply` / `delete` (クラスタへの直接変更)、`git commit` / `git push` はユーザーが自分の端末で実行する**。Claude は実行せず、コマンドを渡す。commit / push は、そのつど明示的な OK を待つ。
- クラスタへの変更は、原則 **Git にコミットして ArgoCD に反映させる** (GitOps)。`kubectl` での直接変更は、調査と一時的な検証だけにする。
- apply 前に **plan を `-out` で保存**し、`terraform show -no-color X.tfplan | grep -E '^  # |^Plan:'` で内容を確認して報告する。`replace` / `destroy` が混ざっていたら、apply の前に、はっきり伝える。
- **課金が始まる操作** (クラスタやノードプールの作成・拡張) の前に、金額の目安と止め方を伝える。
- **未確認のことは「未確認」と書く**。料金・クォータ・無料枠・API やツールの仕様を、記憶で断定しない (公式のドキュメントで確認する。確認できなければ、そう書く)。
- 秘密 (鍵、トークン、`*.tfvars`、`backend.hcl`、`*.tfstate`、kubeconfig) は、コミットも表示もしない。出力に秘密が出たら、指摘して、無効化の手順を示す。
- `*.tfplan` は使い終わったら消す。

## スコープの管理 (重要)
- 作業は**フェーズ順**に進める。今のフェーズが終わるまで、次のフェーズのものに手を付けない。
- ユーザーが新しいツールを足したくなったら、①上の流れのどこに入るか、②今のフェーズで必要か、を確認し、必要でなければ `docs/progress.md` の「後でやる」に書いて止める。
- 「全部そろってから」ではなく、**各フェーズの終わりで動くものをデモできる状態**にする (README の更新と、画面録画か手順の記録まで含めて完了とする)。

| フェーズ | 内容 | 完了の条件 |
|---|---|---|
| 1 | Terraform で VPC と GKE、ArgoCD、OTel Demo のデプロイ、GitHub Actions (OIDC で鍵なし)、README と構成図 | `terraform apply` から OTel Demo の画面が開くまでを、手順どおり再現できる |
| 2 | SLO (Sloth)、アラート、障害の注入 (OTel Demo の flagd) → 検知 → トレースで原因特定、ポストモーテムと Runbook | 障害を起こしてから原因を特定するまでのデモ動画がある |
| 3 | ゴールデンパスのテンプレートと自分のサービス、SBOM (Syft)、署名 (Cosign)、Kyverno での検証、External Secrets、dev/prod の分離、Renovate | 「このプロジェクトで示したいこと」の 1〜5 が通しで動く |
| 4 | Backstage のソフトウェアテンプレート、OpenCost | 余裕があれば |

## 技術の選択 (決定済み。変えるときは ADR を書く)
- **クラウド**: GCP (GKE)。EKS は作らない。ローカルの検証は kind。
- **Pod からクラウドへの認証**: GKE の Workload Identity。CI からクラウドへの認証は、GitHub Actions の OIDC と Workload Identity Federation。**鍵ファイルは作らない**。
- **マニフェスト**: 他者が作ったもの (OTel Demo など) は Helm で入れる。自分のマニフェストと環境ごとの差分は Kustomize の overlay で管理する。
- **依存の更新**: Renovate (Helm の values、Terraform、ArgoCD のマニフェストまで対象にするため)。
- **署名と SBOM**: 自分でビルドしたイメージだけが対象。OTel Demo の公開イメージは対象外。
- **監視**: OTel Demo の Helm chart に同梱の部品 (OTel Collector、Prometheus、Grafana、Jaeger) と、自分で足す部品の役割が重ならないようにする。足す前に、同梱のもので足りないかを確認する。
- **秘密情報**: External Secrets Operator + Secret Manager。Secret をマニフェストに直接書かない。

## コスト
- 無料クレジットの期限は **2027 年 1 月 27 日**。それ以降はクラスタを動かせない前提で、各フェーズの終わりに**デモの録画を残す**。
- 【課金アカウントは有料に切り替え済み】期限を過ぎると、クレジットではなく**実費で課金される**。期限の前日までに `terraform destroy` を済ませ、残っているリソースがないことを確認する。
- フェーズ 3 以降は、GKE を使わず手元の kind で進められるものを優先する。
- 使っていない間は `terraform destroy` で消す。作り直せることも、このプロジェクトで示す価値の一つ。
- ノードは Spot を基本にする。GKE の無料枠・料金・Spot の在庫は**未確認**のため、最初に動かした日の請求レポートで実測し、`docs/progress.md` に記録する。
- 予算アラートは、無料クレジットの適用前の金額で判定する (`EXCLUDE_ALL_CREDITS`)。

## Claude の環境でできること・できないこと
- できる: ファイルの読み書き、`terraform fmt`、`bash -n`、`trivy config` (ローカル)、`kustomize build` と `helm template` (入っていれば)。
- できない: `terraform plan` / `apply`、`gcloud`、`kubectl` でのクラスタ操作、`git push`。**ユーザーの端末での実行**を依頼し、結果は `... 2>&1 | tee out.txt` でファイルに保存してもらい、「見て」で読む (`out.txt` / `*.plan.txt` は gitignore 済み)。

## Git
- **`git add` は、パスを指定**する。`git add -A` / `git add .` は使わない。話題ごとにコミットを分ける。
- コミットメッセージは英語。末尾に `Co-Authored-By` 行を付ける。
- コミット時に pre-commit が走る: `terraform fmt` / `tflint` / `trivy` / `gitleaks` / 秘密鍵の検出。trivy の除外は、**リソース宣言の直前**に `# trivy:ignore:ID 理由` と書く。
- CI (GitHub Actions) でも同じ検査を、変更の有無にかかわらず全ディレクトリに対して実行する。

## ディレクトリ構成 (予定)
```
terraform/          VPC、GKE、Workload Identity、Artifact Registry、予算
  bootstrap/        state 用バケット (state はローカル)
gitops/
  apps/             ArgoCD の Application / ApplicationSet
  platform/         ArgoCD、Kyverno、External Secrets、監視の部品
  workloads/        OTel Demo と自分のサービス (Kustomize の base と overlays/dev・prod)
templates/          ゴールデンパスのサービステンプレート
.github/workflows/  CI (検査、SBOM、署名、Terraform の plan)
docs/
  progress.md       進捗・決定事項・落とし穴 (正の記録)
  adr/              設計判断の記録 (1 件 1 ファイル)
  runbooks/         アラートごとの対応手順
  postmortems/      障害注入の記録
```

## 書き方の規約
- Terraform とマニフェストのコメントは日本語で、**理由 (なぜそうしたか)** を書く。落とし穴は `【…】` で目立たせる。
- 設計判断は ADR に残す (背景、選択肢、決定、結果)。README の「選定理由」は ADR へのリンクにする。
- README の冒頭には、何を作ったか・見どころ・構成図を置く。作業ログや経緯は `docs/progress.md` に書く。
- 起動スクリプトや Job は冪等に書く。
