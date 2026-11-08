# 進捗・決定事項・落とし穴

このプロジェクトの正の記録。新しいセッションでは、README の次にこれを読む。

## 現在のフェーズ
**フェーズ 1** (Terraform で VPC と GKE、ArgoCD、OTel Demo のデプロイ、GitHub Actions、README と構成図)

完了の条件: `terraform apply` から OTel Demo の画面が開くまでを、手順どおり再現できる。

## 中断した地点 (2026-11-08)
- 終わったこと: GCP プロジェクトの作成 (README の手順 1)。雛形・ADR・bootstrap のコード
- 作業環境を Fedora から WSL (Ubuntu) に移した。コミットのメールアドレスを直すため、Git の履歴は捨てて `git init` からやり直した (古いコミット ID は無効)。移行後の確認 (`mise install --locked`、`pre-commit run --all-files`、gcloud の 2 つのログイン) は済んだ
- bootstrap の plan と apply が済んだ (2026-11-08)。state 用のバケット `<project_id>-tfstate` と予算アラートができた。WIF も bootstrap に移した (下記)
  - 【`terraform/bootstrap/terraform.tfstate` はこの PC にしかない】バックアップはとらず、失ったら import で戻す (2026-11-08 に決定)。手順は「bootstrap の state を失ったら」。state を退避して plan で試し、`4 to import` を確認した (2026-11-08。その後 WIF を足したので、今は 11 個。11 個での試行は未実施)
- GitHub の `someone785/gke-golden-path` (private) に push した (2026-11-08)
- `terraform/` 本体を書き、apply → `kubectl get nodes` (Ready、kube-system の Pod が Running) → destroy まで通した (2026-11-08、約 30 分)
- destroy の後、【削除した WIF の pool と provider は 30 日間同じ ID で作り直せない】ことが分かり、WIF を bootstrap に移した (ADR 0004 の追記)。pool と provider は undelete して bootstrap に import した
- 本体の `remove_default_node_pool` (非推奨) をやめ、既定のノードプールなしで作る書き方にした (クラスタの版が条件を満たしたため)。【この書き方での apply は未実施】
- 次にやること: `terraform/platform/` (ArgoCD と最初の Application)。コードはクラスタがない間に書き、apply は OTel Demo の画面を開くところまでまとめて行う
- ユーザーの判断待ち: クレジットの期限の前に、bootstrap (state 用のバケット、予算アラート、WIF) も消すか、プロジェクトごと削除するか。消す場合は、バケットの `prevent_destroy` を外す手順を「期限」の節に書く

## 期限 (重要)
- 無料クレジットの期限は **2027-01-27**。課金アカウントは有料に切り替え済みなので、期限を過ぎると**実費で課金される**。
- **2027-01-26 までに** `terraform destroy` (platform → 本体) を済ませ、残っているリソースがないことを確認する。
- フェーズ 3 以降は、GKE を使わず kind で進められるものを優先する。

## 次にやること
- [x] GCP プロジェクトの作成、請求先アカウントのリンク、ADC の設定、最小限の API の有効化 (2026-11-08、ユーザーの端末で実行)
- [x] リポジトリの雛形: `README.md`、`.gitignore`、`.pre-commit-config.yaml`、`mise.toml` / `mise.lock` (2026-11-08)
- [x] `terraform/bootstrap/`: state 用のバケット、予算アラート (`EXCLUDE_ALL_CREDITS`)、Workload Identity Federation (2026-11-08 に apply)
- [x] `terraform/`: VPC、GKE (ゾーン型、Spot ノードプール)、Artifact Registry (2026-11-08 に apply → destroy で確認)
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
- 東京と他のリージョンの料金の差。Spot の在庫と回収の頻度
- ノードのブートディスク (GKE の既定は 100 GB と記憶しているが未確認)、LoadBalancer、通信の料金
- Cloud Billing API (価格表) の利用料金 (ドキュメントに記載なし)
- ゾーンをまたぐ通信の料金
- Claude の sandbox で、存在しない dotfile (`.bashrc` など) が `git status` に未追跡として出る現象 (Fedora の bubblewrap で発生) が、WSL でも起きるか。出たら無視し、`git add` しない
- OTel Demo を動かすのに実際に使うメモリ・CPU (limits の合計は約 8 GiB。下の「実測の記録」)。`agent`・`chatbot`・`mcp` に LLM の API キーが要るか
- Renovate が Terraform の `helm_release` の版の更新に対応しているか
- Renovate が `mise.lock` と、SHA で固定した `rev:` / `uses:` の更新に対応しているか

## 実測の記録
- 2026-11-08: trivy v0.69.3 のリリースを GitHub API で確認した。公開日は 2026-03-03 (攻撃の 3 月 19 日より前)、`immutable: true`。`mise.lock` の linux-x64 のチェックサムは、公式の `trivy_0.69.3_checksums.txt` と一致した。mise は lock のときに cosign で来歴を検証している (`provenance = "cosign"`)。
- 2026-11-08: 予算アラートの `all_updates_rule` を省略しても、Console の予算の画面で「請求先アカウントの管理者とユーザーにメールでアラートを送信」が有効になっていることを確認した。
- 2026-11-08: GKE の料金のページで確認。管理手数料は $0.10 / クラスタ / 時間。無料枠は請求先アカウントごとに月 $74.40 (ゾーン型の Standard か Autopilot のクラスタ 1 つ分)。繰り越しなし。ノードの Compute Engine の料金には使えない。
- 2026-11-08: Cloud Billing Catalog API で、東京 (asia-northeast1) の E2 の単価 (円、税抜きかは未確認) を取得した。Spot の割引は約 40% (料金のページの「60〜91%」より小さい)。API は調べたあとに無効に戻す。

  | | vCPU / 時間 | メモリ GiB / 時間 | e2-standard-2 / 時間 | e2-standard-4 / 時間 | e2-standard-4 / 730 時間 |
  |---|---|---|---|---|---|
  | Spot | 2.661 円 | 0.355 円 | 8.16 円 | 16.32 円 | 約 11,900 円 |
  | 通常 | 4.434 円 | 0.592 円 | 13.60 円 | 27.20 円 | 約 19,900 円 |

  【予算 5,000 円 / 月では、e2-standard-4 の Spot 1 台でも常時は動かせない】使うときだけ apply し、終わったら destroy する (例: 80 時間で約 1,300 円 + ディスクなど)。
