################################################################################
# ArgoCD Application: Loki
# Wave 3 - Observability (deployed after platform is ready)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  ignoreDifferences:
    - group: apps
      kind: DaemonSet
      name: loki-canary
      jsonPointers:
        - /spec
  source:
    chart: loki
    repoURL: https://grafana.github.io/helm-charts
    targetRevision: 5.41.4
    helm:
      values: |
        loki:
          auth_enabled: false
          commonConfig:
            replication_factor: 1
            path_prefix: /var/loki
          storage_config:
            filesystem:
              directory: /var/loki/chunks
          schema_config:
            configs:
              - from: 2024-01-01
                store: tsdb
                object_store: filesystem
                schema: v13
                index:
                  prefix: loki_index_
                  period: 24h
        singleBinary:
          replicas: 1
          persistence:
            enabled: false
          extraVolumes:
            - name: loki-tmp-storage
              emptyDir: {}
          extraVolumeMounts:
            - name: loki-tmp-storage
              mountPath: /var/loki
          # Evita agendamento no bootstrap node
          nodeSelector:
            workload-type: general
          tolerations: []
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 512Mi
        read:
          replicas: 0
        write:
          replicas: 0
        backend:
          replicas: 0
        serviceAccount:
          create: true
          name: loki
        monitoring:
          selfMonitoring:
            enabled: false
            grafanaAgent:
              installOperator: false
        test:
          enabled: false
        # Loki Canary disabled for MVP (can be enabled later if needed)
        # It's a verification tool, not critical for operations
        lokiCanary:
          enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: observability
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
