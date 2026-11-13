# ADR 0006: SLO は Sloth の CLI で生成し、同梱の Prometheus と Alertmanager で評価・通知する

- 状態: 決定
- 日付: 2026-11-13

## 背景
- フェーズ 2 では、SLO とアラートを付け、障害の注入 → 検知 → トレースで原因の特定、までを見せる。
- CLAUDE.md の方針で、監視の部品は OpenTelemetry Demo の chart (0.42.6) に同梱のものと役割が重ならないようにし、足す前に同梱のもので足りないかを確かめる。
- chart 0.42.6 を取得して確かめたこと (2026-11-13、`helm template` と values の確認):
  - 同梱の Prometheus は prometheus-community の chart (v3.14.0) で、**Prometheus Operator ではない**。`PrometheusRule` などの CRD はなく、ルールは values の `serverFiles` に書く。
  - 同梱の **Alertmanager** (サブチャート) は、OTel Demo の values で無効にされている。有効にすると、Prometheus の設定に宛先が自動で入る。
  - 【`configmapReload` も無効】ルールを変えても Prometheus が読み直さない (Deployment に設定の checksum の annotation もない)。
  - 同梱の OTel Collector の `span_metrics` が、トレースから `traces_span_metrics_calls_total` などを作っている。ラベルは `service_name`、`span_name`、`status_code` (同梱のダッシュボードの式で確認)。
  - 同梱の Grafana には `CartAddItemHighLatency` というアラートの定義があるが、ファイル名が `.yml` で、テンプレートが `*.yaml` を探すため**読み込まれていない** (`grafana-alerting` の ConfigMap が空)。

## 選択肢
### SLO のルールの作り方
1. ルールを手で書く: 多窓のバーンレートのアラートは式が長く、間違えやすい
2. **Sloth の CLI で生成し、生成物を Git に置く**
3. Sloth の operator をクラスタに入れる: 出力は `PrometheusRule` で、同梱の Prometheus では読めない。Prometheus Operator を足すと、同梱の Prometheus と役割が重なる

### アラートの評価と通知
1. **同梱の Prometheus で評価し、同梱の Alertmanager で通知する**
2. Grafana のアラート (Grafana 内蔵の Alertmanager): Sloth の出力 (Prometheus のルール) をそのまま使えない

### SLI
1. **span_metrics (トレースから作られるメトリクス)**: アプリに計装を足さずに済む
2. アプリの HTTP / gRPC のメトリクス: サービスごとに言語と名前が違う

## 決定
- SLO は `gitops/workloads/otel-demo/slo/*.sloth.yaml` に書き、`scripts/gen-slo-rules.sh` で Sloth の CLI からルールを生成して、chart に渡す values (`values-slo-rules.yaml`) にする。生成物も Git に置く。
- CI で `scripts/gen-slo-rules.sh --check` を実行し、生成物が SLO の定義と一致すること、promtool の検査に通ることを確かめる。
- ArgoCD の Application を multi-source にし、chart は Helm のリポジトリから、values はこの Git のリポジトリから読む。
- 同梱の Alertmanager と、Prometheus の `configmapReload` を有効にする。Alertmanager の永続ディスクは使わない。
- 最初の SLO は **checkout の注文 (PlaceOrder) の成功率 99%**。障害は flagd の `paymentFailure` で起こし、症状 (checkout) と原因 (payment) が別のサービスになる筋書きにする。
- 通知先は、まず Alertmanager の画面だけにする。Slack などは Webhook の URL (秘密) が要るので、フェーズ 3 の External Secrets の後にする。
- Sloth、promtool、helm (`helm template` での確認用) は mise で入れ、チェックサムで固定する (ADR 0005)。promtool は同梱の Prometheus と版をそろえる。

## 結果
- 新しい部品をクラスタに足さずに、SLO とアラートが付く。
- 【生成物を手で直さない】SLO の定義を直して、スクリプトで生成し直す。CI が不一致を検出する。
- 【chart を上げたら、同梱の Prometheus の版と、Alertmanager・configmapReload の values のキーが変わっていないか確かめる】`helm template` で確認する。
- 【SLO の期間は 30 日だが、クラスタは使うときだけ動かす】エラーバジェットの残量は意味のある値にならない。デモで見せるのは、バーンレートのアラートが鳴ることと、そこからトレースで原因を特定する流れ。
- 未確認:
  - Prometheus での `span_name` の実際の値 (`oteldemo.CheckoutService/PlaceOrder` と推測)
  - `paymentFailure` のとき、checkout の PlaceOrder の span が `STATUS_CODE_ERROR` になるか
  - Alertmanager を有効にしたときの、メモリの使用量
