# フェーズ 3 の計画

完了の条件: 「このプロジェクトで示したいこと」(CLAUDE.md) の 1〜5 が通しで動く。

1. 開発者がテンプレート (ゴールデンパス) から新しいサービスを作る
2. PR を出すと、CI がテスト・脆弱性検査・SBOM 作成・イメージ署名を行う
3. マージすると、ArgoCD が dev にデプロイし、確認後に prod へ昇格する
4. Kyverno が署名のないイメージや方針違反を拒否する
5. ダッシュボードと SLO・アラートが自動で付く

## 前提と決めたこと (2026-11-17)
- 【GKE を使わず kind で進められるものを優先する】(CLAUDE.md)。GKE を使うのは、kind ではできないもの (Workload Identity が要るもの、OTel Demo の監視の部品と組み合わせるもの) と、最後の通しの確認だけ。
- 手元の環境: Docker 29.9.3、メモリ 11 GB、6 コア。OTel Demo を丸ごと (約 8 GB) kind で動かすのは厳しいので、kind では ArgoCD・Kyverno・自分のサービスだけを動かす。
- **イメージの置き場所は GHCR** (GitHub Container Registry)。CI は `GITHUB_TOKEN` で push (鍵なし)、kind も GKE も認証なしで pull できる。→ ADR 0007 に書く
  - 【未確認】リポジトリを private にしている間も、GHCR のパッケージだけ public にできるか。
  - Terraform の Artifact Registry は使わなくなる。消すかどうかは ADR 0007 で決める (`docs/progress.md` の「後でやる」の Artifact Registry の置き場所の件は、これで片付く)。
- **サービスの言語は Go**。1 つの静的なバイナリを distroless のイメージに入れる。OTel の SDK で計装し、トレースから span_metrics が作られるようにする (フェーズ 2 の SLO と同じ仕組みに乗せるため)。

## 決めること (ADR に書く)
| ADR | 内容 | 案 |
|---|---|---|
| 0007 | イメージの置き場所 | GHCR (上記) |
| 0008 | 署名と SBOM | Cosign の keyless 署名 (GitHub Actions の OIDC → Sigstore)。**鍵ファイルを作らない**方針と合う。SBOM は Syft で作り、Cosign で attestation としてイメージに付ける。イメージは digest で参照する |
| 0009 | dev / prod の分け方 | 費用のため、1 つのクラスタに namespace を 2 つ。Kustomize の overlay (`overlays/dev`、`overlays/prod`)。昇格は、prod の overlay のイメージの digest を書き換える PR |
| 0010 | Kyverno のポリシーの種類 | ImageValidatingPolicy と ValidatingPolicy (CEL) |
| 0011 | テンプレートの作り方 | `templates/service-go/` を雛形にし、`scripts/new-service.sh` でコピーして名前を置き換える (Backstage はフェーズ 4) |

【未確認】Cosign の keyless 署名を Kyverno で検証するときの設定 (issuer、subject の書き方)、SBOM の attestation の検証の書き方。実装の前に公式のドキュメントで確かめる。

## 進め方 (各ステップの終わりで、動くものを見せられるようにする)

| # | 内容 | 流れ | 場所 | 見せるもの |
|---|---|---|---|---|
| 1 | **自分のサービス**を Go で書く (HTTP の API 1 つ、`/healthz`、OTel の計装、テスト)。Dockerfile (distroless) | 1 | 手元 | `docker run` で動き、テストが通る |
| 2 | **CI** にイメージのビルドを足す: テスト → trivy でイメージを検査 → GHCR に push → Syft で SBOM → Cosign で keyless 署名と SBOM の attestation | 2 | GitHub Actions | PR で CI が通り、`cosign verify` で署名が確かめられる |
| 3 | **kind** のクラスタと ArgoCD を手元で作るスクリプト (冪等)。kind・ArgoCD の版は mise とスクリプトで固定 | 3 の準備 | kind | `kind` のクラスタで ArgoCD の画面が開く |
| 4 | **dev / prod**: Kustomize の base と overlay、ArgoCD の Application (ApplicationSet か 2 つの Application)。main にマージすると dev に入り、prod は昇格の PR で入る | 3 | kind | dev に入り、PR をマージすると prod に入る |
| 5 | **Kyverno**: 署名の検証 (自分のイメージは、このリポジトリの CI が署名したものだけ許可)、方針 (リソースの上限、`latest` の禁止など) | 4 | kind | 署名のないイメージ・方針違反が拒否される |
| 6 | **テンプレート化**: 1〜5 を `templates/service-go/` にまとめ、`scripts/new-service.sh` で 2 つ目のサービスを作れるようにする | 1 | 手元 + kind | 新しいサービスが、CI・dev/prod・署名の検証まで、そのまま通る |
| 7 | **SLO とダッシュボードの自動化**: テンプレートに SLO の定義を含め、`gen-slo-rules.sh` がサービスごとの定義を集める。ダッシュボードは同梱の Grafana で足りるか確かめる | 5 | 手元 (生成) + GKE (確認) | 新しいサービスに SLO のアラートが付く |
| 8 | **Renovate**: Helm の values、Terraform、ArgoCD のマニフェスト、`mise.toml`、SHA で固定した action を対象にする | (保守) | GitHub | Renovate の PR が来る |
| 9 | **External Secrets** + Secret Manager (GKE の Workload Identity)。使い道は Alertmanager の通知先 (Slack の Webhook の URL) | 5 の通知 | GKE | Secret Manager の値が Secret になり、アラートが Slack に届く |
| 10 | **通しの確認**: GKE で 1〜5 を通して動かし、スクリーンショットと時系列で記録する | 1〜5 | GKE | `docs/demo/phase3.md` |

- GKE を使うのはステップ 7 の確認・9・10 だけ (2〜3 回、1 回あたり約 1〜2 時間、約 21 円 / 時間)。
- ステップ 8 (Renovate) はクラスタが要らないので、途中のどこで入れてもよい。
- 【kind では External Secrets を Secret Manager につなげない】kind には Workload Identity がなく、鍵ファイルを作らない方針のため。kind ではステップ 9 を行わない。

## このフェーズで扱わないもの
- Backstage のソフトウェアテンプレート、OpenCost (フェーズ 4)
- 同梱の Grafana のアラートの不具合、Jaeger の `Incomplete` (「後でやる」のまま)
