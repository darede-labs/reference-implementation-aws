################################################################################
# External DNS Helm Values
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/external-dns/helm-values.yaml.tpl
################################################################################

# AWS provider configuration
provider: aws

# Sources to watch for DNS records
sources:
  - ingress
  - service

# Route53 configuration
aws:
  region: "{{ region }}"
  zoneType: public

# Domain filters
domainFilters:
  - "{{ domain }}"

# TXT registry for ownership tracking
txtOwnerId: "{{ cluster_name }}"
txtPrefix: "external-dns-"
registry: txt

# Policy: upsert-only (safer, won't delete existing records)
policy: upsert-only

# Update interval
interval: 2m

# IRSA configuration
serviceAccount:
  create: true
  name: external-dns
  annotations:
    eks.amazonaws.com/role-arn: "{{ external_dns_role_arn }}"

# Resource limits
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

# Pod security
podSecurityContext:
  fsGroup: 65534
  runAsNonRoot: true
  runAsUser: 65534

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]

# Logging
logLevel: info
logFormat: json
