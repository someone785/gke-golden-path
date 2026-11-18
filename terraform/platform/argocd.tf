# ---------------------------------------------------------------
# ArgoCD 本体 (ADR 0003: ArgoCD 自身は Terraform が管理する)
# ---------------------------------------------------------------
# 版の更新は、この version を上げる PR で行う。
# 【公開から 2 週間ほど経った版を選ぶ】出たばかりの版は、問題が見つかって取り下げられることがあるため (ADR 0005 と同じ考え方)
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.11.1" # ArgoCD v3.5.6、2026-10-23 公開

  # 初回はイメージの取得に時間がかかるので、既定の 300 秒より長く待つ
  timeout = 600

  # kind (scripts/kind-up.sh) と同じ values を使う
  values = [file("${path.module}/../../gitops/platform/argocd/values.yaml")]
}

# ---------------------------------------------------------------
# app-of-apps のルート
# ---------------------------------------------------------------
# gitops/apps/ の下 (common/ と gke/) にある Application をすべて ArgoCD に読ませる。これより先は、すべて Git から入る。
# kind のルート (kind/root-app.yaml) は common/ だけを読む (OTel Demo は kind ではメモリが足りないため gke/ に置いている)。
# 【finalizers を付けない】付けると、destroy で ArgoCD を先に消したときに Application の削除が止まる。
# 配下のリソースは、本体の destroy でクラスタごと消える。
resource "helm_release" "root_app" {
  name      = "root-app"
  namespace = "argocd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.7" # 2026-10-16 公開

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "gitops/apps"
          # サブディレクトリ (common/、gke/) も読む
          directory = {
            recurse = true
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  # Application の CRD は argo-cd の chart が入れる
  depends_on = [helm_release.argocd]
}
