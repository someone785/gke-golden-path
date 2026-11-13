# 進捗・決定事項・落とし穴

このプロジェクトの正の記録。新しいセッションでは、README の次にこれを読む。

## 現在のフェーズ
**フェーズ 2** (SLO (Sloth)、アラート、障害の注入 (flagd) → 検知 → トレースで原因特定、ポストモーテムと Runbook)

完了の条件: 障害を起こしてから原因を特定するまでのデモ動画がある。

フェーズ 1 は 2026-11-13 に完了した ([demo/phase1.md](demo/phase1.md))。

## 中断した地点 (2026-11-11)
- 終わったこと: GCP プロジェクトの作成 (README の手順 1)。雛形・ADR・bootstrap のコード
- 作業環境を Fedora から WSL (Ubuntu) に移した。コミットのメールアドレスを直すため、Git の履歴は捨てて `git init` からやり直した (古いコミット ID は無効)。移行後の確認 (`mise install --locked`、`pre-commit run --all-files`、gcloud の 2 つのログイン) は済んだ
- bootstrap の plan と apply が済んだ (2026-11-08)。state 用のバケット `<project_id>-tfstate` と予算アラートができた。WIF も bootstrap に移した (下記)
  - 【`terraform/bootstrap/terraform.tfstate` はこの PC にしかない】バックアップはとらず、失ったら import で戻す (2026-11-08 に決定)。手順は「bootstrap の state を失ったら」。state を退避して plan で試し、`4 to import` を確認した (2026-11-08。その後 WIF を足したので、今は 12 個。12 個での試行は未実施)
- GitHub の `someone785/gke-golden-path` (private) に push した (2026-11-08)
- `terraform/` 本体を書き、apply → `kubectl get nodes` (Ready、kube-system の Pod が Running) → destroy まで通した (2026-11-08、約 30 分)
- destroy の後、【削除した WIF の pool と provider は 30 日間同じ ID で作り直せない】ことが分かり、WIF を bootstrap に移した (ADR 0004 の追記)。pool と provider は undelete して bootstrap に import した
- 本体の `remove_default_node_pool` (非推奨) をやめ、既定のノードプールなしで作る書き方にした (クラスタの版が条件を満たしたため)。2 回目の apply で動くことを確認した
- `terraform/platform/` (ArgoCD、ルートの Application) と `gitops/apps/otel-demo.yaml` を書いた (2026-11-08、コミット済み)
- 2026-11-08 19 時台に通しで試したが、platform の apply で ArgoCD の chart の取得が失敗した (GitHub の障害「Increase in timeouts for some unauthenticated users」で HTTP 503)。本体を destroy し、リポジトリを private に戻した。platform の state には data source しかない (作られたものはない)
- **2026-11-11: 通しで動いた**。`terraform apply` (本体 → platform) → ArgoCD が Git から OTel Demo を入れる → Astronomy Shop・Jaeger・Grafana・ArgoCD の画面が開く、まで確認し、destroy した (約 1 時間)。スクリーンショットはある。録画は未確認
  - 途中で `agent` の Pod が ContainerCreating のまま止まった。原因は `agent-fixtures` の ConfigMap (約 750 KB) が client-side apply の annotation の上限 (256 KiB) を超えたこと。Application に `ServerSideApply=true` を足して直した (落とし穴を参照)
- 通しの手順は README の「再現の手順」に移した (2026-11-11)
- **2026-11-11: CI が通った**。GitHub Actions から WIF (鍵なし) で認証し、`terraform plan` が `13 to add` を出した。plan に必要な権限は viewer + serviceUsageConsumer + state バケットの objectUser で足りた
- README (何を作ったか、見どころ、構成図 (Mermaid)、再現の手順) を書いた (2026-11-11)。【README の手順 2 の後半 (backend.hcl などのコピーと init) は、通しで試していない】(手順 5 の ArgoCD のパスワードは 2026-11-13 に確認した)
- **2026-11-13: README の手順どおりに通しで動かした** (記録は [demo/phase1.md](demo/phase1.md))。一度で Synced / Healthy になり、クラスタがある状態の CI の plan は `No changes`。destroy してリポジトリを private に戻した
- 次にやること: フェーズ 1 を完了とし、フェーズ 2 (SLO、アラート、障害の注入) に進む
- ユーザーの判断待ち: クレジットの期限の前に、bootstrap (state 用のバケット、予算アラート、WIF) も消すか、プロジェクトごと削除するか。消す場合は、バケットの `prevent_destroy` を外す手順を「期限」の節に書く

