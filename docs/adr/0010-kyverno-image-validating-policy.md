# ADR 0010: Kyverno の ImageValidatingPolicy で署名と SBOM を確かめ、ValidatingPolicy で方針を守らせる

- 状態: 決定
- 日付: 2026-11-19

## 背景
- 「このプロジェクトで示したいこと」の 4: Kyverno が署名のないイメージや方針違反を拒否する。
- イメージは cosign v3 の既定 (Sigstore bundle 形式、OCI の referrer) で keyless 署名し、SBOM (SPDX) を attestation として付けている (ADR 0008)。
- Kyverno 1.18 のドキュメントには、cosign v3 の既定の署名を検証できるかが書かれていなかった (ADR 0008 の未確認)。

## 選択肢
### 署名の検証
1. **ImageValidatingPolicy (`policies.kyverno.io/v1`、CEL)**: Kyverno v1.19.2 のソース (`pkg/image/verifiers/ivpol/cosign/verifier.go`) に、cosign v3 の bundle の referrer を読む処理がある。
2. ClusterPolicy の `verifyImages` (従来の方式): cosign v3 の既定の形式を読めるかは確かめていない。
3. Kubernetes の ValidatingAdmissionPolicy: 署名の検証はできない。

### 方針 (レジストリ、digest、リソースの上限、root の禁止)
1. **ValidatingPolicy (`policies.kyverno.io/v1`、CEL)**: ImageValidatingPolicy と同じ書き方 (CEL) で、`kyverno test` で試せる。
2. ClusterPolicy の `validate.pattern`: 書き方が 2 種類に分かれる。

## 決定
- 署名は 1、方針は 1。Kyverno は v1.19.2 (chart 3.9.2) を ArgoCD で入れる (`gitops/apps/common/kyverno.yaml`)。v1.20.0 は公開から 1 週間だったので避けた。
- `verify-own-images` (ImageValidatingPolicy): `ghcr.io/someone785/*` のイメージは、main の `images.yml` の keyless 署名と、その署名者による SPDX の attestation がなければ拒否する。
- `workload-baseline` (ValidatingPolicy): ラベル `gke-golden-path/workload=true` の namespace では、次を守らない Pod を拒否する。ラベルは ApplicationSet (`managedNamespaceMetadata`) が付ける。
  - イメージは `ghcr.io/someone785/` のものだけ (署名を確かめられないイメージを持ち込ませない)
  - digest で参照する
  - メモリの上限を付ける
  - root で動かさない
- ポリシーは `kyverno test` (`gitops/platform/kyverno-policies/tests/`) で、手元と CI で試す。署名の検証は GHCR の本物のイメージで行う。kyverno の CLI は mise で入れ、クラスタの Kyverno と版をそろえる。

## 結果
- 2026-11-19 に `kyverno apply` / `kyverno test` で確かめたこと:
  - main の CI が署名した本物のイメージ (`938afbd8…`) は通る。
  - identity を PR の ref (`refs/pull/1/merge`) にすると、「署名がない」で拒否される。
  - attestation の種類を CycloneDX にすると、「SBOM の attestation がない」で拒否される。
  - 方針に違反する 4 種類の Pod (ほかのレジストリ、タグでの参照、メモリの上限なし、root) は拒否される。
- 【attestor の名前に `-` を使わない】CEL の式で `attestors.<名前>` と書くので、`github-main` は「`attestors.github` 引く `main`」と読まれ、ポリシーのコンパイルに失敗する。
- 【`failurePolicy: Fail`】Kyverno が止まっていると、`ghcr.io/someone785/*` の Pod を作れない。署名を確かめないまま通すよりよい。
- 【OTel Demo などの他者のイメージは対象外】`workload-baseline` は workload のラベルの namespace だけ、`verify-own-images` は自分のレジストリのイメージだけを見る (CLAUDE.md: 署名の対象は自分でビルドしたイメージだけ)。
- 未確認:
  - クラスタの Kyverno で、`kyverno test` と同じ結果になるか (kind で確かめる)。
  - すでにある namespace (`greeter-dev`、`greeter-prod`) に、ApplicationSet の `managedNamespaceMetadata` のラベルが後から付くか。
  - Deployment に対する拒否が、Deployment を作るときに出るか (Kyverno の autogen)、ReplicaSet が Pod を作るときに出るか。
