# ArgoCD SSO com Keycloak

Configuração de Single Sign-On (SSO) do ArgoCD com Keycloak.

---

## ✅ O Que Foi Configurado

### 1. **Client ArgoCD no Keycloak**

**Arquivo:** `packages/keycloak/keycloak-bootstrap-job.yaml`

**Criação automática:**
- **Client ID:** `argocd`
- **Client Secret:** `argocd-secret-2024` (fixo)
- **Redirect URIs:** `https://argocd.timedevops.click/auth/callback`
- **Protocol:** OpenID Connect
- **Flow:** Authorization Code (standard flow)

### 2. **Grupo Keycloak → Role ArgoCD**

**Grupo criado:** `superuser`
- Usuário `admin` é membro deste grupo
- Mapeado para `role:admin` no ArgoCD

### 3. **OIDC Configurado no ArgoCD**

**Arquivo:** `packages/argo-cd/values.yaml`

```yaml
configs:
  cm:
    url: https://argocd.timedevops.click
    oidc.config: |
      name: Keycloak
      issuer: https://keycloak.timedevops.click/auth/realms/cnoe
      clientID: argocd
      clientSecret: argocd-secret-2024
      requestedScopes: ["openid", "profile", "email", "groups"]
```

### 4. **RBAC Mapeamento**

```yaml
configs:
  rbac:
    policy.csv: |
      # Keycloak SSO - grupo superuser = admin
      g, superuser, role:admin
```

---

## 🔑 Como Fazer Login

### Via SSO (Keycloak) - Recomendado ✅

1. Acesse: **https://argocd.timedevops.click**
2. Clique em **"LOG IN VIA KEYCLOAK"**
3. Será redirecionado para Keycloak
4. Login:
   - **Username:** `admin`
   - **Password:** `admin`
5. ✅ Logado como admin (grupo superuser)

### Via Admin Local (Fallback)

```bash
export AWS_PROFILE=darede

# Pegar senha do admin local
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Local:"
echo "  User: admin"
echo "  Pass: $ARGOCD_PASSWORD"
```

---

## 👥 Gerenciamento de Usuários

### Adicionar Novos Usuários com Acesso Admin

```bash
export AWS_PROFILE=darede

# 1. Criar usuário no Keycloak
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080/auth \
  --realm master \
  --user admin \
  --password admin

kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh create users \
  -r cnoe \
  -s username=joao \
  -s enabled=true \
  -s email=joao@empresa.com \
  -s firstName=João \
  -s lastName=Silva

# 2. Definir senha
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh set-password \
  -r cnoe \
  --username joao \
  --new-password senha123

# 3. Adicionar ao grupo superuser
JOAO_ID=$(kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh get users -r cnoe -q username=joao | \
  grep -o '"id" *: *"[^"]*' | head -1 | cut -d'"' -f4)

SUPERUSER_GROUP_ID=$(kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh get groups -r cnoe | \
  grep -A1 '"name" *: *"superuser"' | grep '"id"' | head -1 | grep -o '[a-f0-9-]\{36\}')

kubectl exec -n keycloak deployment/keycloak -- \
  curl -s -X PUT -H "Authorization: Bearer TOKEN" \
  "http://localhost:8080/auth/admin/realms/cnoe/users/$JOAO_ID/groups/$SUPERUSER_GROUP_ID"

echo "✅ Usuário joao criado e adicionado ao grupo superuser"
```

### Criar Grupo Read-Only

```bash
# 1. Criar grupo no Keycloak
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh create groups \
  -r cnoe \
  -s name=developers

# 2. Adicionar mapeamento no ArgoCD
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
data:
  policy.csv: |
    g, backstage, role:readonly
    g, superuser, role:admin
    g, developers, role:readonly
'

# 3. Reiniciar ArgoCD
kubectl rollout restart deployment/argocd-server -n argocd
```

---

## 🔄 Atualizar Configuração (Aplicar Mudanças)

### Se Mudou config.yaml ou Values

```bash
export AWS_PROFILE=darede

# 1. Recriar Keycloak bootstrap job
kubectl delete job keycloak-bootstrap -n keycloak
kubectl apply -f packages/keycloak/keycloak-bootstrap-job.yaml

# Aguardar job completar
kubectl wait --for=condition=complete job/keycloak-bootstrap -n keycloak --timeout=300s

# 2. Atualizar ArgoCD via ArgoCD (auto-sync)
# Ou forçar sync:
kubectl patch application argo-cd -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 3. Reiniciar ArgoCD server
kubectl rollout restart deployment/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

echo "✅ ArgoCD atualizado com nova configuração SSO"
```

---

## 🐛 Troubleshooting

### Botão "LOG IN VIA KEYCLOAK" não aparece

**Causa:** OIDC config não foi aplicado

**Solução:**
```bash
# Verificar ConfigMap
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 10 oidc

# Se não aparecer, aplicar manualmente:
kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  url: https://argocd.timedevops.click
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.timedevops.click/auth/realms/cnoe
    clientID: argocd
    clientSecret: argocd-secret-2024
    requestedScopes: ["openid", "profile", "email", "groups"]
'

kubectl rollout restart deployment/argocd-server -n argocd
```

### Erro "invalid_client" ao fazer login

**Causa:** Client secret incorreto

**Solução:**
```bash
# Verificar secret no Keycloak
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080/auth \
  --realm master \
  --user admin \
  --password admin

kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=argocd

# Atualizar secret se necessário
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh update clients/ARGOCD_ID \
  -r cnoe \
  -s secret=argocd-secret-2024
```

### Login funciona mas não tem permissões de admin

**Causa:** Usuário não está no grupo superuser

**Solução:**
```bash
# Adicionar ao grupo via Keycloak UI:
# https://keycloak.timedevops.click
# Realm cnoe → Users → seu_usuario → Groups → Join Group → superuser

# Ou via CLI (ver seção "Adicionar Novos Usuários")
```

### Redirect após login vai para localhost

**Causa:** Redirect URI incorreto

**Solução:**
```bash
# Atualizar redirect URIs no client argocd
kubectl exec -n keycloak deployment/keycloak -- \
  /opt/jboss/keycloak/bin/kcadm.sh update clients/ARGOCD_ID \
  -r cnoe \
  -s 'redirectUris=["https://argocd.timedevops.click/auth/callback","https://argocd.timedevops.click/*"]'
```

---

## 📋 Credenciais Padrão

| Serviço | URL | Login | Método |
|---------|-----|-------|--------|
| **ArgoCD** | https://argocd.timedevops.click | admin / admin | SSO Keycloak ✅ |
| **ArgoCD (local)** | https://argocd.timedevops.click | admin / [secret] | Admin local |
| **Keycloak** | https://keycloak.timedevops.click | admin / admin | Admin direto |
| **Backstage** | https://backstage.timedevops.click | admin / admin | SSO Keycloak ✅ |

---

## ✅ Resumo

**Configuração automática:**
- ✅ Client `argocd` criado no Keycloak
- ✅ Secret fixo: `argocd-secret-2024`
- ✅ Grupo `superuser` criado
- ✅ Usuário `admin` no grupo `superuser`
- ✅ OIDC configurado no ArgoCD
- ✅ RBAC mapeando `superuser` → `role:admin`

**Login único (SSO):**
- ✅ Backstage e ArgoCD usam mesmas credenciais
- ✅ Login: `admin` / `admin`
- ✅ Gerenciamento centralizado no Keycloak

**Próximo deploy:**
- ✅ Tudo configurado automaticamente via `install.sh`
- ✅ Nenhuma configuração manual necessária

---

**Última atualização:** 11 de Dezembro de 2025
