#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

# Read config values
ACM_CERTIFICATE_ARN=$(yq eval '.acm_certificate_arn' ${CONFIG_FILE})

# Create all namespaces upfront to avoid race conditions
echo -e "${CYAN}📦 Creating namespaces...${NC}"
for ns in argocd backstage argo ingress-nginx external-secrets atlantis crossplane-system external-dns; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
done

# Install AWS Load Balancer Controller (required for NLB with ACM)
echo -e "${BOLD}${GREEN}🔄 Installing AWS Load Balancer Controller...${NC}"
helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 120s > /dev/null

# Install ingress-nginx with ACM certificate from config.yaml
echo -e "${BOLD}${GREEN}🔄 Installing ingress-nginx with ACM TLS termination...${NC}"
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --values ${REPO_ROOT}/packages/ingress-nginx/values.yaml \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="${ACM_CERTIFICATE_ARN}" \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s > /dev/null

echo -e "${YELLOW}⏳ Waiting for NLB to be provisioned...${NC}"
sleep 30

# Static helm values files
ARGOCD_STATIC_VALUES_FILE=${REPO_ROOT}/packages/argo-cd/values.yaml
EXTERNAL_SECRETS_STATIC_VALUES_FILE=${REPO_ROOT}/packages/external-secrets/values.yaml
ADDONS_APPSET_STATIC_VALUES_FILE=${REPO_ROOT}/packages/bootstrap/values.yaml

# Chart versions for Argo CD and ESO
ARGOCD_CHART_VERSION=$(yq '.argocd.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
EXTERNAL_SECRETS_CHART_VERSION=$(yq '.external-secrets.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)

# Custom Manifests Paths
ARGOCD_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/argo-cd/manifests
EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/external-secrets/manifests

# Build Argo CD dynamic values
# Read secrets and config from config.yaml
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' ${CONFIG_FILE})
ARGOCD_ADMIN_PASSWORD=$(yq eval '.secrets.argocd.admin_password // "argocd-admin-2024"' ${CONFIG_FILE})
GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})

ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)
cat << EOF > "$ARGOCD_DYNAMIC_VALUES_FILE"
cnoe_ref_impl: # Specific values for reference CNOE implementation to control extraObjects.
  auto_mode: $([[ "${AUTO_MODE}" == "true" ]] && echo '"true"' || echo '"false"')
global:
  domain: $([[ "${PATH_ROUTING}" == "true" ]] && echo "${DOMAIN_NAME}" || echo "${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}")
server:
  ingress:
    annotations: {}
    path: /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    tls: false
configs:
  secret:
    argocdServerAdminPassword: ${ARGOCD_ADMIN_PASSWORD}
  cm:
        - profile
        - email
        - groups
      requestedIDTokenClaims:
        groups:
          essential: true
  params:
    'server.basehref': /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.rootpath': $([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.insecure': 'true'
EOF

echo -e "${BOLD}${GREEN}🔄 Adding Helm repositories...${NC}"
# Add all required helm repos with retry logic
add_helm_repo_with_retry() {
  local name=$1
  local url=$2
  local max_attempts=3
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if helm repo add "$name" "$url" > /dev/null 2>&1; then
      echo -e "${GREEN}✅ Added helm repo: $name${NC}"
      return 0
    else
      echo -e "${YELLOW}⚠️  Attempt $attempt/$max_attempts failed for $name, retrying...${NC}"
      sleep 5
      attempt=$((attempt + 1))
    fi
  done
  echo -e "${RED}❌ Failed to add helm repo $name after $max_attempts attempts${NC}"
  return 1
}

add_helm_repo_with_retry "argo" "https://argoproj.github.io/argo-helm"
add_helm_repo_with_retry "external-secrets" "https://charts.external-secrets.io"
add_helm_repo_with_retry "backstage" "https://backstage.github.io/charts"
add_helm_repo_with_retry "codecentric" "https://codecentric.github.io/helm-charts"
add_helm_repo_with_retry "ingress-nginx" "https://kubernetes.github.io/ingress-nginx"
add_helm_repo_with_retry "runatlantis" "https://runatlantis.github.io/helm-charts"

