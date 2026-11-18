#!/usr/bin/env bash
# 手元の kind のクラスタを消す。冪等: クラスタがなければ何もしない。
set -euo pipefail

CLUSTER_NAME="gke-golden-path"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "クラスタ ${CLUSTER_NAME} はない (何もしない)"
fi
