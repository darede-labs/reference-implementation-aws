# Plano de Limpeza do install.sh

## Seções a REMOVER (Keycloak)

### 1. Namespace keycloak (L16)
```bash
for ns in argocd keycloak backstage argo...  # REMOVER keycloak
```

### 2. Variável KEYCLOAK_REALM (L12)
```bash
KEYCLOAK_REALM=$(yq eval '.keycloak.realm // "cnoe"' ${CONFIG_FILE})  # REMOVER
```

### 3. KEYCLOAK_SUBDOMAIN (L60, 278, 295)
```bash
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' ${CONFIG_FILE})  # REMOVER
```

### 4. Secrets Keycloak (L265-275)
```bash
KEYCLOAK_ADMIN_USER=...
KEYCLOAK_ADMIN_PASSWORD=...
kubectl create secret generic keycloak ...  # REMOVER TUDO
```

### 5. ConfigMap domain-config (L290-298)
- Remover namespace keycloak
- Remover KEYCLOAK_SUBDOMAIN do configmap

### 6. ArgoCD Keycloak OIDC (L347-434)
- Remover configuração OIDC com Keycloak
- Remover keycloak-secret
- Remover bootstrap job Keycloak

### 7. Keycloak Ingress (L512-539)
```bash
# Apply Keycloak Ingress...  # REMOVER TUDO
```

### 8. Backstage Keycloak OIDC (L284, 300, 320)
- BACKSTAGE_OIDC_SECRET referencia Keycloak
- Remover

## Seções a ADICIONAR (Cognito)

### 1. Ler configuração Cognito do config.yaml
```bash
COGNITO_USER_POOL_ID=$(yq eval '.cognito.user_pool_id' ${CONFIG_FILE})
COGNITO_CLIENT_ID=$(yq eval '.cognito.user_pool_client_id' ${CONFIG_FILE})
COGNITO_CLIENT_SECRET=$(yq eval '.cognito.user_pool_client_secret' ${CONFIG_FILE})
COGNITO_DOMAIN=$(yq eval '.cognito.user_pool_domain' ${CONFIG_FILE})
COGNITO_REGION=$(yq eval '.cognito.region // "us-east-1"' ${CONFIG_FILE})
```

### 2. Criar Backstage secret com Cognito OIDC
```bash
OIDC_ISSUER_URL="https://cognito-idp.${COGNITO_REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}"

kubectl create secret generic backstage-env-vars \
  -n backstage \
  --from-literal=OIDC_ISSUER_URL="${OIDC_ISSUER_URL}" \
  --from-literal=OIDC_CLIENT_ID="${COGNITO_CLIENT_ID}" \
  --from-literal=OIDC_CLIENT_SECRET="${COGNITO_CLIENT_SECRET}" \
  --from-literal=BACKSTAGE_FRONTEND_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}" \
  ...
```

### 3. Auth session e backend secrets
```bash
AUTH_SESSION_SECRET=$(yq eval '.secrets.backstage.auth_session_secret' ${CONFIG_FILE})
BACKEND_SECRET=$(yq eval '.secrets.backstage.backend_secret' ${CONFIG_FILE})
```

## Resumo de Mudanças

| Item | Linhas | Ação |
|------|--------|------|
| Namespace keycloak | L16 | REMOVER |
| KEYCLOAK_REALM | L12 | REMOVER |
| KEYCLOAK_SUBDOMAIN | L60, 278, 295 | REMOVER |
| Secrets Keycloak | L265-275 | REMOVER |
| ConfigMap domain-config | L290-298 | ATUALIZAR (remover keycloak) |
| ArgoCD Keycloak OIDC | L347-434 | REMOVER |
| Keycloak Ingress | L512-539 | REMOVER |
| Backstage OIDC | L284, 300, 320 | ATUALIZAR para Cognito |
| Cognito config | NOVO | ADICIONAR |
| BACKSTAGE_FRONTEND_URL | NOVO | ADICIONAR |

## Validação Pós-Limpeza

- [ ] Nenhuma referência a "keycloak" no install.sh
- [ ] config.yaml lido 100%
- [ ] Cognito OIDC configurado
- [ ] BACKSTAGE_FRONTEND_URL injetado
- [ ] Namespace keycloak não criado
- [ ] Teste de instalação limpa OK

---

Data: 2026-01-05 21:33 UTC-3
Próximo: Executar limpeza sistemática