- 2026-11-08: OTel Demo (chart 0.42.6 / アプリ 3.1.0) の `values.yaml` のメモリの limits の合計は、デモのサービス約 6.1 GiB + 監視の部品約 2.0 GiB = 約 8 GiB。
- 2026-11-08: 本体の apply は、クラスタの作成が 8 分 34 秒、ノードプールが 53 秒。API の有効化に約 1 分。destroy は数分。
- 2026-11-08: REGULAR チャンネルで作られたクラスタの版は 1.36.4-gke.2046003 (コントロールプレーン、ノードとも)。kubectl は 1.36.6 を `mise.lock` で固定した (公式の sha256 と一致を確認)。
(初日の請求額、Spot の回収の状況などを、ここに書く)

## bootstrap の state を失ったら
バックアップはとらない。リソースは 11 個だけで、`import` ブロックで戻せるため (bootstrap は最初の 1 回だけ apply し、destroy しない。ADR 0004)。
`terraform.tfvars` も失っていたら、`terraform.tfvars.example` から作り直す。

```bash
cd terraform/bootstrap
# 予算アラートの ID を調べる (出力の billingAccounts/.../budgets/ の後ろの部分)
gcloud billing budgets list --billing-account=<請求先アカウントの ID> 2>&1 | tee ../../out.txt
cp import.tf.example import.tf
terraform plan -var budget_id=<予算アラートの ID> -out=import.tfplan 2>&1 | tee ../../out.txt
terraform show -no-color import.tfplan | grep -E '^  # |^Plan:' > ../../bootstrap.plan.txt
```
期待する結果は `Plan: 11 to import, 0 to add, 0 to change, 0 to destroy`。`add` や `change` があれば apply しない。
問題がなければ `terraform apply import.tfplan` → `rm import.tf import.tfplan` → `terraform plan` で `No changes` を確かめる。

## 落とし穴
- 【ゾーン型とリージョン型は、作成後に切り替えられない】`location` を変えると、クラスタは作り直しになる。
- 【リージョン型のノード数はゾーンごと】`node_count = 2` は、2 台 × 3 ゾーン = 6 台になる。
- 【GKE と同じ Terraform で helm/kubernetes provider を使わない】作り直しや destroy のときに壊れやすい → ADR 0004
- 【bootstrap の state はローカルにある】失ったら「bootstrap の state を失ったら」の手順で import する。【state を失ったまま apply しない】バケットは名前の重複で失敗し、予算アラートは 2 つめが作られる。
- 【trivy の 0.69.4〜0.69.6 は使わない】CVE-2026-33634 で悪意のある版が出回った。trivy-action・setup-trivy のタグも付け替えられた → ADR 0005
- 【mise.toml に `[settings] locked = true` を書かない】グローバルの設定のツール (node、starship) まで lock を要求されて失敗する。厳格な検査は CI の `mise install --locked` で行う。
- 【mise の公式ドキュメントは、手元の mise 2026.10.8 より新しい】`locked_require_checksum` は「不明な設定」と警告された。ドキュメントの設定を使う前に、手元の版で使えるか確かめる。
- 【pre-commit の上流の gitleaks フックは、初回に Go ごとソースからビルドするので遅い】→ repo: local で手元の gitleaks を呼ぶ。版は `mise.toml` で固定する。
- 【作業は WSL2 (Ubuntu) の中で行う。ネイティブの Windows では作業しない】`mise.lock` に pre-commit の `windows-x64` のチェックサムがなく、pre-commit-terraform のフックと CLAUDE.md の手順も bash が前提。
- 【リポジトリは WSL の中 (`~/projects/...`) に置く。`/mnt/c/...` に置かない】Windows のファイルシステム越しは遅く、改行コード (CRLF) と実行権限で問題が出やすい。
- 【改行コード】WSL の git は `core.autocrlf=input`。`.gitattributes` はまだない。Windows 側のエディタで開くなら `* text=auto eol=lf` を足すことを検討する。
- 【削除した Workload Identity Pool / Provider は 30 日間、同じ ID で作り直せない】destroy する側 (本体) に置かない → ADR 0004 の追記
- 【GKE の `deletion_protection` は provider の既定が true】false にしないと destroy できない
- 【`... | tee out.txt` は上書きする】結果を残したいコマンドの後に別のコマンドを tee すると、前の結果が消える。続けて記録するときは `tee -a`

## 後でやる
(今のフェーズで不要なものは、ここに書いて止める)
- フェーズ 3: Artifact Registry の置き場所を決める。本体にあると destroy のたびにイメージが消え、同じ名前ですぐ作り直せるかも未確認 (ADR 0004 の追記)
