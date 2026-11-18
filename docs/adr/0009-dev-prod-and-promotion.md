# ADR 0009: dev / prod は 1 つのクラスタの namespace で分け、dev は CI が自動で、prod は PR で入れる

- 状態: 決定
- 日付: 2026-11-19

## 背景
- 「このプロジェクトで示したいこと」の 3: マージすると、ArgoCD が dev にデプロイし、確認後に prod へ昇格する。
- 費用を抑えるため、GKE は使うときだけ 1 ノードで動かす。フェーズ 3 は kind を優先する (CLAUDE.md)。
- 自分のマニフェストと環境ごとの差分は Kustomize の overlay で管理する (CLAUDE.md)。
- イメージは digest で参照する (ADR 0007)。

## 選択肢
### 環境の分け方
1. **1 つのクラスタに namespace を 2 つ (`<サービス>-dev`、`<サービス>-prod`)**: 費用が増えない。kind でも同じ形で動く。
2. クラスタを 2 つ: 本番に近いが、費用が 2 倍になる。kind ではメモリが足りない。

### dev へのデプロイ
1. **CI (images.yml の deploy-dev) が overlays/dev の digest を書き換えて main にコミットする**: 部品を足さない。何が入っているかが Git に残る。
2. ArgoCD Image Updater: 部品が 1 つ増える。digest の更新は Git への書き戻しで行うので、結局 1 と同じことをする。
3. dev はタグ (`main` など) で追いかける: タグは付け替わる。digest で参照する方針 (ADR 0007) と合わない。

### prod への昇格
1. **手元のスクリプト (`scripts/promote.sh`) で、dev の digest を prod にコピーする PR を作る**: 人が「確認後に」判断する場所が PR のマージになる。ユーザーの権限で作る PR なので、CI の検査も動く。
2. CI (GITHUB_TOKEN) で PR を作る: 【GITHUB_TOKEN で作った PR では、ほかのワークフローが動かない】(GitHub の仕様)。検査を通らない PR を prod に入れることになる。リポジトリの設定で、Actions に PR の作成を許可する必要もある。
3. dev への反映と同時に prod にも入れる: 確認の機会がない。

## 決定
- 環境の分け方は 1、dev へのデプロイは 1、prod への昇格は 1。
- マニフェストは `gitops/workloads/<サービス>/base/` と `overlays/dev`、`overlays/prod`。
- ArgoCD は ApplicationSet (`gitops/apps/common/workloads.yaml`) で、`gitops/workloads/*/overlays/*` のディレクトリから Application `<サービス>-<環境>` を作る。テンプレートから作ったサービス (フェーズ 3 のステップ 6) も、ディレクトリを置くだけで入る。
- `scripts/promote.sh` は、PR を作る前に `cosign verify` で「main の images.yml が署名したイメージ」かを確かめる。

## 結果
- 流れ: サービスのコードの PR をマージ → images.yml がイメージを作って署名 → deploy-dev が overlays/dev を書き換えてコミット → ArgoCD が dev に入れる → 確認 → `scripts/promote.sh` → PR をマージ → ArgoCD が prod に入れる。
- 【deploy-dev のコミット (GITHUB_TOKEN) では、ワークフローが動かない】繰り返しにならない代わりに、そのコミットは ci の検査を通らない (変えるのは digest だけ)。
- 【images.yml は、サービスのコードかワークフロー自体が変わったときだけ動く】マニフェストだけの変更 (昇格の PR など) でイメージを作り直すと、中身が同じでも digest が変わり、dev が無駄に入れ替わるため。
- 【1 つのクラスタなので、dev と prod は完全には分かれていない】ノードやクラスタ全体の障害は両方に及ぶ。学習用として許容する。
- 未確認:
  - ApplicationSet の git の generator で、複数の階層のワイルドカード (`gitops/workloads/*/overlays/*`) が動くか (ドキュメントに例がない)。kind で確かめる。
  - deploy-dev のジョブが、`contents: write` で main に push できるか (リポジトリの Actions の設定による)。`packages: write` は同じ設定で使えた。
