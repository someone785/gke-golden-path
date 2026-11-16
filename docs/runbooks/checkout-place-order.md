# Runbook: CheckoutPlaceOrderErrorBudgetBurn

checkout の注文 (PlaceOrder) の失敗が増え、SLO のエラーバジェットを速く消費しているときに鳴るアラート。
アラートの定義は [checkout.sloth.yaml](../../gitops/workloads/otel-demo/slo/checkout.sloth.yaml)、設計の理由は [ADR 0006](../adr/0006-slo-and-alerting.md)。

## 概要
| 項目 | 内容 |
|---|---|
| SLO | checkout の `oteldemo.CheckoutService/PlaceOrder` の成功率 99% (30 日) |
| SLI | span_metrics の `traces_span_metrics_calls_total` のうち、`status_code="STATUS_CODE_ERROR"` の割合 |
| 利用者への影響 | 注文ボタンを押すとエラーになる (frontend の `POST /api/checkout` が 422) |
| `severity=page` | 速い燃え方。すぐに対応する。5 分と 1 時間の窓でエラー率 14.4% 超、または 30 分と 6 時間の窓で 6% 超 |
| `severity=ticket` | 遅い燃え方。営業時間内に対応する。2 時間と 1 日の窓でエラー率 3% 超、または 6 時間と 3 日の窓で 1% 超 |

【checkout はアラートが鳴る場所であって、原因の場所とは限らない】checkout は cart、product-catalog、currency、shipping、payment、email などを呼ぶ。原因はトレースで呼び出し先をたどって探す。

## 1. 画面を開く (1 分)
```bash
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080   # Shop、Jaeger、Grafana、flagd
kubectl -n otel-demo port-forward svc/prometheus 9090:9090
kubectl -n otel-demo port-forward svc/alertmanager 9093:9093
```

| 画面 | URL |
|---|---|
| Alertmanager | http://localhost:9093/ |
| Prometheus のアラート | http://localhost:9090/alerts |
| Jaeger | http://localhost:8080/jaeger/ui/ |
| flagd (機能フラグ) | http://localhost:8080/feature |

## 2. 影響の大きさを確かめる (2 分)
今のエラー率 (5 分の窓):
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=slo:sli_error:ratio_rate5m{sloth_service="checkout"}'
```
- 0.4 なら、注文の 40% が失敗している。
- 結果が空なら、まだ一度もエラーが記録されていない (指標の系列がない)。

## 3. 原因のサービスを絞り込む (3 分)
### メトリクスで当たりを付ける
エラーを出している span を、サービスごとに並べる:
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=sort_desc(sum by (service_name, span_name) (rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])))'
```
- checkout、frontend、frontend-proxy (frontend の手前のプロキシ) 以外のサービスが出ていたら、そこが原因の候補。
- 【メトリクスだけでは発生源を決められない】1 回の失敗した注文が、呼び出しの経路にあるすべての span にエラーとして残るので、上位の行は同じ値になる (2026-11-17 のデモ)。発生源はトレースで確かめる。

### トレースで確かめる
1. Jaeger で Service を `checkout`、Attributes (Tags) に `error=true` を入れて Find Traces。
2. 失敗したトレースを 1 つ開く。
3. 赤い印 (エラー) の付いた span を、**呼び出し先の方向 (下)** にたどる。赤い印が付いている**一番深い span** が発生源。
4. その span の Tags と Logs で、エラーの内容 (例外のメッセージなど) を読む。
   【span の詳細の Resource の行には、プロジェクト ID (`cloud.account.id`) が出る】画面を共有・撮影するときは隠す。

例 (2026-11-14 の通し稽古。payment が原因のとき):
```
frontend  POST /api/checkout (422)          ← 利用者に見える症状
frontend  oteldemo.CheckoutService/PlaceOrder
checkout  oteldemo.CheckoutService/PlaceOrder ← SLO で測っている span
checkout  oteldemo.PaymentService/Charge (呼び出し)
payment   oteldemo.PaymentService/Charge
payment   charge                             ← 発生源
```
cart、product-catalog、currency、shipping、quote の span は正常 (200) だった。

## 4. 原因ごとの対応
### 機能フラグ (flagd) が有効になっている
この環境の障害の多くは、OTel Demo の flagd のフラグで起こせる。**最初に確かめる。**
1. http://localhost:8080/feature を開く。
2. `off` 以外になっているフラグを探す。checkout の注文に効くもの:

   | フラグ | 症状 |
   |---|---|
   | `paymentFailure` | payment の Charge が n% 失敗する |
   | `paymentUnreachable` | payment に接続できない |
   | `cartFailure` | cart が n% 失敗する |
   | `productCatalogFailure` | 特定の商品で product-catalog が失敗する |

3. `off` に戻して保存する。
4. 誰が・なぜ有効にしたかを確かめ、ポストモーテムに書く。

### 特定のサービスの Pod が落ちている・再起動を繰り返している
```bash
kubectl -n otel-demo get pods
kubectl -n otel-demo describe pod <Pod の名前>
kubectl -n otel-demo logs <Pod の名前> --previous
```
- 【`kubectl` での直接の変更は一時的な対処だけにする】恒久的な直し (リソースの上限など) は、Git の values を直して ArgoCD に反映させる。

### 直前に変更を反映していた
- ArgoCD (`kubectl -n argocd port-forward svc/argocd-server 8081:80` → http://localhost:8081) で、otel-demo の同期の履歴を見る。
- 直前の変更が原因なら、Git で revert して ArgoCD に反映させる。

## 5. 直ったことを確かめる
1. 2. の 5 分の窓のエラー率が **0** に下がる (対応してから数分)。
2. Jaeger で、新しいトレースに `error=true` のものが出なくなる。

【アラートは、直してもすぐには消えない】page のアラートには「30 分と 6 時間の窓でエラー率 6% 超」という条件もある。
障害中の失敗が 30 分の窓に残る間は鳴り続ける (通し稽古では、15 分間 40〜50% の失敗のあと、止めてから 13 分後もまだ鳴っていた)。
**5 分の窓が 0 に戻っていれば対応は終わり**。アラートが消えるのを待つ必要はない。消えないことを理由に、別の対処を重ねない。

【ticket はさらに長く鳴る】ticket の条件は「2 時間と 1 日の窓で 3% 超」または「6 時間と 3 日の窓で 1% 超」。
クラスタを作ってから 2 時間以内は、これらの窓がすべて「起動してから今まで」になり、障害中のエラーが抜けない。
2026-11-17 のデモでは、page は対処から約 25 分で解消したが、ticket は 40 分たっても鳴っていた (作っては消す運用では、ほぼクラスタを消すまで鳴る)。

窓ごとの値を見るときは:
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query={__name__=~"slo:sli_error:ratio_rate(5m|30m|1h|6h)", sloth_service="checkout"}'
```

## 6. 後で行うこと
- [docs/postmortems/](../postmortems/) にポストモーテムを書く (いつ・何が起き・どう気付き・どう特定し・どう直したか、再発の防止)。
- この Runbook で足りなかった手順があれば、ここに足す。
