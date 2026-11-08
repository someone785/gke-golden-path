# 進捗・決定事項・落とし穴

このプロジェクトの正の記録。新しいセッションでは、README の次にこれを読む。

## 現在のフェーズ
**フェーズ 1** (Terraform で VPC と GKE、ArgoCD、OTel Demo のデプロイ、GitHub Actions、README と構成図)

完了の条件: `terraform apply` から OTel Demo の画面が開くまでを、手順どおり再現できる。

## 中断した地点 (2026-11-08)
- 終わったこと: GCP プロジェクトの作成 (README の手順 1)。雛形・ADR・bootstrap のコード
- 作業環境を Fedora から WSL (Ubuntu) に移した。コミットのメールアドレスを直すため、Git の履歴は捨てて `git init` からやり直した (古いコミット ID は無効)。移行後の確認 (`mise install --locked`、`pre-commit run --all-files`、gcloud の 2 つのログイン) は済んだ
- 次にやること: bootstrap の plan (README の手順 2)。apply はまだしない
  ```bash
  cd terraform/bootstrap
  cp terraform.tfvars.example terraform.tfvars   # project_id と billing_account を入れる
  terraform init 2>&1 | tee ../../out.txt
  terraform plan -out=bootstrap.tfplan 2>&1 | tee -a ../../out.txt
  terraform show -no-color bootstrap.tfplan | grep -E '^  # |^Plan:' > ../../bootstrap.plan.txt
  ```
  期待する結果は `Plan: 4 to add` (API 2 つ、バケット、予算アラート)。`replace` / `destroy` がないことを確認する。
  `out.txt` には請求先アカウントの ID が出る可能性がある (gitignore 済み)。
- ユーザーの判断待ち: クレジットの期限の前に、bootstrap (state 用のバケット、予算アラート) も消すか、プロジェクトごと削除するか。消す場合は、バケットの `prevent_destroy` を外す手順を「期限」の節に書く
- その次: bootstrap の apply → `terraform/` 本体 (VPC、GKE、Artifact Registry、WIF) の作成

## 期限 (重要)
- 無料クレジットの期限は **2027-01-27**。課金アカウントは有料に切り替え済みなので、期限を過ぎると**実費で課金される**。
- **2027-01-26 までに** `terraform destroy` (platform → 本体) を済ませ、残っているリソースがないことを確認する。
- フェーズ 3 以降は、GKE を使わず kind で進められるものを優先する。

## 次にやること
- [x] GCP プロジェクトの作成、請求先アカウントのリンク、ADC の設定、最小限の API の有効化 (2026-11-08、ユーザーの端末で実行)
- [x] リポジトリの雛形: `README.md`、`.gitignore`、`.pre-commit-config.yaml`、`mise.toml` / `mise.lock` (2026-11-08)
- [ ] `terraform/bootstrap/`: state 用のバケット、予算アラート (`EXCLUDE_ALL_CREDITS`) — コードは作成済み。plan と apply が未実施
- [ ] `terraform/`: VPC、GKE (ゾーン型、Spot ノードプール)、Artifact Registry、Workload Identity Federation
- [ ] `terraform/platform/`: ArgoCD と、最初の Application
- [ ] `gitops/apps/`: OTel Demo の Application
- [ ] `.github/workflows/`: 検査 (fmt、tflint、trivy、gitleaks) と `terraform plan` (OIDC で鍵なし)
- [ ] README (構成図、再現の手順)、デモの録画、初日の請求額の実測

## 決定事項

| 日付 | 決定 | ADR |
|---|---|---|
| 2026-11-08 | リージョンは東京 (asia-northeast1)。Terraform の変数にする | [0001](adr/0001-region-tokyo.md) |
| 2026-11-08 | GKE はゾーン型のクラスタ | [0002](adr/0002-zonal-cluster.md) |
| 2026-11-08 | ArgoCD は Terraform (`helm_release`) で入れて、ArgoCD 自身は Terraform が管理し続ける | [0003](adr/0003-argocd-bootstrap-by-terraform.md) |
| 2026-11-08 | Terraform を bootstrap・本体・platform の 3 つに分ける | [0004](adr/0004-terraform-split.md) |
| 2026-11-08 | ツールは、タグではなくチェックサム (`mise.lock`) とコミット SHA で固定する | [0005](adr/0005-pin-tools-by-checksum-and-sha.md) |

## 未確認のこと (確認したら、ここを更新する)
- 東京と他のリージョンの料金の差。Spot の在庫
- GKE の管理手数料の無料枠 (ゾーン型のクラスタ 1 つ分か)
- ゾーンをまたぐ通信の料金
- Claude の sandbox で、存在しない dotfile (`.bashrc` など) が `git status` に未追跡として出る現象 (Fedora の bubblewrap で発生) が、WSL でも起きるか。出たら無視し、`git add` しない
- OTel Demo を動かすのに必要なメモリ・CPU と、それに合うノードのサイズと台数
- Renovate が Terraform の `helm_release` の版の更新に対応しているか
- Renovate が `mise.lock` と、SHA で固定した `rev:` / `uses:` の更新に対応しているか

## 実測の記録
- 2026-11-08: trivy v0.69.3 のリリースを GitHub API で確認した。公開日は 2026-03-03 (攻撃の 3 月 19 日より前)、`immutable: true`。`mise.lock` の linux-x64 のチェックサムは、公式の `trivy_0.69.3_checksums.txt` と一致した。mise は lock のときに cosign で来歴を検証している (`provenance = "cosign"`)。
(初日の請求額、Spot の回収の状況などを、ここに書く)

## 落とし穴
- 【ゾーン型とリージョン型は、作成後に切り替えられない】`location` を変えると、クラスタは作り直しになる。
- 【リージョン型のノード数はゾーンごと】`node_count = 2` は、2 台 × 3 ゾーン = 6 台になる。
- 【GKE と同じ Terraform で helm/kubernetes provider を使わない】作り直しや destroy のときに壊れやすい → ADR 0004
- 【bootstrap の state はローカルにある】失わないようにする。
- 【trivy の 0.69.4〜0.69.6 は使わない】CVE-2026-33634 で悪意のある版が出回った。trivy-action・setup-trivy のタグも付け替えられた → ADR 0005
- 【mise.toml に `[settings] locked = true` を書かない】グローバルの設定のツール (node、starship) まで lock を要求されて失敗する。厳格な検査は CI の `mise install --locked` で行う。
- 【mise の公式ドキュメントは、手元の mise 2026.10.8 より新しい】`locked_require_checksum` は「不明な設定」と警告された。ドキュメントの設定を使う前に、手元の版で使えるか確かめる。
- 【pre-commit の上流の gitleaks フックは、初回に Go ごとソースからビルドするので遅い】→ repo: local で手元の gitleaks を呼ぶ。版は `mise.toml` で固定する。
- 【作業は WSL2 (Ubuntu) の中で行う。ネイティブの Windows では作業しない】`mise.lock` に pre-commit の `windows-x64` のチェックサムがなく、pre-commit-terraform のフックと CLAUDE.md の手順も bash が前提。
- 【リポジトリは WSL の中 (`~/projects/...`) に置く。`/mnt/c/...` に置かない】Windows のファイルシステム越しは遅く、改行コード (CRLF) と実行権限で問題が出やすい。
- 【改行コード】WSL の git は `core.autocrlf=input`。`.gitattributes` はまだない。Windows 側のエディタで開くなら `* text=auto eol=lf` を足すことを検討する。

## 後でやる
(今のフェーズで不要なものは、ここに書いて止める)
