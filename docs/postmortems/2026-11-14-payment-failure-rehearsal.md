# ポストモーテム: payment の失敗による注文のエラー (通し稽古)

- 日付: 2026-11-14
- 状態: 確定
- 書いた人: someone785 (Claude と一緒に作成)
- 関係するアラート: `CheckoutPlaceOrderErrorBudgetBurn` (`severity=page`)
- Runbook: [checkout-place-order.md](../runbooks/checkout-place-order.md)

> 【これは意図して起こした障害】フェーズ 2 の通し稽古として、OTel Demo の flagd の `paymentFailure` を有効にした。
> 利用者は OTel Demo の load-generator だけで、実際の利用者への影響はない。
> 検知から原因の特定までの流れが働くかを確かめるのが目的。

## 要約
payment の Charge が 50% の確率で失敗するようにしたところ、checkout の注文 (PlaceOrder) の約 40〜50% が失敗した。
約 1.5 分で SLO のバーンレートのアラート (page) が鳴り、Jaeger のトレースで発生源が payment だと特定できた。
フラグを `off` に戻して回復したが、アラートは遅い燃え方の条件で、その後も鳴り続けた。

## 影響
| 項目 | 内容 |
|---|---|
| 期間 | 約 00:04 〜 00:18:34 (約 15 分) |
| 利用者への影響 | 注文の約 40〜50% が失敗 (frontend の `POST /api/checkout` が 422)。利用者は load-generator だけ |
| SLO への影響 | 5 分の窓のエラー率が最大 40% (目標の失敗の上限は 1%)。30 日の SLO の期間に対して、クラスタは数時間しか動いていないため、エラーバジェットの残量は意味のある値にならない (ADR 0006) |

## 時系列 (JST)
| 時刻 | 出来事 | 根拠 |
|---|---|---|
| 00:03〜00:04 ごろ | flagd で `paymentFailure` を `50%` にした (障害の開始) | 操作した人の記憶。最初のエラーのトレースが 00:04:00.814 |
| 00:05:29 | アラート `CheckoutPlaceOrderErrorBudgetBurn` (page) が Alertmanager に届いた | Alertmanager の `startsAt` (15:05:29Z) |
| 00:05 以降 | SLI (5 分の窓) のエラー率が 40% | Prometheus の `slo:sli_error:ratio_rate5m` |
| 〜00:13 ごろ | Jaeger で checkout の `error=true` のトレースを検索し、1 つを開いて、発生源が payment の `charge` だと特定した | Jaeger の画面 (開いたトレースは 00:13:44 のもの) |
| 00:18:34 | flagd で `paymentFailure` を `off` に戻した (対処) | 操作した人の記録 |
| 00:31:57 までに | SLI (5 分の窓) が 0 に戻った (回復) | Prometheus |
| 00:31:57 | アラートはまだ鳴っていた。30 分の窓のエラー率 21.9%、6 時間の窓 21.3% (どちらも 6% 超) | Prometheus、Alertmanager (`state: active`) |
| — | アラートの解消は見届けずに、クラスタを destroy した | 費用を抑えるため |

| 指標 | 値 |
|---|---|
| 検知までの時間 (開始 → アラート) | 約 1.5〜2 分 |
| 特定までの時間 (アラート → 原因の特定) | 10 分以内 (正確な時刻は記録していない。初めて画面を操作しながらの値) |
| 回復までの時間 (開始 → 回復) | 約 15 分 + 5 分の窓が 0 に戻るまで (数分) |

## 原因
- **直接の原因**: flagd の `paymentFailure` を `50%` にしたため、payment の `oteldemo.PaymentService/Charge` が半分の確率でエラーを返した。
- checkout は注文の処理の中で payment の Charge を呼ぶ。Charge が失敗すると注文 (PlaceOrder) 全体がエラーになり、frontend は利用者に 422 を返した。
- checkout の側には、payment の失敗をやり直す仕組み (リトライ) や、失敗を利用者に見せない仕組みはない (OTel Demo の作り)。

