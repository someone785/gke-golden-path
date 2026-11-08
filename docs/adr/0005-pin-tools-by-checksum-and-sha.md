# ADR 0005: ツールは、タグではなくチェックサムとコミット SHA で固定する

- 状態: 決定
- 日付: 2026-11-08

## 背景
- Git のタグやリリースは、後から別のコミット・別のバイナリに付け替えられる。
  実例として、2026 年 3 月に trivy でサプライチェーン攻撃があった (CVE-2026-33634)。
  - 盗まれた認証情報で、悪意のある v0.69.4 が公開された。
  - `trivy-action` の 77 個のタグのうち 76 個と、`setup-trivy` のタグ 7 個すべてが、悪意のあるコミットに付け替えられた。
  - v0.69.5 と v0.69.6 の Docker Hub のイメージも、悪意のあるものだったと報告されている。
  - v0.69.3 は、変更できないリリース (immutable release) で保護されていて、影響を受けなかったと報告されている。
    GitHub API で確認したところ、v0.69.3 の公開日は 2026-03-03 (攻撃より前) で、`immutable: true` だった (2026-11-08)。
  - 参考: [GitLab Advisory](https://advisories.gitlab.com/golang/github.com/aquasecurity/trivy/CVE-2026-33634/)、
    [EGI](https://advisories.egi.eu/Advisory-EGI-SVG-2026-09)、
    [Kudelski Security](https://kudelskisecurity.com/research/trivy-tag-compromise-supply-chain-attack)
- 検査のツール (trivy、gitleaks など) が差し替えられると、検査そのものが信用できなくなる。

## 選択肢
1. 版の番号 (タグ) で固定する: 付け替えに弱い
2. **バイナリはチェックサムで、取得元のリポジトリはコミット SHA で固定する**
3. ツールをソースからビルドして、コミット SHA で固定する: Go などのツールチェーンが要り、遅い。
   そもそも mise の aqua 方式 (ビルド済みのバイナリを取得する) では、SHA を指定できない

## 決定
2 にする。

| 対象 | 方法 |
|---|---|
| 手元・CI のツール (terraform、tflint、trivy、gitleaks、pre-commit) | `mise.lock` に、ダウンロード先の URL とチェックサムを記録する。CI では `mise install --locked` で、lock にないツールをエラーにする |
| pre-commit のフックの取得元 | `pre-commit autoupdate --freeze` で、`rev:` をコミット SHA にする |
| GitHub Actions の action (CI を作るとき) | `uses: owner/action@<40 桁の SHA> # vX.Y.Z` と書く。trivy は trivy-action を使わず、mise で `mise.lock` から入れる |

## 理由
- チェックサムでの固定は、中身が 1 バイトでも違えば、インストールが失敗する。タグがどう付け替えられても防げる。
- mise の aqua 方式は、配布元が用意していれば、Cosign 署名・SLSA の来歴・GitHub のアテステーションを既定で検証する。
  ただし、各ツールがどれを用意しているかは**未確認**。

## 結果
- 【lock した時点のバイナリが固定される】悪意のあるものが出回っている最中に lock すると、それを固定してしまう。
  更新 (`mise lock --bump`) の前に、配布元の告知を確認する。
- ツールを足したら `mise lock` を実行する。CI は `--locked` なので、lock にないツールは CI で失敗する。
- 【`mise.toml` に `[settings] locked = true` を書くと、グローバルの設定のツール (手元の node など) まで lock を要求される】
  そのため、厳格な検査は CI の `--locked` だけで行う。手元の `mise install` で lock の版とチェックサムが使われるかは、
  ドキュメントの記述 (lock にある版が優先される) に基づく理解で、挙動は**未確認**。
- 更新の手間が増える。フェーズ 3 で Renovate を入れるとき、`mise.lock` と SHA の更新に対応しているかを確認する (**未確認**)。