- **フェーズ 2 の準備 (2026-11-13、クラスタなし)**: OTel Demo の chart 0.42.6 を調べ、SLO とアラートの構成を決めた (ADR 0006)
  - 同梱の Alertmanager と、Prometheus の configmapReload を有効にした (`gitops/workloads/otel-demo/values.yaml`)
  - checkout の PlaceOrder の SLO (99%) を Sloth で書き、`scripts/gen-slo-rules.sh` でルールを生成した。CI で一致と promtool の検査をする
  - Application を multi-source にし、values を Git から読むようにした
  - sloth 0.16.0、promtool 3.14.0、helm 4.3.1 を mise で入れた (linux-x64 のチェックサムは公式のファイルと一致)
  - (済) クラスタを動かして、span_name の実際の値・アラートが鳴ること・トレースで原因が分かることを確かめる。その後 Runbook (`docs/runbooks/checkout-place-order.md`) を書く
- **2026-11-14: フェーズ 2 の通し稽古 (クラスタあり)**。障害の注入 → アラート → トレースで原因の特定、までつながった
  - multi-source の Application は一度で Synced / Healthy。Alertmanager は Running (メモリ 10 Mi)、Prometheus に configmap-reload が付いた。Sloth のルールが読み込まれ、Prometheus から Alertmanager が見えた
  - span_name は推測どおり `oteldemo.CheckoutService/PlaceOrder` (checkout と frontend の両方にある。SLO は `service_name="checkout"` で絞る)
  - flagd の `paymentFailure` を 50% にした (00:04 ごろ) → SLI (5 分) は 40% → **約 1.5〜2 分でアラート (page) が Alertmanager に届いた**
  - Jaeger: `payment charge` → `PaymentService/Charge` → checkout の `PlaceOrder` → frontend の `POST /api/checkout` (422) と、エラーが呼び出しをさかのぼるのが見えた (スクリーンショットは `docs/demo/images/phase2/rehearsal-*`)。トレースに `Incomplete` の表示が出た (原因は未確認)
  - 00:18:34 に off にしたが、13 分後もアラートは鳴ったまま。30 分と 6 時間の窓の条件 (6%) が成り立っているため (30 分の窓 21.9%)。Sloth の多窓のアラートとして正しい動き。解消までの時間は未計測
  - Runbook (`docs/runbooks/checkout-place-order.md`) を書いた (2026-11-14)。アラートの `runbook_url` のリンク先
  - 次: ポストモーテムの雛形と、通し稽古の分の 1 件目 → 動画の段取り表 → 動画を撮る

## 期限 (重要)
- 無料クレジットの期限は **2027-01-27**。課金アカウントは有料に切り替え済みなので、期限を過ぎると**実費で課金される**。
- **2027-01-26 までに** `terraform destroy` (platform → 本体) を済ませ、残っているリソースがないことを確認する。
- フェーズ 3 以降は、GKE を使わず kind で進められるものを優先する。

## 次にやること
- [x] GCP プロジェクトの作成、請求先アカウントのリンク、ADC の設定、最小限の API の有効化 (2026-11-08、ユーザーの端末で実行)
- [x] リポジトリの雛形: `README.md`、`.gitignore`、`.pre-commit-config.yaml`、`mise.toml` / `mise.lock` (2026-11-08)
- [x] `terraform/bootstrap/`: state 用のバケット、予算アラート (`EXCLUDE_ALL_CREDITS`)、Workload Identity Federation (2026-11-08 に apply)
- [x] `terraform/`: VPC、GKE (ゾーン型、Spot ノードプール)、Artifact Registry (2026-11-08 に apply → destroy で確認)
- [x] `terraform/platform/`: ArgoCD と、最初の Application (2026-11-11 に通しで確認)
- [x] `gitops/apps/`: OTel Demo の Application (2026-11-11 に通しで確認)
- [x] `.github/workflows/`: 検査 (fmt、tflint、trivy、gitleaks) と `terraform plan` (OIDC で鍵なし) (2026-11-11、run 43008527183 で checks・plan とも成功、`Plan: 13 to add`)
- [x] README (構成図、再現の手順) (2026-11-11)、初日の請求額の実測 (2026-11-11)
- [x] README の手順どおりに通しで動かし、手順とスクリーンショットを記録した (2026-11-13、[demo/phase1.md](demo/phase1.md))。動画ではなく記録とスクリーンショットにした (CLAUDE.md の「画面録画か手順の記録」)

