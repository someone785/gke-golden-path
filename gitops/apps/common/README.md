# gitops/apps/common

kind と GKE の両方に入れる ArgoCD の Application を置く (自分のサービス、Kyverno など)。

- GKE のルート (`terraform/platform/argocd.tf`) は `gitops/apps/` の下をすべて読む (`common/` と `gke/`)。
- kind のルート (`kind/root-app.yaml`) は、ここ (`common/`) だけを読む。
- GKE だけに入れるもの (OTel Demo。kind ではメモリが足りない) は `gitops/apps/gke/` に置く。

ArgoCD は、このディレクトリの `.yaml` / `.yml` / `.json` だけをマニフェストとして読む (この README は読まない)。
