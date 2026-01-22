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
  source:
    chart: keycloak
    repoURL: https://codecentric.github.io/helm-charts
    targetRevision: 18.10.0
    helm:
      values: |
        # Disable internal PostgreSQL (use external RDS)
        postgresql:
          enabled: false
        
        # External database configuration via environment variables
        extraEnv: |
          - name: DB_VENDOR
            value: postgres
          - name: DB_ADDR
            value: {{ keycloak_db_address }}
          - name: DB_PORT
            value: "5432"
          - name: DB_DATABASE
            value: {{ keycloak_db_name }}
          - name: DB_USER
            value: {{ keycloak_db_username }}
          - name: DB_PASSWORD
            value: {{ keycloak_db_password }}
          - name: KEYCLOAK_USER
            value: {{ keycloak_admin_user }}
          - name: KEYCLOAK_PASSWORD
            value: {{ keycloak_admin_password }}
          - name: PROXY_ADDRESS_FORWARDING
            value: "true"
        
        # Resources for cost optimization (Graviton ARM64)
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
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
