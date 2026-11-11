# ADR 0004: Terraform を bootstrap・本体・platform の 3 つに分ける

- 状態: 決定
- 日付: 2026-11-08

## 背景
- Terraform の state は、GCS のバケットに置きたい。ただ、そのバケット自体も Terraform で作りたい (鶏と卵の問題)。
- GKE を作るのと同じ Terraform で、`helm` / `kubernetes` provider を使って ArgoCD を入れると、
  provider の設定が、まだ存在しないクラスタ (同じ apply で作るリソース) を参照することになる。
  これは、クラスタを作り直すときや destroy するときに壊れやすい、よく知られた問題である。
- 予算アラートは、クラスタを消している間も残しておきたい。

## 選択肢
1. **3 つに分ける**: bootstrap・本体・platform
2. bootstrap だけ分けて、本体と platform は 1 つにまとめる (provider の問題が残る)
3. state 用のバケットを `gcloud` で手で作り、Terraform は 1 つか 2 つにする
   (予算アラートがコードに残らない)

## 決定
3 つに分ける。

| 順 | ディレクトリ | 作るもの | state の置き場所 | 頻度 |
|---|---|---|---|---|
| 1 | `terraform/bootstrap/` | state 用のバケット、予算アラート、Workload Identity Federation (2026-11-08 に追加) | ローカル (gitignore する) | 最初の 1 回だけ。destroy しない |
| 2 | `terraform/` | VPC、GKE、Artifact Registry | GCS | 作り直すたび |
| 3 | `terraform/platform/` | ArgoCD、最初の Application | GCS | 作り直すたび (2 の後) |

## 結果
- 普段のサイクルでは、次の順に実行する。
  - 作るとき: `apply` を 2 → 3 の順に行う
  - 消すとき: `destroy` を 3 → 2 の順に行う
- 予算アラートは bootstrap にあるので、クラスタを消している間も有効なままになる。
- platform は、本体の出力 (クラスタのエンドポイントなど) を、`terraform_remote_state` か data source で参照する。
  どちらにするかは、実装のときに決める。
- 2 → 3 は、慣れたら 1 つのスクリプト (`make up` など) にまとめてもよい。
  その場合も、plan → 内容の表示 → 確認の入力待ち → apply の順にする。
- 【bootstrap の state はローカルにある】
  これを失うと、バケットと予算アラートを Terraform で管理できなくなる (import すれば戻せる)。
  消さないように注意する。

## 追記 (2026-11-08): Workload Identity Federation を本体から bootstrap に移す
### 背景
- 最初は WIF (GitHub Actions 用の pool と provider) を本体に置いていた。
- 本体を一度 apply → destroy したところで、**削除した pool と provider は 30 日間復元でき、その間は同じ ID で作り直せない**ことが分かった
  ([公式のドキュメント](https://docs.cloud.google.com/iam/docs/manage-workload-identity-pools-providers))。
  本体に置いたままだと、destroy した後 30 日以内の apply が失敗する。

### 選択肢
1. **WIF を bootstrap に移す** (destroy しない側に置く)
2. pool の ID に、apply ごとに変わる接尾辞を付ける (provider の名前が毎回変わり、GitHub Actions の設定も毎回直すことになる)

### 決定
1 にする。削除された pool と provider は `undelete` で復元し、bootstrap に import した。

### 結果
- クラスタを消している間も、CI の `terraform plan` が認証できる (CI の plan は、クラスタがない時間のほうが長い)。
- WIF 用の API (iam、iamcredentials、sts) と、GitHub のリポジトリに付ける IAM のロールも bootstrap に移した。
- bootstrap の state を失ったときに import するリソースは 12 個になった (その後 serviceUsageConsumer を足した) (`terraform/bootstrap/import.tf.example`)。
- 【Artifact Registry も、destroy するとイメージが消える】同じ名前ですぐ作り直せるかは未確認。使うのはフェーズ 3 なので、そのときに置き場所を決める。
