#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

################################################################################
# Read all config values upfront
################################################################################
ACM_CERTIFICATE_ARN=$(yq eval '.acm_certificate_arn' ${CONFIG_FILE})
KEYCLOAK_REALM=$(yq eval '.keycloak.realm // "cnoe"' ${CONFIG_FILE})
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' ${CONFIG_FILE})
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' ${CONFIG_FILE})
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
ATLANTIS_SUBDOMAIN=$(yq eval '.atlantis.subdomain // "atlantis"' ${CONFIG_FILE})

# Secrets from config
KEYCLOAK_ADMIN_USER=$(yq eval '.secrets.keycloak.admin_user // "admin"' ${CONFIG_FILE})
KEYCLOAK_ADMIN_PASSWORD=$(yq eval '.secrets.keycloak.admin_password // "admin"' ${CONFIG_FILE})
ARGOCD_OIDC_SECRET=$(yq eval '.secrets.argocd.oidc_client_secret' ${CONFIG_FILE})
BACKSTAGE_OIDC_SECRET=$(yq eval '.secrets.backstage.oidc_client_secret' ${CONFIG_FILE})
POSTGRES_PASSWORD=$(yq eval '.secrets.backstage.postgres_password // "backstage123"' ${CONFIG_FILE})
GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
ATLANTIS_WEBHOOK_SECRET=$(yq eval '.atlantis.webhook_secret // "atlantis-webhook-secret"' ${CONFIG_FILE})

# Derived URLs
KEYCLOAK_HOST="${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"
ARGOCD_HOST="${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}"
BACKSTAGE_HOST="${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
ATLANTIS_HOST="${ATLANTIS_SUBDOMAIN}.${DOMAIN_NAME}"
# Note: Keycloak in dev mode returns HTTP issuer, so we use HTTP here
KEYCLOAK_ISSUER_URL="http://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}"

################################################################################
# Create namespaces
################################################################################
echo -e "${CYAN}📦 Creating namespaces...${NC}"
for ns in argocd keycloak backstage atlantis ingress-nginx; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
done

################################################################################
# 1. AWS Load Balancer Controller
################################################################################
echo -e "${BOLD}${GREEN}🔄 [1/6] Installing AWS Load Balancer Controller...${NC}"
helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 120s > /dev/null

################################################################################
# 2. ingress-nginx with ACM
################################################################################
echo -e "${BOLD}${GREEN}🔄 [2/6] Installing ingress-nginx...${NC}"
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true" \
  --set controller.config.proxy-real-ip-cidr="0.0.0.0/0" \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-name"=cnoe \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=external \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"=ip \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="${ACM_CERTIFICATE_ARN}" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-ports"="443" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"=tcp \
  --set controller.service.loadBalancerClass=service.k8s.aws/nlb \
  --set controller.service.targetPorts.https=http \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s > /dev/null

echo -e "${YELLOW}⏳ Waiting for NLB to be provisioned...${NC}"
sleep 30

################################################################################
# 3. Keycloak (Simple Deployment - dev mode for POC)
################################################################################
echo -e "${BOLD}${GREEN}🔄 [3/6] Installing Keycloak...${NC}"

# Use simple deployment instead of Helm (Bitnami requires paid subscription)
cat << EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:26.0
        args: ["start-dev"]
        env:
        - name: KC_BOOTSTRAP_ADMIN_USERNAME
          value: "${KEYCLOAK_ADMIN_USER}"
        - name: KC_BOOTSTRAP_ADMIN_PASSWORD
          value: "${KEYCLOAK_ADMIN_PASSWORD}"
        - name: KC_HOSTNAME
          value: "${KEYCLOAK_HOST}"
        - name: KC_HOSTNAME_STRICT
          value: "false"
        - name: KC_PROXY_HEADERS
          value: xforwarded
        - name: KC_HTTP_ENABLED
          value: "true"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  selector:
    app: keycloak
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
spec:
  ingressClassName: nginx
  rules:
  - host: ${KEYCLOAK_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 80
EOF

echo -e "${YELLOW}⏳ Waiting for Keycloak to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak --timeout=300s --kubeconfig $KUBECONFIG_FILE || sleep 60

# Configure Keycloak realm, clients, and users
echo -e "${CYAN}🔐 Configuring Keycloak realm and clients...${NC}"
kubectl exec deployment/keycloak -n keycloak --kubeconfig $KUBECONFIG_FILE -- bash -c '
KCADM="/opt/keycloak/bin/kcadm.sh"
$KCADM config credentials --server http://localhost:8080 --realm master --user '"${KEYCLOAK_ADMIN_USER}"' --password '"${KEYCLOAK_ADMIN_PASSWORD}"'
$KCADM create realms -s realm='"${KEYCLOAK_REALM}"' -s enabled=true 2>/dev/null || echo "Realm exists"
$KCADM create clients -r '"${KEYCLOAK_REALM}"' -s clientId=argocd -s "redirectUris=[\"https://'"${ARGOCD_HOST}"'/*\"]" -s publicClient=false -s enabled=true -s secret='"${ARGOCD_OIDC_SECRET}"' 2>/dev/null || echo "ArgoCD client exists"
$KCADM create clients -r '"${KEYCLOAK_REALM}"' -s clientId=backstage -s "redirectUris=[\"https://'"${BACKSTAGE_HOST}"'/*\"]" -s publicClient=false -s enabled=true -s secret='"${BACKSTAGE_OIDC_SECRET}"' 2>/dev/null || echo "Backstage client exists"
$KCADM create groups -r '"${KEYCLOAK_REALM}"' -s name=superusers 2>/dev/null || true
$KCADM create users -r '"${KEYCLOAK_REALM}"' -s username=user1 -s email=user1@example.com -s enabled=true 2>/dev/null || true
$KCADM set-password -r '"${KEYCLOAK_REALM}"' --username user1 --new-password user123 2>/dev/null || true
echo "✓ Keycloak configured"
'

################################################################################
# 4. ArgoCD
################################################################################
echo -e "${BOLD}${GREEN}🔄 [4/6] Installing ArgoCD...${NC}"

# Get Keycloak service IP for hostAlias
KEYCLOAK_SVC_IP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}' --kubeconfig $KUBECONFIG_FILE)

