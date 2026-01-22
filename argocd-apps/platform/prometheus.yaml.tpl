################################################################################
# ArgoCD Application: Prometheus Stack
# Wave 3 - Observability (deployed after platform is ready)
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: kube-prometheus-stack
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 55.5.0
    helm:
      values: |
        prometheus:
          enabled: true
          prometheusSpec:
            retention: 15d
            resources:
              requests:
                cpu: 200m
                memory: 512Mi
              limits:
                memory: 2Gi
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: gp2
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 10Gi
        grafana:
          enabled: true
          adminPassword: changeme
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              external-dns.alpha.kubernetes.io/hostname: grafana.{{ domain }}
            hosts:
              - grafana.{{ domain }}
            tls: []
          additionalDataSources:
            - name: Loki
              type: loki
              url: http://loki-gateway.observability.svc.cluster.local:80
              access: proxy
              isDefault: false
        alertmanager:
          enabled: false
        nodeExporter:
          enabled: false
        kubeStateMetrics:
          enabled: true
        prometheusOperator:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: observability
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
