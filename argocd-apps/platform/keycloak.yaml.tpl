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

        # External database configuration via Kubernetes Secret (populated by keycloak-db-secret job)
        extraEnv: |
          - name: DB_VENDOR
            value: postgres
          - name: DB_ADDR
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: host
          - name: DB_PORT
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: port
          - name: DB_DATABASE
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: database
          - name: DB_USER
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: username
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: password
          - name: KEYCLOAK_USER
            value: {{ keycloak_admin_user }}
          - name: KEYCLOAK_PASSWORD
            valueFrom:
              secretKeyRef:
                name: keycloak-admin
                key: password
          - name: KEYCLOAK_FRONTEND_URL
            value: https://{{ keycloak_subdomain }}.{{ domain }}/auth
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