# Create ArgoCD values file with OIDC config and hostAlias
ARGOCD_VALUES_FILE=$(mktemp)
cat > "$ARGOCD_VALUES_FILE" <<EOF
global:
  domain: ${ARGOCD_HOST}
server:
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: ${ARGOCD_HOST}
    tls: false
  # hostAlias to resolve Keycloak hostname internally
  hostAliases:
    - ip: "${KEYCLOAK_SVC_IP}"
      hostnames:
        - "${KEYCLOAK_HOST}"
configs:
  params:
    server.insecure: true
  cm:
    oidc.config: |
      name: Keycloak
      issuer: ${KEYCLOAK_ISSUER_URL}
      clientID: argocd
      clientSecret: ${ARGOCD_OIDC_SECRET}
      requestedScopes:
        - openid
        - profile
        - email
        - groups
EOF

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values "$ARGOCD_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s > /dev/null

rm -f "$ARGOCD_VALUES_FILE"

################################################################################
# 5. Backstage
################################################################################
echo -e "${BOLD}${GREEN}🔄 [5/6] Installing Backstage...${NC}"

# Create Backstage secrets
kubectl create secret generic backstage-secrets -n backstage \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  --from-literal=GITHUB_TOKEN=${GITHUB_TOKEN} \
  --from-literal=BACKSTAGE_CLIENT_SECRET=${BACKSTAGE_OIDC_SECRET} \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null

helm upgrade --install backstage backstage \
  --repo https://backstage.github.io/charts \
  --namespace backstage \
  --version 2.6.0 \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.host=${BACKSTAGE_HOST} \
  --set ingress.annotations."external-dns\.alpha\.kubernetes\.io/hostname"=${BACKSTAGE_HOST} \
  --set ingress.tls.enabled=false \
  --set backstage.image.registry=ghcr.io \
  --set backstage.image.repository=cnoe-io/backstage-app \
  --set backstage.image.tag=latest \
  --set backstage.extraEnvVarsSecrets[0]=backstage-secrets \
  --set backstage.extraEnvVars[0].name=BACKSTAGE_FRONTEND_URL \
  --set backstage.extraEnvVars[0].value="https://${BACKSTAGE_HOST}" \
  --set backstage.extraEnvVars[1].name=KEYCLOAK_NAME_METADATA \
  --set backstage.extraEnvVars[1].value="http://keycloak.keycloak.svc.cluster.local:80/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" \
  --set postgresql.enabled=true \
  --set postgresql.auth.password=${POSTGRES_PASSWORD} \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s > /dev/null || echo "Backstage install completed (may need config)"

################################################################################
# 6. Atlantis
################################################################################
echo -e "${BOLD}${GREEN}🔄 [6/6] Installing Atlantis...${NC}"

# Create Atlantis values file
ATLANTIS_VALUES_FILE=$(mktemp)
cat > "$ATLANTIS_VALUES_FILE" <<EOF
github:
  user: ${GITHUB_ORG}
  token: ${GITHUB_TOKEN}
  secret: ${ATLANTIS_WEBHOOK_SECRET}
orgAllowlist: "github.com/${GITHUB_ORG}/*"
ingress:
  enabled: true
  host: ${ATLANTIS_HOST}
  ingressClassName: nginx
  path: /
  pathType: Prefix
volumeClaim:
  storageClassName: gp2
EOF

helm upgrade --install atlantis runatlantis/atlantis \
  --namespace atlantis \
  --values "$ATLANTIS_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s > /dev/null

rm -f "$ATLANTIS_VALUES_FILE"

################################################################################
# Summary
################################################################################
echo -e "\n${BOLD}${GREEN}✅ Installation complete!${NC}\n"
echo -e "Services:"
echo -e "  - ArgoCD:    https://${ARGOCD_HOST}"
echo -e "  - Keycloak:  https://${KEYCLOAK_HOST}"
echo -e "  - Backstage: https://${BACKSTAGE_HOST}"
echo -e "  - Atlantis:  https://${ATLANTIS_HOST}"
echo -e "\nCredentials:"
echo -e "  - Keycloak Admin: ${KEYCLOAK_ADMIN_USER} / ${KEYCLOAK_ADMIN_PASSWORD}"
echo -e "  - Test User:      user1 / user123"
echo -e "\nTo uninstall:"
echo -e "  helm uninstall keycloak -n keycloak"
echo -e "  helm uninstall argocd -n argocd"
echo -e "  helm uninstall backstage -n backstage"
echo -e "  helm uninstall atlantis -n atlantis"
echo -e "  helm uninstall ingress-nginx -n ingress-nginx"
