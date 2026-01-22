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
        # Use external RDS database (no PVC needed)
        postgresql:
          enabled: false
        
        externalDatabase:
          host: {{ keycloak_db_address }}
          port: 5432
          user: {{ keycloak_db_username }}
          password: {{ keycloak_db_password }}
          database: {{ keycloak_db_name }}
        
        # Keycloak admin credentials
        keycloak:
          username: {{ keycloak_admin_user }}
          password: {{ keycloak_admin_password }}
        
        # Production settings
        proxy: edge
        proxyHeaders: xforwarded
        
        # Service and ingress
        service:
          type: ClusterIP
        
        ingress:
          enabled: true
          ingressClassName: nginx
          hostname: {{ keycloak_hostname }}
          annotations:
            nginx.ingress.kubernetes.io/ssl-redirect: "true"
            nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
            external-dns.alpha.kubernetes.io/hostname: {{ keycloak_hostname }}
          tls: true
        
        # Resources for cost optimization (Graviton ARM64)
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
        
        # Node affinity for Karpenter nodes
        affinity:
          nodeAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                preference:
                  matchExpressions:
                    - key: karpenter.sh/capacity-type
                      operator: Exists
              - weight: 50
                preference:
                  matchExpressions:
                    - key: role
                      operator: NotIn
                      values:
                        - karpenter-bootstrap
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
