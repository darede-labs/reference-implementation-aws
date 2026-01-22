################################################################################
# ControllerConfig for AWS Providers - IRSA Configuration
# This ensures all AWS providers use the correct service account with IRSA
################################################################################
apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: aws-config
spec:
  serviceAccountName: crossplane
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 2000
    fsGroup: 2000
  args:
    - --debug
    - --poll=1m
    - --max-reconcile-rate=100