## 検知と特定
1. **検知**: Sloth で生成した多窓のバーンレートのアラートが、5 分と 1 時間の窓でエラー率 14.4% を超えたことで鳴った。
2. **影響の確認**: Prometheus で SLI (5 分の窓) が 40% と確認した。
3. **特定**: Jaeger で Service を `checkout`、`error=true` で検索すると、14 件のエラーのトレースがあった。1 つを開き、赤い印 (エラー) を呼び出し先へたどった:
   ```
   frontend  POST /api/checkout (422)          ← 利用者に見える症状
   frontend  oteldemo.CheckoutService/PlaceOrder
   checkout  oteldemo.CheckoutService/PlaceOrder ← SLO で測っている span (アラートが鳴った場所)
   checkout  oteldemo.PaymentService/Charge (呼び出し)
   payment   oteldemo.PaymentService/Charge
   payment   charge                             ← 発生源
   ```
   同じトレースの cart、product-catalog、currency、shipping、quote は正常 (200) だった。
   スクリーンショット: [エラーのトレースの一覧](../demo/images/phase2/rehearsal-jaeger-error-traces.png)、[原因の span](../demo/images/phase2/rehearsal-jaeger-payment-root-cause.png)

## うまくいったこと
- アプリに計装を足さずに、トレースから作られる指標 (span_metrics) だけで SLO とアラートが働いた。
- 障害の開始から約 1.5〜2 分で検知できた。
- アラートが鳴った場所 (checkout) と原因の場所 (payment) が違っても、トレースで 1 本の呼び出しの流れとして追えた。
- アラートに Runbook の URL と日本語の要約が付いていた。

## うまくいかなかったこと
- **アラートが誰にも届かない**。通知先は Alertmanager の画面だけで、人が画面を見ていないと気付けない。
- **回復してもアラートが鳴り続けた**。遅い燃え方の条件 (30 分と 6 時間の窓で 6% 超) が残るため。Sloth の設計どおりだが、知らないと「まだ直っていない」と誤解して、別の対処を重ねるおそれがある。
- **障害が起きる前は、SLI の値が「空」だった**。エラーの系列がまだ存在しないため。ダッシュボードでは No data に見え、計測が壊れているのと区別しにくい。
- 時刻の記録が不十分で、特定までの時間を正確に出せなかった。
- Jaeger のトレースに `Incomplete` (span の一部が欠けている) と表示された。原因は未確認。

## 運が良かったこと
- 原因が 1 つのサービス (payment) に閉じていて、トレースの赤い印をたどるだけで行き着けた。複数のサービスが同時に壊れると、こう単純にはいかない。
- 障害を起こしたのが自分 (flagd の操作) だったので、Runbook の「最初に flagd のフラグを確かめる」がそのまま当たった。

## 対策
| 対策 | 種類 | 担当 | 期限 | 状態 |
|---|---|---|---|---|
| Runbook に「アラートは直してもすぐには消えない。5 分の窓が 0 なら対応は終わり」と書く | 手順 | someone785 | 2026-11-14 | 済 ([Runbook の 5.](../runbooks/checkout-place-order.md#5-直ったことを確かめる)) |
| Alertmanager の通知先を Slack などにする (Webhook の URL は External Secrets で渡す) | 検知 | someone785 | フェーズ 3 | 未着手 (`docs/progress.md` の「後でやる」) |
| デモの本番で、時刻を記録し (開始・検知・特定・対処・回復・解消)、アラートが解消するまでの時間を測る | 手順 | someone785 | フェーズ 2 のデモ | 未着手 (段取り表に入れた) |
| SLI が「空」のとき、ダッシュボードで 0 として見せる (`or vector(0)` など) かを検討する | 検知 | someone785 | 未定 | 未着手 |
| Jaeger の `Incomplete` の原因を調べる | 検知 | someone785 | 未定 | 未着手 |
