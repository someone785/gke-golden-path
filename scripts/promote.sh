#!/usr/bin/env bash
# dev で動いているイメージを prod に昇格する PR を作る (ADR 0009)。
# dev の overlay の digest を prod の overlay にコピーし、ブランチを切ってコミットし、PR を作る。
# PR をマージすると、ArgoCD が prod に入れる。
#
# 使い方: scripts/promote.sh <サービス名>     例: scripts/promote.sh greeter
#
# 【これはユーザーが自分の端末で実行する】git commit / push と PR の作成を行う (CLAUDE.md)。
# 冪等: prod がすでに dev と同じ digest なら、何もしない。
set -euo pipefail

cd "$(dirname "$0")/.."

svc="${1:?サービス名を指定する (例: scripts/promote.sh greeter)}"
registry="ghcr.io/someone785"
image="${registry}/${svc}"
dev_dir="gitops/workloads/${svc}/overlays/dev"
prod_dir="gitops/workloads/${svc}/overlays/prod"
# Kyverno (フェーズ 3 のステップ 5) と同じ条件: main の images.yml が keyless で署名したもの
identity="https://github.com/someone785/gke-golden-path/.github/workflows/images.yml@refs/heads/main"

for cmd in git gh kustomize cosign; do
  command -v "${cmd}" >/dev/null || { echo "${cmd} がない (mise install を実行する)" >&2; exit 1; }
done
[[ -f "${dev_dir}/kustomization.yaml" && -f "${prod_dir}/kustomization.yaml" ]] \
  || { echo "${dev_dir} か ${prod_dir} がない" >&2; exit 1; }

# 【main の最新から始める】古い main から昇格すると、CI が書き換えた dev の digest を取りこぼす
[[ -z "$(git status --porcelain)" ]] || { echo "作業ツリーに未コミットの変更がある。片付けてから実行する" >&2; exit 1; }
git switch main
git pull --ff-only origin main

digest_of() {
  kustomize build "$1" | grep -oE "image: ${image}@sha256:[0-9a-f]{64}" | head -1 | sed 's/.*@//'
}
dev_digest=$(digest_of "${dev_dir}")
prod_digest=$(digest_of "${prod_dir}")
[[ -n "${dev_digest}" ]] || { echo "dev の digest を読めない" >&2; exit 1; }

if [[ "${dev_digest}" == "${prod_digest}" ]]; then
  echo "prod はすでに dev と同じ (${dev_digest})。昇格するものはない"
  exit 0
fi

# 【昇格の前に署名を確かめる】main の CI が署名したイメージでなければ、PR を作らない
echo "== 署名を確かめる: ${image}@${dev_digest}"
cosign verify --certificate-identity "${identity}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "${image}@${dev_digest}" >/dev/null

branch="promote/${svc}-${dev_digest:7:12}"
git switch -c "${branch}"
(cd "${prod_dir}" && kustomize edit set image "${image}@${dev_digest}")
git add "${prod_dir}/kustomization.yaml"
git commit -m "deploy(prod): promote ${svc} to ${dev_digest:0:19}

dev: ${dev_digest}
prod (before): ${prod_digest:-none}"
git push -u origin "${branch}"

gh pr create --base main --head "${branch}" \
  --title "deploy(prod): promote ${svc} to ${dev_digest:0:19}" \
  --body "dev で動いている ${svc} を prod に昇格する (scripts/promote.sh で作成)。

| | digest |
|---|---|
| dev (昇格するもの) | \`${dev_digest}\` |
| prod (今) | \`${prod_digest:-なし}\` |

- 署名: \`cosign verify\` で、main の \`images.yml\` が keyless で署名したことを確かめた
- マージすると、ArgoCD が \`${svc}-prod\` に入れる"

git switch main
