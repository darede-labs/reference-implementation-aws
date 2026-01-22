################################################################################
# ArgoCD Application: Keycloak
# Wave 1 - Identity Provider (deployed after ingress)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - chart: keycloak
      repoURL: https://codecentric.github.io/helm-charts
      targetRevision: 18.10.0
      helm:
        valueFiles:
          - $values/platform/keycloak/helm-values.yaml
    - repoURL: {{ git_repo_url }}
      targetRevision: {{ git_branch }}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
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
