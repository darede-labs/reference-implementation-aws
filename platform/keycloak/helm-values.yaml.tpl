################################################################################
# Keycloak Helm Values
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/keycloak/helm-values.yaml.tpl
# Chart: bitnami-legacy/keycloak
################################################################################

## Global configuration
global:
  storageClass: gp3

## Image configuration
## IMPORTANT: Since August 28, 2024, Bitnami moved non-hardened images to bitnamilegacy registry
## Using latest tag as it's the most reliable for bitnamilegacy registry
image:
  registry: docker.io
  repository: bitnamilegacy/keycloak
  tag: latest
  pullPolicy: IfNotPresent

## Keycloak configuration
auth:
  adminUser: {{ keycloak_admin_user }}
  adminPassword: {{ keycloak_admin_password }}

## Production mode (recommended)
production: true

## Proxy configuration (TLS terminated at NLB)
proxy: edge

## Proxy headers (required for production mode when TLS is terminated externally)
proxyHeaders: xforwarded

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
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
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
## Initial startup takes ~4-5min for DB schema initialization
## Maximum timeout: 120s per probe (failureThreshold * timeoutSeconds)
livenessProbe:
  enabled: true
  initialDelaySeconds: 300  # 5min to allow for DB schema init
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
  successThreshold: 1

readinessProbe:
  enabled: true
  initialDelaySeconds: 240  # 4min to allow for startup
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 12  # 2min of failures allowed
  successThreshold: 1

## Startup probe (added for Kubernetes 1.18+)
## This prevents liveness probe from killing the container during initial startup
startupProbe:
  enabled: true
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 12  # 6min total (12 * 30s)

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
  # Keycloak frontend URL (required for proper OIDC redirect)
  - name: KEYCLOAK_HOSTNAME
    value: "https://{{ keycloak_subdomain }}.{{ domain }}"
  - name: KC_HOSTNAME_URL
    value: "https://{{ keycloak_subdomain }}.{{ domain }}"
  - name: KC_HOSTNAME_STRICT
    value: "false"
  # Features
  - name: KC_FEATURES
    value: "token-exchange,admin-fine-grained-authz"
  - name: KC_LOG_LEVEL
    value: "INFO"
  # Database pool configuration
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
