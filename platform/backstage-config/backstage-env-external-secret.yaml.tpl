apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: backstage-env-vars
  namespace: backstage
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: backstage-env-vars
    creationPolicy: Owner
  data:
    - secretKey: GITHUB_TOKEN
      remoteRef:
        key: backstage-env-vars
        property: GITHUB_TOKEN
    - secretKey: OIDC_CLIENT_SECRET
      remoteRef:
        key: backstage-env-vars
        property: OIDC_CLIENT_SECRET
    - secretKey: AUTH_SESSION_SECRET
      remoteRef:
        key: backstage-env-vars
        property: AUTH_SESSION_SECRET
    - secretKey: BACKEND_SECRET
      remoteRef:
        key: backstage-env-vars
        property: BACKEND_SECRET
    - secretKey: ARGOCD_ADMIN_PASSWORD
      remoteRef:
        key: backstage-env-vars
        property: ARGOCD_ADMIN_PASSWORD
