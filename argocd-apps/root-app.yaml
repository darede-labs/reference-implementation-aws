################################################################################
# Root App-of-Apps
# This is the single entry point that triggers all platform applications
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: {{ .config.gitops.repo_url }}
    targetRevision: {{ .config.gitops.revision }}
    path: argocd-apps/platform
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
