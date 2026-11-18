#!/usr/bin/env bash
# 手元に kind のクラスタを作り、ArgoCD とルートの Application (gitops/apps/common/) を入れる (フェーズ 3)。
# 冪等: 何度実行しても同じ状態になる (クラスタがあれば作らず、ArgoCD は helm upgrade --install で揃える)。
#
# 使い方:
#   scripts/kind-up.sh      # 作る / 揃える
#   scripts/kind-down.sh    # 消す
#
# 【ArgoCD の chart の版と values は GKE と同じにする】terraform/platform/argocd.tf と gitops/platform/argocd/values.yaml
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_NAME="gke-golden-path"
ARGO_HELM_REPO="https://argoproj.github.io/argo-helm"
ARGOCD_CHART_VERSION="10.11.1" # ArgoCD v3.5.6 (terraform/platform/argocd.tf と同じ)
ARGOCD_APPS_CHART_VERSION="2.0.7"

for cmd in docker kind kubectl helm; do
  command -v "${cmd}" >/dev/null || { echo "${cmd} がない (mise install を実行する)" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Docker が動いていない" >&2; exit 1; }

# 1. クラスタ
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "== クラスタ ${CLUSTER_NAME} はある (作らない)"
else
  echo "== クラスタ ${CLUSTER_NAME} を作る"
  kind create cluster --config kind/cluster.yaml --wait 120s
fi
# 【kubectl と helm の接続先を kind に固定する】GKE の接続先 (kubeconfig の current-context) のまま実行しないように
CONTEXT="kind-${CLUSTER_NAME}"
kubectl config use-context "${CONTEXT}" >/dev/null

# 2. ArgoCD
echo "== ArgoCD (chart ${ARGOCD_CHART_VERSION})"
helm upgrade --install argocd argo-cd \
  --kube-context "${CONTEXT}" \
  --repo "${ARGO_HELM_REPO}" --version "${ARGOCD_CHART_VERSION}" \
  --namespace argocd --create-namespace \
  --values gitops/platform/argocd/values.yaml \
  --wait --timeout 10m

# 3. ルートの Application
echo "== ルートの Application (gitops/apps/common/)"
helm upgrade --install root-app argocd-apps \
  --kube-context "${CONTEXT}" \
  --repo "${ARGO_HELM_REPO}" --version "${ARGOCD_APPS_CHART_VERSION}" \
  --namespace argocd \
  --values kind/root-app.yaml \
  --wait --timeout 5m

cat <<EOF

== できた
ArgoCD の画面:
  kubectl --context ${CONTEXT} -n argocd port-forward svc/argocd-server 8081:80
  → http://localhost:8081 (【https ではなく http】、ユーザーは admin)
パスワード (【表示するだけ。保存・共有しない】):
  kubectl --context ${CONTEXT} -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
Application の状態:
  kubectl --context ${CONTEXT} get applications -n argocd
EOF
