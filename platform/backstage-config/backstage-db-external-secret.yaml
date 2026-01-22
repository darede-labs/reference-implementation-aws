apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: backstage-db-credentials
  namespace: backstage
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: backstage-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_HOST
      remoteRef:
        key: rds_secret
        property: host
    - secretKey: POSTGRES_PORT
      remoteRef:
        key: rds_secret
        property: port
    - secretKey: POSTGRES_USER
      remoteRef:
        key: rds_secret
        property: username
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: rds_secret
        property: password
