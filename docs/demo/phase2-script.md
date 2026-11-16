# フェーズ 2 のデモの段取り表

フェーズ 2 の完了の条件「障害を起こしてから原因を特定するまでを、スクリーンショットと時系列で記録してある」のための段取り。
筋書きは、2026-11-14 の通し稽古 ([ポストモーテム](../postmortems/2026-11-14-payment-failure-rehearsal.md)) と同じ。
動画にしなかった理由は `docs/progress.md` (2026-11-14)。

**見せたい流れ**: 障害を入れる → 利用者に症状が出る → 約 2 分でアラートが鳴る → Runbook に沿って、トレースで原因 (payment) を特定する → 直す → 回復を確かめる

- かかる時間: クラスタの作成から destroy まで約 1〜1.5 時間 (約 21〜30 円)。アラートの解消まで測るなら、さらに約 30 分 (約 10 円)
- 成果物: `docs/demo/phase2.md` (時系列とスクリーンショット)、ポストモーテム (本番の分)

## 準備

### 1. クラスタを作る
README の手順 3・4 のとおり (public にする → 本体 → `get-credentials` → platform)。

### 2. 待つ (Healthy になってから 10 分以上)
- 【起動の直後は span_metrics に checkout の系列がない】load-generator の注文が流れるまで待つ。
- 次の問い合わせで、checkout の PlaceOrder の系列があることを確かめる (port-forward の後):
  ```bash
  curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=count(traces_span_metrics_calls_total{service_name="checkout",span_name="oteldemo.CheckoutService/PlaceOrder"})'
  ```
  `"result":[]` でなければよい。

### 3. port-forward (4 つの端末)
```bash
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
kubectl -n otel-demo port-forward svc/prometheus 9090:9090
kubectl -n otel-demo port-forward svc/alertmanager 9093:9093
kubectl -n argocd port-forward svc/argocd-server 8081:80
```

### 4. ブラウザのタブを、使う順に開いておく
| # | タブ | URL |
|---|---|---|
| 1 | Prometheus のアラート | http://localhost:9090/alerts |
| 2 | flagd | http://localhost:8080/feature |
| 3 | Astronomy Shop | http://localhost:8080/ |
| 4 | Alertmanager | http://localhost:9093/ |
| 5 | Prometheus の問い合わせ (下の式を入れておく) | http://localhost:9090/graph |
| 6 | Jaeger (Service = `checkout`、Attributes = `error=true` を入れておく) | http://localhost:8080/jaeger/ui/ |

タブ 5 に入れておく式 (Runbook の手順 3):
```
sort_desc(sum by (service_name, span_name) (rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])))
```

### 5. 時刻の記録
【手での記録は続かない】2026-11-17 のデモでは、画面の操作と撮影で手が足りず、`echo` での記録は最初の 1 回だけになった。
時刻は、後から API で取り戻せる。手での記録は補助にする:
- アラートが鳴った時刻: `curl -s http://localhost:9090/api/v1/alerts` の `activeAt`
- 最初と最後のエラー: Jaeger の API (`http://localhost:8080/jaeger/ui/api/traces?service=checkout&tags={"error":"true"}&lookback=1h`) のトレースの開始時刻
- 回復した時刻: `slo:sli_error:ratio_rate5m` を `query_range` で問い合わせ、0 になった時刻

各場面で、別の端末で次を実行する。`<出来事>` は下の表の「時刻の記録」の列の言葉にする:
```bash
echo "$(date +%T) <出来事>" | tee -a ~/projects/gke-golden-path/out.txt
```

### 6. スクリーンショットの注意
- 【写さない】ArgoCD のパスワード、プロジェクト ID (gcloud の出力、ブラウザの他のタブ、**Jaeger の span の詳細の Resource の行**)、通知
- 置き場所は `docs/demo/images/phase2/`。ファイル名は下の表のとおり (撮ったものを貼ってもらえれば、Claude が名前を付けて置く)

## 本番

| 場面 | 画面 | 操作 | 撮るもの (ファイル名) | 時刻の記録 |
|---|---|---|---|---|
| 1. 平常 | Prometheus のアラート | 開くだけ | `CheckoutPlaceOrderErrorBudgetBurn` が `inactive` (`01-alert-inactive.png`) | `baseline` |
| 2. 障害を入れる | flagd | `paymentFailure` を `50%` にして保存 | 保存した後の flagd の画面 (`02-flagd-payment-failure-50.png`) | `inject` |
| 3. 症状 | Shop | 商品をカートに入れて注文する。成功したら、もう 1〜2 回試す | 注文が失敗した画面 (`03-shop-order-failed.png`)。表示のされ方は未確認 | `symptom` |
| 4. 検知 | Prometheus のアラート | 鳴るまで再読み込み (約 2 分) | `firing` になったところ (`04-alert-firing.png`) | `fired` |
| 5. 通知 | Alertmanager | アラートを開く | `severity=page`、要約、`runbook_url` (`05-alertmanager.png`) | — |
| 6. 絞り込み | Prometheus の問い合わせ | タブ 5 の式を実行 (Table の表示) | payment がエラーを出している (`06-errors-by-service.png`) | — |
| 7. 特定 | Jaeger | Find Traces → エラーのトレースを 1 つ開く → payment の `charge` の span をクリックして Tags / Logs を開く | トレースの一覧 (`07-jaeger-error-traces.png`)、赤い印をたどった画面 (`08-jaeger-root-cause.png`)、`charge` の span の詳細 (`09-jaeger-error-detail.png`) | `identified` |
| 8. 対処 | flagd | `paymentFailure` を `off` にして保存 | (撮らなくてよい) | `mitigated` |
| 9. 回復 | Prometheus の問い合わせ | 5 分ほど待ち、下の式 A を実行 | 5 分の窓が 0 (`10-sli-recovered.png`) | `recovered` |
| 10. 鳴り続けるアラート | Prometheus の問い合わせ → アラート | 下の式 B を実行 | 30 分の窓が 6% を超えていて、アラートはまだ `firing` (`11-alert-still-firing.png`) | — |

式 A (場面 9):
```
slo:sli_error:ratio_rate5m{sloth_service="checkout"}
```
式 B (場面 10。窓ごとの値):
```
{__name__=~"slo:sli_error:ratio_rate(5m|30m|1h|6h)", sloth_service="checkout"}
```

### うまくいかなかったとき
- 4. で 5 分たっても鳴らない: 式 A と `slo:sli_error:ratio_rate1h{sloth_service="checkout"}` を問い合わせ、14.4% (0.144) を超えているかを見る。超えていなければ、`paymentFailure` を `100%` にする。
- 7. でエラーのトレースが見つからない: Lookback を `Last 15 minutes` にし、Find Traces を押し直す。
- `Incomplete` の表示が出たトレースは避けて、別のトレースを開く。

## 後片付け
1. (任意) アラートが解消するまでの時間を測る。`off` にしてから約 30 分かかる見込み。5 分ごとに次を実行し、`[]` になったら時刻を記録する (`resolved`):
   ```bash
   curl -s http://localhost:9093/api/v2/alerts | head -c 300; echo
   ```
2. README の手順 6 で destroy し、リポジトリを private に戻す。
3. `out.txt` (時刻の記録) とスクリーンショットを Claude に渡し、`docs/demo/phase2.md` とポストモーテム (本番の分) を書く。