## 決定事項

| 日付 | 決定 | ADR |
|---|---|---|
| 2026-11-08 | リージョンは東京 (asia-northeast1)。Terraform の変数にする | [0001](adr/0001-region-tokyo.md) |
| 2026-11-08 | GKE はゾーン型のクラスタ | [0002](adr/0002-zonal-cluster.md) |
| 2026-11-08 | ArgoCD は Terraform (`helm_release`) で入れて、ArgoCD 自身は Terraform が管理し続ける | [0003](adr/0003-argocd-bootstrap-by-terraform.md) |
| 2026-11-08 | Terraform を bootstrap・本体・platform の 3 つに分ける | [0004](adr/0004-terraform-split.md) |
| 2026-11-08 | ツールは、タグではなくチェックサム (`mise.lock`) とコミット SHA で固定する | [0005](adr/0005-pin-tools-by-checksum-and-sha.md) |
| 2026-11-08 | ArgoCD は認証なしでリポジトリを読む。クラスタを動かすときは public にする (公開の前に gitleaks で全履歴を検査した)。2026-11-11 時点では、動かしていない間は private に戻している | — |
| 2026-11-13 | SLO は Sloth の CLI で生成し、同梱の Prometheus と Alertmanager で評価・通知する。最初の SLO は checkout の注文の成功率 | [0006](adr/0006-slo-and-alerting.md) |

## 未確認のこと (確認したら、ここを更新する)
- 東京と他のリージョンの料金の差。Spot の在庫と回収の頻度
- GKE の管理手数料が無料枠で実際に相殺されているか (請求レポートのクレジットを含めた表示で確かめる)
- Network Intelligence Center の課金を止められるか (必要のない機能のため)
- LoadBalancer の料金 (今は port-forward なので使っていない)
- Cloud Billing API (価格表) の利用料金 (ドキュメントに記載なし)
- ゾーンをまたぐ通信の料金
- Claude の sandbox で、存在しない dotfile (`.bashrc` など) が `git status` に未追跡として出る現象 (Fedora の bubblewrap で発生) が、WSL でも起きるか。出たら無視し、`git add` しない
- kubelet がイメージの削除や Pod の追い出しを始めるディスクの使用率 (ノードのディスクを 50 GB にした理由。下の「実測の記録」)
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
- 2026-11-11: OTel Demo が動いている状態で `kubectl top` を測った。ノード (e2-standard-4、1 台) は CPU 1.5 コア (38%)、メモリ 7.6 GiB (58%)。メモリが多いのは opensearch 832 Mi、grafana 656 Mi、kafka 556 Mi。CPU は load-generator が 671m。→ e2-standard-4 の 1 台で足りる。
- 2026-11-11: Grafana で、ノードの `/mnt/stateful_partition` (イメージの置き場) が 25.4 GiB 中 21.0 GiB 使用 (約 83%) だった (ディスク 30 GB のとき)。→ 既定を 50 GB に上げた。
- 2026-11-11: `agent` は LLM の API キーなしで動いた (`USE_VCR=True` で録画した応答を再生する)。
- 2026-11-11: 請求レポート (プロジェクトで絞り込み、クレジットの適用前、11/8〜11/11) の合計は 36 円。【11/11 の分は反映しきっていない可能性がある】(管理手数料が 1.17 時間分しか出ていない)

  | SKU | 金額 | メモ |
  |---|---|---|
  | Zonal Kubernetes Clusters (1.17 時間) | 18 円 | 約 15.8 円 / 時間。無料枠で相殺されるはず (未確認) |
  | Spot E2 (CPU + メモリ) | 12 円 | ノード 1 台で約 16 円 / 時間。見積もりどおり |
  | Private Service Connect Partner Select End Point | 1.6 円 | 約 1.6 円 / 時間。想定外。private nodes のクラスタで使われるものと思われる (未確認) |
  | Network Intelligence Center (3 種類) | 約 1.4 円 | 想定外。自動で課金された |
  | Balanced PD Capacity (0.04 GiB・月) | 0.9 円 | 約 23 円 / GiB・月。50 GB なら約 1.6 円 / 時間 |
  | Cloud NAT (IP、ゲートウェイ) | 0.8 円 | 約 1 円 / 時間 |
  | E2 (通常) 0.1 時間 | 0.7 円 | 11/8 の最初の apply で一瞬作られた既定のノードプール |

  → 動かしている間の目安は約 21 円 / 時間 (管理手数料は無料枠で 0 円の前提)。
