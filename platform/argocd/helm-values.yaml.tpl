################################################################################
# ArgoCD Helm Values
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/argocd/helm-values.yaml.tpl
################################################################################

global:
  domain: {{ argocd_subdomain }}.{{ domain }}

## ArgoCD Configuration
configs:
  params:
    server.insecure: true  # TLS terminated at NLB
    application.instanceLabelKey: argocd.argoproj.io/instance

  cm:
    # Helm chart repositories
    helm.repositories: |
      - name: argo
        type: helm
        url: https://argoproj.github.io/argo-helm
      - name: bitnami
        type: helm
        url: https://charts.bitnami.com/bitnami
      - name: codecentric
        type: helm
        url: https://codecentric.github.io/helm-charts
      - name: crossplane
        type: helm
        url: https://charts.crossplane.io/stable

    # Git repositories (for app-of-apps)
    repositories: |
      - url: {{ git_repo_url }}
        name: platform-infra

    # Resource customizations
    resource.customizations.health.argoproj.io_Application: |
      hs = {}
      hs.status = "Progressing"
      hs.message = ""
      if obj.status ~= nil then
        if obj.status.health ~= nil then
          hs.status = obj.status.health.status
          if obj.status.health.message ~= nil then
            hs.message = obj.status.health.message
          end
        end
      end
      return hs

  # RBAC Configuration
  rbac:
    policy.default: role:readonly
    policy.csv: |
      p, role:org-admin, applications, *, */*, allow
      p, role:org-admin, clusters, get, *, allow
      p, role:org-admin, repositories, get, *, allow
      p, role:org-admin, repositories, create, *, allow
      p, role:org-admin, repositories, update, *, allow
      p, role:org-admin, repositories, delete, *, allow
      g, platform-team, role:org-admin

## Controller
controller:
  replicas: 1

  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi

## Server
server:
  replicas: 2

  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

  # Ingress configuration
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
      external-dns.alpha.kubernetes.io/hostname: {{ argocd_subdomain }}.{{ domain }}
    hosts:
      - {{ argocd_subdomain }}.{{ domain }}
    tls:
      - secretName: argocd-tls
        hosts:
          - {{ argocd_subdomain }}.{{ domain }}

## Repo Server
repoServer:
  replicas: 2

  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

## ApplicationSet Controller
applicationSet:
  replicas: 2

  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

## Notifications Controller
notifications:
  enabled: true

  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

## Dex (SSO) - Disabled for now, will use Keycloak OIDC
dex:
  enabled: false

## Redis
redis:
  enabled: true

  resources:
    limits:
      cpu: 200m
      memory: 128Mi
    requests:
      cpu: 100m
      memory: 64Mi
