################################################################################
# Keycloak Helm Values
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/keycloak/helm-values.yaml.tpl
# Chart: bitnami-legacy/keycloak
################################################################################

## Global configuration
global:
  storageClass: gp3

## Keycloak configuration
auth:
  adminUser: {{ keycloak_admin_user }}
  adminPassword: {{ keycloak_admin_password }}

## Production mode (recommended)
production: true

## Proxy configuration (TLS terminated at NLB)
proxy: edge

## Database configuration (External PostgreSQL - RDS)
postgresql:
  enabled: false  # Use external RDS database

externalDatabase:
  host: {{ keycloak_db_address }}
  port: 5432
  user: {{ keycloak_db_username }}
  password: {{ keycloak_db_password }}
  database: {{ keycloak_db_name }}
  existingSecret: ""  # We'll pass password directly
  existingSecretPasswordKey: ""

## Replication
replicaCount: {{ keycloak_replicas }}

## Service configuration
service:
  type: ClusterIP
  ports:
    http: 8080
    https: 8443

## Ingress configuration
ingress:
  enabled: true
  ingressClassName: nginx
  hostname: {{ keycloak_subdomain }}.{{ domain }}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    external-dns.alpha.kubernetes.io/hostname: {{ keycloak_subdomain }}.{{ domain }}
  tls: true
  selfSigned: false

## Resource limits
resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 512Mi

## Liveness and readiness probes
livenessProbe:
  enabled: true
  initialDelaySeconds: 120
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1

readinessProbe:
  enabled: true
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1

## Pod Disruption Budget
pdb:
  create: true
  minAvailable: 1

## Autoscaling (disabled for POC)
autoscaling:
  enabled: false

## Metrics
metrics:
  enabled: true
  serviceMonitor:
    enabled: false  # Enable when Prometheus is installed

## Security Context
containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true
  readOnlyRootFilesystem: false

podSecurityContext:
  enabled: true
  fsGroup: 1001

## Extra environment variables (for advanced configuration)
extraEnvVars:
  - name: KC_FEATURES
    value: "token-exchange,admin-fine-grained-authz"
  - name: KC_LOG_LEVEL
    value: "INFO"
  - name: KC_DB_POOL_INITIAL_SIZE
    value: "5"
  - name: KC_DB_POOL_MAX_SIZE
    value: "20"
  - name: KC_DB_POOL_MIN_SIZE
    value: "5"

## Init containers (for database wait)
initContainers: []

## Cache (Infinispan embedded)
cache:
  enabled: true
  stackName: kubernetes
