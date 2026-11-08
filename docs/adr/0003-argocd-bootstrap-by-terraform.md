# ADR 0003: ArgoCD は Terraform で入れて、ArgoCD 自身は Terraform が管理し続ける

- 状態: 決定
- 日付: 2026-11-08

## 背景
クラスタの中のものは GitOps (ArgoCD) で管理する方針だが、ArgoCD 自身は、最初に誰かが入れなければならない (ブートストラップの問題)。
フェーズ 1 の完了条件は、「`terraform apply` から OTel Demo の画面が開くまでを、手順どおり再現できる」こと。

## 選択肢

| # | 最初に入れる | その後の ArgoCD 自身の管理 | 評価 |
|---|---|---|---|
| A | Terraform (`helm_release`) | Terraform | 担当がはっきり分かれる。`terraform apply` だけで全部が立ち上がる |
| B | Terraform か手動の `helm install` | ArgoCD 自身 (自分の chart を指す Application) | すべてが Git に揃う。ただし、Terraform で入れると、Terraform と ArgoCD が同じものを管理し合って衝突する |
| C | 手動 (`helm install` や `kubectl apply`) | ArgoCD 自身 | 単純だが、`terraform apply` の外に手作業が残る |
| D | `argocd-autopilot` (CLI) | ArgoCD 自身 | リポジトリの構成に型がある。今の開発状況は**未確認** |
| E | ArgoCD 以外 (GKE の Config Sync など) | — | 技術の選択 (CLAUDE.md) と変わるので対象外 |

## 決定
A にする。Terraform で ArgoCD と最初の Application (app-of-apps のルート) を入れる。それ以外は、すべて ArgoCD が Git から入れる。

## 理由
- フェーズ 1 の完了条件 (`terraform apply` からの再現) に、いちばん素直に合う。
- 担当の境界がはっきりする。ArgoCD 自身は Terraform、ほかはすべて ArgoCD が管理する。
- B を Terraform で入れる場合の衝突を避けられる。
  ArgoCD は Helm を使わず、マニフェストに展開して適用する。そのため、ArgoCD が自分の版を上げても、
  次の `terraform apply` で、Terraform が元の版に戻すことがありうる。

## 結果
- ArgoCD 自身だけは、GitOps の外 (Terraform の管理) に置く。これは意図した例外とする。
- ArgoCD の版の更新は、Terraform の `helm_release` の版を上げる PR で行う。
  Renovate がこの更新に対応しているかは、Renovate を入れるときに確認する (**未確認**)。
- GKE と同じ Terraform で ArgoCD を入れると、provider の問題が起きる。そのため、Terraform を分ける (ADR 0004)。
