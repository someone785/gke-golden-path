# ADR 0008: イメージは Cosign で keyless 署名し、SBOM は Syft で作って attestation として付ける

- 状態: 決定
- 日付: 2026-11-18

## 背景
- 「このプロジェクトで示したいこと」の 2 と 4: CI が SBOM を作ってイメージに署名し、Kyverno が署名のないイメージを拒否する。
- 署名と SBOM の対象は、自分でビルドしたイメージだけ (CLAUDE.md)。
- 【鍵ファイルは作らない】(CLAUDE.md)。署名の鍵を作ると、その保管と漏れたときの無効化が必要になる。

## 選択肢
### 署名
1. **Cosign の keyless 署名**: GitHub Actions の OIDC トークンで、Sigstore の Fulcio から短命の証明書を受け取って署名し、Rekor (公開の透明性ログ) に記録する。証明書に「どのリポジトリの、どのワークフローの、どの ref が署名したか」が入る。
2. Cosign の鍵での署名: 鍵ファイル (または KMS) が要る。
3. Notary (Notation): 鍵と証明書の管理が要る。

### SBOM
1. **Syft で SPDX の JSON を作り、Cosign で attestation としてイメージに付ける**: イメージと SBOM が digest で結び付き、署名もされる。
2. SBOM を CI の成果物 (artifact) として保存するだけ: イメージとの結び付きが弱く、Kyverno から見えない。

## 決定
- 署名は 1 (keyless)、SBOM は 1 (Syft → `cosign attest --type spdxjson`)。
- CI (`.github/workflows/images.yml`) で、push → SBOM → 署名 → attestation → 自分で `cosign verify` の順に行う。署名は digest に対して行う。
- 【Cosign v3 の既定 (Sigstore bundle 形式、OCI の referrer) のまま使う】
  - Cosign 3.1.4 では、従来の形式で署名するオプション (`--new-bundle-format=false`) は非推奨で、「将来は新しい形式だけになる」とされている (cosign のソースの `cmd/cosign/cli/options/sign.go`、2026-11-18 に確認)。従来の形式に寄せても、いずれ使えなくなる。
- ツールは mise で入れ、チェックサムで固定する (ADR 0005)。cosign 3.1.4、syft 1.56.0。linux-x64 のチェックサムは、公式のチェックサムのファイルと一致した (2026-11-18)。

## 結果
- 鍵の保管と無効化が要らない。署名したワークフローが証明書に残るので、Kyverno で「このリポジトリの main の `images.yml` が署名したものだけ」を許可できる。
- 【`images.yml` の名前と置き場所を変えると、Kyverno の検証が通らなくなる】証明書の identity が変わるため。
- 【PR のイメージも署名されるが、identity の ref が `refs/pull/<番号>/merge` になる】Kyverno で main だけを許可すれば、PR のイメージはクラスタで動かせない。
- 署名の記録は公開の Rekor に残る (リポジトリ名とワークフロー名が公開される)。リポジトリはクラスタを動かす間 public にしているので、許容する。
- 未確認:
  - Kyverno (1.18 のドキュメント) で、Cosign v3 の既定の署名と SPDX の attestation を keyless で検証する書き方。ドキュメントには Sigstore bundle 用の `SigstoreBundle` の型があるが、例は SLSA の来歴だけだった。フェーズ 3 のステップ 5 で確かめる。通らなければ、署名のオプションか検証の方法を見直す。
  - (2026-11-18 に確認) GHCR に、署名と SBOM の attestation が OCI の referrer として保存された (`cosign tree`)。
