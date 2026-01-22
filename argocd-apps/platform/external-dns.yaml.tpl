################################################################################
# ArgoCD Application: External DNS
# Wave 0 - Infrastructure layer (must be deployed first)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://kubernetes-sigs.github.io/external-dns
    chart: external-dns
    targetRevision: 1.16.1
    helm:
      values: |
        provider: aws
        sources:
          - ingress
          - service
        aws:
          region: "{{ region }}"
          zoneType: public
        domainFilters:
          - "{{ domain }}"
        txtOwnerId: "{{ cluster_name }}"
        txtPrefix: "external-dns-"
        registry: txt
        policy: upsert-only
        interval: 2m
        serviceAccount:
          create: true
          name: external-dns
          annotations:
            eks.amazonaws.com/role-arn: "{{ external_dns_role_arn }}"
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
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
        logLevel: info
        logFormat: json
  destination:
    server: https://kubernetes.default.svc
    namespace: external-dns
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
