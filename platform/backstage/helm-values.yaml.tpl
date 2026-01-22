# Backstage Helm Values - Dynamically Generated
# Source: config.yaml + Terraform outputs
# DO NOT EDIT MANUALLY - regenerate with: scripts/render-templates.sh

ingress:
  enabled: true
  className: "nginx"
  annotations:
    external-dns.alpha.kubernetes.io/hostname: {{ backstage_hostname }}
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  host: {{ backstage_hostname }}
  path: "/"
  tls:
    enabled: true

backstage:
  replicas: 2
  image:
    registry: ghcr.io
    repository: backstage/backstage
    tag: latest
    pullPolicy: IfNotPresent

  command: ["node", "packages/backend"]

  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

  extraEnvVars:
    # TLS Configuration (accept self-signed certs from Keycloak)
    - name: NODE_TLS_REJECT_UNAUTHORIZED
      value: "0"

    # Backstage URLs
    - name: BACKSTAGE_FRONTEND_URL
      value: "https://{{ backstage_hostname }}"

    # GitHub Integration
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: GITHUB_TOKEN
    - name: GITHUB_ORG
      value: "{{ github_org }}"
    - name: INFRA_REPO
      value: "{{ infrastructure_repo }}"

    # Keycloak OIDC
    - name: OIDC_ISSUER_URL
      value: "https://{{ keycloak_hostname }}/auth/realms/platform"
    - name: OIDC_CLIENT_ID
      value: "backstage"
    - name: OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: OIDC_CLIENT_SECRET

    # PostgreSQL (configured via appConfig.backend.database)
    - name: POSTGRES_HOST
      valueFrom:
        secretKeyRef:
          name: backstage-db-credentials
          key: POSTGRES_HOST
    - name: POSTGRES_PORT
      valueFrom:
        secretKeyRef:
          name: backstage-db-credentials
          key: POSTGRES_PORT
    - name: POSTGRES_USER
      valueFrom:
        secretKeyRef:
          name: backstage-db-credentials
          key: POSTGRES_USER
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: backstage-db-credentials
          key: POSTGRES_PASSWORD

    # Auth Secrets
    - name: AUTH_SESSION_SECRET
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: AUTH_SESSION_SECRET
    - name: BACKEND_SECRET
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: BACKEND_SECRET

    # ArgoCD Integration
    - name: ARGO_CD_URL
      value: "https://{{ argocd_hostname }}"
    - name: ARGOCD_ADMIN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: ARGOCD_ADMIN_PASSWORD

    # Terraform Backend
    - name: TERRAFORM_BACKEND_BUCKET
      value: "{{ terraform_backend_bucket }}"
    - name: TERRAFORM_BACKEND_REGION
      value: "{{ region }}"

    # Kubernetes Service Account Token
    - name: K8S_SA_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-sa-token
          key: token


  extraVolumeMounts:
    - name: catalog-users
      mountPath: "/catalog"
      readOnly: true

  extraVolumes:
    - name: catalog-users
      configMap:
        name: backstage-users

  appConfig:
    app:
      title: Darede Backstage
      baseUrl: https://{{ backstage_hostname }}

    organization:
      name: {{ github_org }}

    backend:
      baseUrl: https://{{ backstage_hostname }}
      auth:
        externalAccess:
          - type: legacy
            options:
              secret: ${BACKEND_SECRET}
              subject: e2e-api
            accessRestrictions:
              - plugin: scaffolder
              - plugin: catalog
      csp:
        connect-src: ['self', 'http:', 'https:']
      cors:
        origin: https://{{ backstage_hostname }}
        methods: [GET, HEAD, PATCH, POST, PUT, DELETE]
        credentials: true
      database:
        client: pg
        connection:
          host: ${POSTGRES_HOST}
          port: ${POSTGRES_PORT}
          user: ${POSTGRES_USER}
          password: ${POSTGRES_PASSWORD}
      cache:
        store: memory

    integrations:
      github:
        - host: github.com
          token: ${GITHUB_TOKEN}

    catalog:
      refreshIntervalSeconds: 100
      rules:
        - allow: [Template, Location, Component, Resource, API, System, Group, User]
      locations:
        - type: url
          target: https://github.com/{{ github_org }}/reference-implementation-aws/blob/main/templates/backstage/catalog-info.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: file
          target: /catalog/users-catalog.yaml
          rules:
            - allow: [User, Group]
      providers:
        github:
          infrastructureResources:
            organization: '{{ github_org }}'
            catalogPath: '/platform/terraform/stacks/**/catalog-info.yaml'
            filters:
              repository: '{{ infrastructure_repo }}'
            schedule:
              frequency: { minutes: 5 }
              timeout: { minutes: 3 }
      processors:
        githubOrg:
          providers:
            - target: https://github.com
              token: ${GITHUB_TOKEN}

    auth:
      environment: production
      session:
        secret: ${AUTH_SESSION_SECRET}
      providers:
        oidc:
          production:
            metadataUrl: https://{{ keycloak_hostname }}/auth/realms/platform/.well-known/openid-configuration
            clientId: backstage
            clientSecret: ${OIDC_CLIENT_SECRET}
            additionalScopes: ['profile', 'email', 'groups']
            prompt: auto
            signIn:
              resolvers:
                - resolver: emailLocalPartMatchingUserEntityName
                - resolver: emailMatchingUserEntityProfileEmail

    signInPage: oidc

    scaffolder:
      defaultAuthor:
        name: Backstage Scaffolder
        email: scaffolder@backstage.io
      defaultCommitMessage: "feat: created via Backstage scaffolder"

    kubernetes:
      serviceLocatorMethod:
        type: multiTenant
      clusterLocatorMethods:
        - type: 'config'
          clusters:
            - url: https://kubernetes.default.svc
              name: {{ cluster_name }}
              authProvider: serviceAccount
              serviceAccountToken: ${K8S_SA_TOKEN}
              skipTLSVerify: true

    argocd:
      username: admin
      password: ${ARGOCD_ADMIN_PASSWORD}
      appLocatorMethods:
        - type: 'config'
          instances:
            - name: in-cluster
              url: https://{{ argocd_hostname }}
              username: admin
              password: ${ARGOCD_ADMIN_PASSWORD}

postgresql:
  enabled: false

serviceAccount:
  create: true
  name: backstage
