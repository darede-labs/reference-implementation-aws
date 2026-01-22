################################################################################
# ArgoCD Application: Keycloak Realm Configuration
# Wave 2 - Realm import (deployed after Keycloak)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak-realm
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: {{ gitops_repo_url }}
    targetRevision: {{ gitops_branch }}
    path: platform/keycloak/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - Replace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
