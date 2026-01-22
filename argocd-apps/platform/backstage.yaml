################################################################################
# ArgoCD Application: Backstage
# Wave 2 - Developer Experience (deployed after Keycloak)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backstage
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: backstage
    repoURL: https://backstage.github.io/charts
    targetRevision: 1.10.0
    helm:
      valuesObject: {}
      # Values from platform/backstage/helm-values.yaml (managed separately)
  destination:
    server: https://kubernetes.default.svc
    namespace: backstage
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