echo -e "${YELLOW}⏳ Updating helm repos...${NC}"
helm repo update > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Argo CD...${NC}"
helm upgrade --install --wait argocd argo/argo-cd \
  --namespace argocd --version $ARGOCD_CHART_VERSION \
  --create-namespace \
  --values "$ARGOCD_STATIC_VALUES_FILE" \
  --values "$ARGOCD_DYNAMIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${YELLOW}⏳ Waiting for Argo CD to be healthy...${NC}"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null


echo -e "${BOLD}${GREEN}🔄 Installing External Secrets...${NC}"

# Get External Secrets IRSA role ARN from Terraform output
EXTERNAL_SECRETS_ROLE_ARN=$(cd ${REPO_ROOT}/cluster/terraform && terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")

if [ -z "$EXTERNAL_SECRETS_ROLE_ARN" ]; then
  echo -e "${RED}❌ Could not get External Secrets role ARN from Terraform. Using default...${NC}"
  EXTERNAL_SECRETS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/external-secrets-irsa"
fi

echo -e "${CYAN}🔐 Using IRSA role: $EXTERNAL_SECRETS_ROLE_ARN${NC}"

# Create dynamic values file with IRSA role
EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE=$(mktemp)
cat "$EXTERNAL_SECRETS_STATIC_VALUES_FILE" | \
  sed "s|\${EXTERNAL_SECRETS_ROLE_ARN}|${EXTERNAL_SECRETS_ROLE_ARN}|g" \
  > "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"

helm upgrade --install --wait external-secrets external-secrets/external-secrets \
  --namespace external-secrets --version $EXTERNAL_SECRETS_CHART_VERSION \
  --create-namespace \
  --values "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

rm -f "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"

echo -e "${YELLOW}⏳ Waiting for External Secrets to be healthy...${NC}"
kubectl wait --for=condition=available deployment/external-secrets -n external-secrets --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Atlantis (GitOps for Terraform)...${NC}"

# Read Atlantis configuration from config.yaml
ATLANTIS_SUBDOMAIN=$(yq eval '.atlantis.subdomain // "atlantis"' ${CONFIG_FILE})
ATLANTIS_WEBHOOK_SECRET=$(yq eval '.atlantis.webhook_secret // "atlantis-webhook-secret"' ${CONFIG_FILE})
ATLANTIS_AUTOMERGE=$(yq eval '.atlantis.automerge // true' ${CONFIG_FILE})

# Build Atlantis extraArgs based on config
ATLANTIS_EXTRA_ARGS=""
if [ "$ATLANTIS_AUTOMERGE" == "true" ]; then
  ATLANTIS_EXTRA_ARGS="--set extraArgs[0]=--automerge --set extraArgs[1]=--autoplan-modules"
fi

# Optional: auto-apply after plan via server-side repoConfig + post_workflow_hook.
# To enable, export ATLANTIS_AUTO_APPLY_TOKEN before running this script.
ATLANTIS_REPO_CONFIG_FILE=$(mktemp)
cat > "$ATLANTIS_REPO_CONFIG_FILE" <<'EOF'
---
repos:
- id: /.*/
  apply_requirements: []
  import_requirements: []
  allowed_overrides: [workflow, delete_source_branch_on_merge]
  allow_custom_workflows: true
  post_workflow_hooks:
    - run: |
        if [ "$COMMAND_NAME" = "plan" ] && [ "$PULL_NUM" != "" ]; then
          curl -s -X POST \
            -H "Authorization: token $AUTO_APPLY_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$BASE_REPO_OWNER/$BASE_REPO_NAME/issues/$PULL_NUM/comments" \
            -d '{"body":"atlantis apply"}' || true
        fi
EOF

ATLANTIS_AUTO_APPLY_ARGS=""
if [ -n "${ATLANTIS_AUTO_APPLY_TOKEN:-}" ]; then
  echo -e "${CYAN}🔐 Configuring Atlantis auto-apply token secret...${NC}"
  kubectl create secret generic atlantis-auto-apply-token \
    --namespace atlantis \
    --from-literal=token="${ATLANTIS_AUTO_APPLY_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  ATLANTIS_AUTO_APPLY_ARGS="--set environmentSecrets[0].name=AUTO_APPLY_TOKEN --set environmentSecrets[0].secretKeyRef.name=atlantis-auto-apply-token --set environmentSecrets[0].secretKeyRef.key=token"
fi

helm upgrade --install --wait atlantis runatlantis/atlantis \
  --namespace atlantis \
  --create-namespace \
  --set github.user="${GITHUB_ORG}" \
  --set github.token="${GITHUB_TOKEN}" \
  --set github.secret="${ATLANTIS_WEBHOOK_SECRET}" \
  --set orgAllowlist="github.com/${GITHUB_ORG}/*" \
  --set ingress.enabled=true \
  --set ingress.host="${ATLANTIS_SUBDOMAIN}.${DOMAIN_NAME}" \
  --set ingress.ingressClassName=nginx \
  --set ingress.path=/ \
  --set serviceAccount.create=true \
  --set serviceAccount.name=atlantis \
  --set-file repoConfig="$ATLANTIS_REPO_CONFIG_FILE" \
  ${ATLANTIS_EXTRA_ARGS} \
  ${ATLANTIS_AUTO_APPLY_ARGS} \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

rm -f "$ATLANTIS_REPO_CONFIG_FILE"

echo -e "${YELLOW}⏳ Waiting for Atlantis to be healthy...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=atlantis -n atlantis --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${BOLD}${GREEN}🔄 Applying custom manifests...${NC}"

# Create hub-cluster-secret directly (workaround for SCP restrictions on Secrets Manager)
echo -e "${CYAN}🔐 Creating hub-cluster-secret with configuration from config.yaml...${NC}"
HUB_CLUSTER_SECRET_MANIFEST=$(mktemp)
cat ${REPO_ROOT}/packages/argo-cd/manifests/hub-cluster-secret-direct.yaml | \
  sed "s|\${CLUSTER_NAME}|${CLUSTER_NAME}|g" | \
  sed "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" | \
  sed "s|\${DOMAIN}|${DOMAIN_NAME}|g" | \
  sed "s|\${AWS_REGION}|${AWS_REGION}|g" | \
  sed "s|\${AWS_ACCOUNT_ID}|${AWS_ACCOUNT_ID}|g" | \
  sed "s|\${ROUTE53_HOSTED_ZONE_ID}|$(yq '.route53_hosted_zone_id' ${CONFIG_FILE})|g" | \
  sed "s|\${PATH_ROUTING}|${PATH_ROUTING}|g" | \
  sed "s|\${REPO_URL}|$(yq '.repo.url' ${CONFIG_FILE})|g" | \
  sed "s|\${REPO_REVISION}|$(yq '.repo.revision' ${CONFIG_FILE})|g" | \
  sed "s|\${REPO_BASEPATH}|$(yq '.repo.basepath' ${CONFIG_FILE})|g" | \
  sed "s|\${AUTO_MODE}|${AUTO_MODE}|g" \
  > "$HUB_CLUSTER_SECRET_MANIFEST"

kubectl apply -f "$HUB_CLUSTER_SECRET_MANIFEST" --kubeconfig $KUBECONFIG_FILE > /dev/null
rm "$HUB_CLUSTER_SECRET_MANIFEST"

# Create application secrets (workaround for SCP restrictions on Secrets Manager)
echo -e "${CYAN}🔐 Creating application secrets for Backstage, Argo Workflows...${NC}"

# Read Backstage configuration from config.yaml
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
INFRA_REPO=$(yq eval '.infrastructure_repo' ${CONFIG_FILE})
TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' ${CONFIG_FILE})

# Cognito OIDC configuration
COGNITO_USER_POOL_ID=$(yq eval '.cognito.user_pool_id' ${CONFIG_FILE})
COGNITO_CLIENT_ID=$(yq eval '.cognito.user_pool_client_id' ${CONFIG_FILE})
COGNITO_CLIENT_SECRET=$(yq eval '.cognito.user_pool_client_secret' ${CONFIG_FILE})
COGNITO_REGION=$(yq eval '.cognito.region // "us-east-1"' ${CONFIG_FILE})
OIDC_ISSUER_URL="https://cognito-idp.${COGNITO_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}"

# Backstage secrets
AUTH_SESSION_SECRET=$(yq eval '.secrets.backstage.auth_session_secret // "backstage-session-secret-2024"' ${CONFIG_FILE})
BACKEND_SECRET=$(yq eval '.secrets.backstage.backend_secret // "backstage-backend-secret-2024"' ${CONFIG_FILE})
POSTGRES_HOST=$(yq eval '.secrets.backstage.postgres_host // "backstage-postgresql"' ${CONFIG_FILE})
POSTGRES_PORT=$(yq eval '.secrets.backstage.postgres_port // "5432"' ${CONFIG_FILE})
POSTGRES_USER=$(yq eval '.secrets.backstage.postgres_user // "backstage"' ${CONFIG_FILE})
POSTGRES_PASSWORD=$(yq eval '.secrets.backstage.postgres_password // "backstage123"' ${CONFIG_FILE})

# Backstage Frontend URL
BACKSTAGE_FRONTEND_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"

echo -e "${CYAN}🔐 Creating Backstage environment variables secret..."
# Create service account for Backstage Kubernetes plugin
kubectl create serviceaccount backstage-k8s -n backstage --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding backstage-k8s --clusterrole=view --serviceaccount=backstage:backstage-k8s --dry-run=client -o yaml | kubectl apply -f -

# Create secret with K8s token and other env vars
K8S_TOKEN=$(kubectl -n backstage create token backstage-k8s --duration=87600h 2>/dev/null || kubectl -n backstage create token backstage-k8s --duration=24h)
kubectl create secret generic backstage-env-vars \
  -n backstage \
  --from-literal=POSTGRES_HOST=${POSTGRES_HOST} \
  --from-literal=POSTGRES_PORT=${POSTGRES_PORT} \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  --from-literal=GITHUB_TOKEN=$GITHUB_TOKEN \
  --from-literal=ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --from-literal=OIDC_ISSUER_URL="${OIDC_ISSUER_URL}" \
  --from-literal=OIDC_CLIENT_ID="${COGNITO_CLIENT_ID}" \
  --from-literal=OIDC_CLIENT_SECRET="${COGNITO_CLIENT_SECRET}" \
  --from-literal=AUTH_SESSION_SECRET="${AUTH_SESSION_SECRET}" \
  --from-literal=BACKEND_SECRET="${BACKEND_SECRET}" \
  --from-literal=BACKSTAGE_FRONTEND_URL="${BACKSTAGE_FRONTEND_URL}" \
  --from-literal=K8S_SA_TOKEN="$K8S_TOKEN" \
  --from-literal=GITHUB_ORG="$GITHUB_ORG" \
  --from-literal=INFRA_REPO="$INFRA_REPO" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$TF_BACKEND_BUCKET" \
  --from-literal=TERRAFORM_BACKEND_REGION="$TF_BACKEND_REGION" \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# ArgoCD repository credential for private infrastructure repo
# Using GitHub OAuth format: token as username, x-oauth-basic as password
echo -e "${CYAN}🔐 Creating ArgoCD repository credentials for private repo...${NC}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
apiVersion: v1
kind: Secret
metadata:
  name: repo-${INFRA_REPO}-credentials
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/${GITHUB_ORG}/${INFRA_REPO}
  username: ${GITHUB_TOKEN}
  password: x-oauth-basic
EOF

echo "✅ ArgoCD configured with admin password from config.yaml"
# ArgoCD is now configured with simple admin password
# OIDC/SSO can be added later if needed via ArgoCD ConfigMap

# Apply Crossplane Compositions (S3, VPC, SecurityGroup, EC2, RDS, EKS)
echo -e "${CYAN}🔧 Creating Crossplane Compositions...${NC}"
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/s3-bucket-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/s3-bucket-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/vpc-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/vpc-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/securitygroup-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/securitygroup-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/ec2-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/ec2-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/rds-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/rds-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/eks-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/eks-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create ArgoCD Application for infrastructure repo
echo -e "${CYAN}📦 Creating ArgoCD Application for infrastructure resources...${NC}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_ORG}/${INFRA_REPO}
    targetRevision: main
    path: s3-buckets
    directory:
      recurse: false
      exclude: 'catalog-info.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
  - group: "*"
    kind: "*"
    managedFieldsManagers:
    - kube-controller-manager
EOF

# Apply other custom manifests (skip hub-cluster-secret.yaml as we created it directly)
for manifest in "$ARGOCD_CUSTOM_MANIFESTS_PATH"/*.yaml; do
  if [[ ! "$manifest" =~ hub-cluster-secret\.yaml$ ]]; then
    kubectl apply -f "$manifest" --kubeconfig $KUBECONFIG_FILE > /dev/null
  fi
done

kubectl apply -f "$EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH" --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Infrastructure ArgoCD Application...${NC}"
kubectl apply -f "$ARGOCD_CUSTOM_MANIFESTS_PATH/infrastructure-app.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Addons AppSet Argo CD application...${NC}"
helm upgrade --install --wait addons-appset ${REPO_ROOT}/packages/appset-chart \
  --namespace argocd \
  --values "$ADDONS_APPSET_STATIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

# Wait for Argo CD applications to sync
sleep 10
wait_for_apps

# Backstage integration with AWS Cognito
echo -e "\n${BOLD}${GREEN}🔐 Backstage configured with AWS Cognito OIDC...${NC}"

# Apply Backstage Ingress (dynamic from config.yaml)
echo -e "${CYAN}🌐 Creating Backstage Ingress...${NC}"
BACKSTAGE_HOST="${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backstage
  namespace: backstage
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${BACKSTAGE_HOST}
spec:
  ingressClassName: nginx
  rules:
  - host: ${BACKSTAGE_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: backstage
            port:
              number: 7007
EOF

# Generate dynamic Backstage values overlay with correct domain URLs
echo -e "${CYAN}🔧 Generating dynamic Backstage configuration...${NC}"
BACKSTAGE_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
ARGOCD_URL="https://${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}"
REPO_URL=$(yq eval '.repo.url' ${CONFIG_FILE})

cat > /tmp/backstage-dynamic-values.yaml <<EOF
ingress:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${BACKSTAGE_HOST}
  host: ${BACKSTAGE_HOST}
backstage:
  extraEnvVars:
    - name: BACKSTAGE_FRONTEND_URL
      value: ${BACKSTAGE_URL}
    - name: ARGO_CD_URL
      value: ${ARGOCD_URL}
    - name: ARGO_WORKFLOWS_URL
      value: https://argo-workflows.${DOMAIN_NAME}
    - name: GITHUB_ORG
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: GITHUB_ORG
    - name: INFRA_REPO
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: INFRA_REPO
    - name: TERRAFORM_BACKEND_BUCKET
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: TERRAFORM_BACKEND_BUCKET
    - name: TERRAFORM_BACKEND_REGION
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: TERRAFORM_BACKEND_REGION
  appConfig:
    catalog:
      locations:
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-s3/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-ec2/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-security-group/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-vpc/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-eks/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-secrets/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-destroy/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: https://github.com/${GITHUB_ORG}/${INFRA_REPO}/blob/main/catalog-info.yaml
          rules:
            - allow: [Location, Component, Resource, API, System]
      providers:
        github:
          infrastructureResources:
            organization: '${GITHUB_ORG}'
            catalogPath: '/platform/terraform/stacks/**/catalog-info.yaml'
            filters:
              repository: '${INFRA_REPO}'
            schedule:
              frequency: { minutes: 5 }
              timeout: { minutes: 3 }
EOF

# Create ConfigMap with dynamic Backstage values
kubectl create configmap backstage-dynamic-values \
  --namespace backstage \
  --from-file=values.yaml=/tmp/backstage-dynamic-values.yaml \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${GREEN}✅ Backstage configured with AWS Cognito OIDC${NC}"
echo -e "${CYAN}📋 Backstage uses Cognito for authentication - no Keycloak bootstrap needed${NC}"

echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}📊 You can now access your resources and start deploying applications.${NC}"
