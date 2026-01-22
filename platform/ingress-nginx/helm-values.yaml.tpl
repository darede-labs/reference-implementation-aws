################################################################################
# Ingress NGINX Helm Values
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/ingress-nginx/helm-values.yaml.tpl
################################################################################

controller:
  service:
    type: LoadBalancer
    annotations:
      # NLB configuration
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"

      # TLS termination at NLB using ACM certificate
      service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "{{ acm_certificate_arn }}"
      service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"

      # Cross-zone load balancing
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"

      # Tags for cost tracking
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "{{ cloud_economics_tag }},ManagedBy=helm,Component=ingress-nginx"

  # Resource limits for cost optimization
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

  # Replica configuration
  replicaCount: 2

  # Metrics
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false  # Enable when Prometheus is installed

  # Pod disruption budget for high availability
  podDisruptionBudget:
    enabled: true
    minAvailable: 1

  # Affinity to spread pods across nodes
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: ingress-nginx
                app.kubernetes.io/component: controller
            topologyKey: kubernetes.io/hostname
