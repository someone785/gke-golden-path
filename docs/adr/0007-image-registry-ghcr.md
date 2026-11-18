# ADR 0007: 自分でビルドしたイメージは GHCR に置く

- 状態: 決定
- 日付: 2026-11-18

## 背景
- フェーズ 3 で、自分のサービス (`services/*/`) のイメージを CI でビルドし、kind と GKE の両方で動かす。
- フェーズ 3 は、GKE を使わず kind で進められるものを優先する (CLAUDE.md)。
- 【鍵ファイルは作らない】(CLAUDE.md)。kind には GKE の Workload Identity がないので、kind から GCP のサービスに認証する方法がない。
- 本体の Terraform には Artifact Registry がある (フェーズ 1)。本体と一緒に destroy されるので、使うたびにイメージが消える (ADR 0004 の追記)。

## 選択肢
1. **GHCR (GitHub Container Registry)**: CI は `GITHUB_TOKEN` で push できる (鍵なし)。パッケージを public にすれば、kind も GKE も認証なしで pull できる。
2. Artifact Registry: CI は WIF で push できる。kind から pull するには認証が要る (鍵ファイルを作らない方針と合わない)。kind では `kind load` でイメージを直接入れることになり、GKE と手順が分かれる。destroy のたびにイメージが消える問題もある。
3. Docker Hub: アカウントとトークン (秘密) が要る。匿名の pull に回数制限がある。

## 決定
1 にする。イメージは `ghcr.io/someone785/<サービス名>` に置く。

- CI (`.github/workflows/images.yml`) は `GITHUB_TOKEN` (`packages: write`) で push する。
- タグはコミットの SHA (`sha-<12 桁>`、PR は `pr-<番号>-<12 桁>`) にし、マニフェストからは digest で参照する。`latest` は使わない。
- `org.opencontainers.image.source` のラベルで、パッケージをこのリポジトリに結び付ける。

## 結果
- 【パッケージは、最初はリポジトリの公開範囲 (今は private) を引き継ぐ】kind と GKE から認証なしで pull するには、GitHub の画面でパッケージを public にする。リポジトリが private のままでも、パッケージだけを public にできる (GitHub のドキュメント、2026-11-18 に確認)。
- 【一度 public にしたパッケージは、private に戻せない】(同)。イメージに秘密を入れない (distroless に静的なバイナリ 1 つだけを入れる)。
- 本体の Terraform の Artifact Registry は使わなくなる。消すかどうかは別のコミットで決める (消すと、本体の plan が `13 to add` から `12 to add` に変わり、README の手順も直す)。