- 2026-11-11: 請求先アカウント全体のレポートには、別のプロジェクトの GPU (L4) の VM とディスク (約 14 GiB・月、4 日で約 300 円) も出ていた。このプロジェクトとは無関係。
(初日の請求額、Spot の回収の状況などを、ここに書く)

## bootstrap の state を失ったら
バックアップはとらない。リソースは 12 個だけで、`import` ブロックで戻せるため (bootstrap は最初の 1 回だけ apply し、destroy しない。ADR 0004)。
`terraform.tfvars` も失っていたら、`terraform.tfvars.example` から作り直す。

```bash
cd terraform/bootstrap
# 予算アラートの ID を調べる (出力の billingAccounts/.../budgets/ の後ろの部分)
gcloud billing budgets list --billing-account=<請求先アカウントの ID> 2>&1 | tee ../../out.txt
cp import.tf.example import.tf
terraform plan -var budget_id=<予算アラートの ID> -out=import.tfplan 2>&1 | tee ../../out.txt
terraform show -no-color import.tfplan | grep -E '^  # |^Plan:' > ../../bootstrap.plan.txt
```
期待する結果は `Plan: 12 to import, 0 to add, 0 to change, 0 to destroy`。`add` や `change` があれば apply しない。
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
- 【`terraform apply X | tee out.txt && rm X` は、apply が失敗しても rm が走る】パイプの終了ステータスは最後の tee のもの。先に `set -o pipefail` を実行する
- 【terraform を中断すると、GCS の state のロックが残ることがある】2026-11-08 に、中断した plan の provider のプロセスだけが残り、ロックが外れなかった。`ps` で terraform が動いていないことを確かめてから、`kill <provider の PID>` → `terraform force-unlock <ID>`
- 【フェーズ 1 の流れは GitHub に依存する】ArgoCD の chart (github.com の releases)、ArgoCD が読むリポジトリ、OTel Demo のイメージ (ghcr.io) は、すべて認証なしで GitHub から取得する。GitHub の障害中は動かない
- 【ArgoCD はリポジトリを認証なしで読む】リポジトリは public にしておく (2026-11-08 に決定。private のままにする場合は deploy key などが要る)
- 【クラスタを作り直すと、kubeconfig の接続先が古いまま】`gcloud container clusters get-credentials` をやり直す。やらないと kubectl が古い IP にタイムアウトする
- 【OTel Demo の values では Prometheus の configmapReload が無効】ルールを変えても読み直されない → 有効にした (ADR 0006)
- 【SLO の SLI は、一度もエラーが起きていないと「空」になる】エラーの指標 (status_code=ERROR の系列) がまだ存在しないため。一度起きれば 0 になる。ダッシュボードでは No data に見える
- 【Sloth の page のアラートは、障害を止めてもすぐには消えない】30 分と 6 時間の窓の条件 (エラー率 6%) が残るため。15 分間 40〜50% の失敗なら、止めてから 25〜30 分ほど鳴り続ける (推定)
- 【起動の直後は span_metrics にサービスがそろっていない】注文などの操作が流れるまで、その span の系列はない。確認は数分待ってから
- 【Alertmanager のサブチャートは既定で PVC を作る】クラスタごと消すと PD が残るおそれ → 永続ディスクを無効にした
- 【OTel Demo の `agent-fixtures` の ConfigMap は約 750 KB】ArgoCD の既定 (client-side apply) では annotation の上限 256 KiB を超えて作れない → `ServerSideApply=true`
- 【ArgoCD の自動同期は、同じ版で一度失敗すると再挑戦しないことがある】syncOptions を直しても同期されなかったので、`kubectl -n argocd patch application <名前> --type merge -p '{"operation":{"sync":{...}}}'` で 1 回だけ同期を指示した (挙動の仕様は未確認)
- 【`server.insecure` の ArgoCD は http で開く】https で開くと接続を切られる

## 後でやる
(今のフェーズで不要なものは、ここに書いて止める)
- フェーズ 3: Alertmanager の通知先を Slack などにする (Webhook の URL を External Secrets で渡す)
- 同梱の Grafana のアラート `CartAddItemHighLatency` は、chart の不具合 (`.yml` と `*.yaml`) で読み込まれていない。上流に報告するかは未定
- フェーズ 3: Artifact Registry の置き場所を決める。本体にあると destroy のたびにイメージが消え、同じ名前ですぐ作り直せるかも未確認 (ADR 0004 の追記)
