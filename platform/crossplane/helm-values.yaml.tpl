################################################################################
# Crossplane Helm Values - SIMPLIFIED
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/crossplane/helm-values.yaml.tpl
################################################################################

# IRSA Configuration - CRITICAL for AWS access
serviceAccount:
  create: true
  name: crossplane
  annotations:
    eks.amazonaws.com/role-arn: "{{ crossplane_role_arn }}"

# Resource limits - reasonable defaults
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi

# Security - best practices
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65532
  fsGroup: 65532

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]

# Metrics
metrics:
  enabled: true

# RBAC
rbac:
  manage: true

# Args
args:
  - --debug
