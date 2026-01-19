################################################################################
# ArgoCD Bootstrap - App of Apps
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/argocd/bootstrap-apps.yaml.tpl
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: {{ git_repo_url }}
    targetRevision: {{ git_branch }}
    path: platform/argocd/applications
  
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  
  syncPolicy:
    automated:
      prune: false  # Don't auto-prune for safety
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
