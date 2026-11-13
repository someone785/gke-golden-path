# フェーズ 2 の動画の段取り表

フェーズ 2 の完了の条件「障害を起こしてから原因を特定するまでのデモ動画がある」のための段取り。
筋書きは、2026-11-14 の通し稽古 ([ポストモーテム](../postmortems/2026-11-14-payment-failure-rehearsal.md)) と同じ。

**見せたい流れ**: 障害を入れる → 利用者に症状が出る → 約 2 分でアラートが鳴る → Runbook に沿って、トレースで原因 (payment) を特定する → 直す → 回復を確かめる

- 動画の長さの目安: 編集後に 5〜7 分 (待ち時間は切るか早送りにする)
- 撮影にかかる時間: クラスタの作成から destroy まで約 1.5 時間 (約 30 円)。アラートの解消まで測るなら、さらに約 30 分

## 撮影の前 (録画しない)

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

### 4. ブラウザのタブを、見せる順に開いておく
| # | タブ | URL |
|---|---|---|
| 1 | ArgoCD (ログインしておく) | http://localhost:8081/ |
| 2 | Astronomy Shop | http://localhost:8080/ |
| 3 | flagd | http://localhost:8080/feature |
| 4 | Prometheus のアラート | http://localhost:9090/alerts |
| 5 | Alertmanager | http://localhost:9093/ |
| 6 | Prometheus の問い合わせ (Runbook の手順 3 の式を入れておく) | http://localhost:9090/graph |
| 7 | Jaeger (Service = `checkout`、Attributes = `error=true` を入れておく) | http://localhost:8080/jaeger/ui/ |

Prometheus のタブ 6 に入れておく式 (Runbook の手順 3):
```
sort_desc(sum by (service_name, span_name) (rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])))
```

### 5. 画面を整える
- 【写さない】ArgoCD のパスワード、プロジェクト ID (gcloud の出力、ブラウザの他のタブ)、通知、ブックマークバー
- ブラウザの表示を 110〜125% に拡大する (動画で字が読めるように)
- 時刻を記録する準備。各場面で、別の端末で次を実行する (録画には写さなくてよい):
  ```bash
  echo "$(date +%T) <出来事>" | tee -a ~/projects/gke-golden-path/out.txt
  ```

### 6. 録画のツールを試す
Windows の Snipping Tool の画面録画、または Xbox Game Bar (Win+Alt+R) を使う想定。**今の環境で使えるかは未確認**なので、10 秒ほど試し撮りして、字が読めるかを確かめる。

## 撮影 (録画する)

| 場面 | 時間 | 画面 | 操作 | 見せたいこと (話すなら) | 時刻の記録 |
|---|---|---|---|---|---|
| 1. 平常 | 30 秒 | ArgoCD → Prometheus のアラート → Alertmanager | 一覧を見せるだけ | Git から入った OTel Demo が Healthy。SLO のアラートは `inactive`、Alertmanager は空 | — |
| 2. 障害を入れる | 20 秒 | flagd | `paymentFailure` を `50%` にして保存 | 「payment が半分失敗するようにする」 | `inject` |
| 3. 症状 | 30 秒 | Shop | 商品をカートに入れて注文する | 注文が失敗する (画面にどう出るかは未確認。成功したら、もう 1〜2 回試す) | — |
| 4. 検知 | 約 2 分 (待ちは切る) | Prometheus のアラート → Alertmanager | 鳴るまで待つ | `CheckoutPlaceOrderErrorBudgetBurn` が `firing`。Alertmanager に `severity=page`、日本語の要約、Runbook の URL | `fired` |
| 5. Runbook | 20 秒 | GitHub の Runbook | Alertmanager の `runbook_url` を開く | 対応の手順がアラートから 1 クリック | — |
| 6. 絞り込み (メトリクス) | 20 秒 | Prometheus の問い合わせ | タブ 6 の式を実行 | checkout と frontend 以外に、payment がエラーを出している | — |
| 7. 特定 (トレース) | 1〜2 分 | Jaeger | Find Traces → エラーのトレースを 1 つ開く → 赤い印を下へたどる → payment の `charge` を開いて Tags / Logs を見せる | アラートが鳴ったのは checkout、原因は payment。cart などは正常 | `identified` |
| 8. 対処 | 20 秒 | flagd | `paymentFailure` を `off` にして保存 | Runbook の手順 4 | `mitigated` |
| 9. 回復 | 約 5 分 (待ちは切る) | Prometheus の問い合わせ → Jaeger | 5 分の窓の SLI を問い合わせ、0 になるのを見せる。Jaeger で新しいエラーが出ないことを見せる | 「アラートはまだ鳴っているが、30 分の窓の条件のため。5 分の窓が 0 なら対応は終わり」(Runbook の手順 5) | `recovered` |
| 10. 締め | 20 秒 | ポストモーテム (GitHub) | 開いて見せる | 時系列と対策を残して終わり | — |

場面 9 で使う問い合わせ:
```
slo:sli_error:ratio_rate5m{sloth_service="checkout"}
```

### うまくいかなかったとき
- 4. で 5 分たっても鳴らない: Prometheus で `slo:sli_error:ratio_rate5m` と `ratio_rate1h` を問い合わせ、14.4% を超えているかを見る。超えていなければ、`paymentFailure` を `100%` にする。
- 7. でエラーのトレースが見つからない: Lookback を `Last 15 minutes` にし、Find Traces を押し直す。
- `Incomplete` の表示が出たトレースは避けて、別のトレースを開く。

## 撮影の後 (録画しない)
1. (任意) アラートが解消するまでの時間を測る。`off` にしてから約 30 分かかる見込み (約 10 円)。5 分ごとに次を実行し、`[]` になった時刻を記録する:
   ```bash
   curl -s http://localhost:9093/api/v2/alerts | head -c 300; echo
   ```
2. README の手順 6 で destroy し、リポジトリを private に戻す。
3. 記録した時刻を送ってもらい、ポストモーテムと `docs/demo/phase2.md` (動画のリンクと時刻) を書く。
4. 動画の置き場所を決める (リポジトリに入れるか、YouTube の限定公開などにするか)。
