# Backstage ServiceAccount Token Secret
# Source: config.yaml
# DO NOT EDIT MANUALLY - regenerate with: scripts/render-templates.sh
#
# Note: ServiceAccount is managed by Helm chart
# This creates only the token secret for Kubernetes API access
---
apiVersion: v1
kind: Secret
metadata:
  name: backstage-sa-token
  namespace: backstage
  annotations:
    kubernetes.io/service-account.name: backstage
  labels:
    app.kubernetes.io/name: backstage
    app.kubernetes.io/component: serviceaccount-token
type: kubernetes.io/service-account-token
