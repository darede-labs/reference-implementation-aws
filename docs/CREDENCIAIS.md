# Credenciais da Plataforma

Este documento contém todas as credenciais fixas configuradas na plataforma para facilitar o acesso e troubleshooting.

---

## 🔐 Keycloak

### Realm: `cnoe`

**Usuário Administrador:**
- **Username:** `admin`
- **Password:** `admin`
- **Email:** `admin@example.com`

**Client Backstage:**
- **Client ID:** `backstage`
- **Client Secret:** `backstage-secret-2024` (fixo)
- **Redirect URIs:** `https://backstage.timedevops.click/*`, `http://localhost:7007/*`

### Acesso Admin Console

**URL:** https://keycloak.timedevops.click/auth

**Credenciais Master Realm:**
- **Username:** `admin`
- **Password:** `admin`

---

## 🎭 Backstage

**URL:** https://backstage.timedevops.click

**Login via Keycloak:**
- **Username:** `admin`
- **Password:** `admin`
- **Provider:** Keycloak OIDC (realm: `cnoe`)

---

## 📊 ArgoCD

**URL:** https://argocd.timedevops.click

**Credenciais:**
- **Username:** `admin`
- **Password:** Obtido via comando:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

---

## 🔧 Valores Técnicos

### Client Secret do Backstage

O client secret do Backstage é **fixo** e está configurado em:

1. **Keycloak Bootstrap Job:** `packages/keycloak/keycloak-bootstrap-job.yaml`
   ```yaml
   FIXED_CLIENT_SECRET="backstage-secret-2024"
   ```

2. **Install Script:** `scripts/install.sh`
   ```bash
   --from-literal=BACKSTAGE_CLIENT_SECRET=backstage-secret-2024
   ```

3. **Kubernetes Secret:** `backstage-env-vars` (namespace: `backstage`)
   ```bash
   kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.BACKSTAGE_CLIENT_SECRET}' | base64 -d
   # Output: backstage-secret-2024
   ```

### Verificar Client Secret no Keycloak

Se precisar verificar o client secret configurado no Keycloak:

```bash
kubectl exec -n keycloak keycloak-0 -- bash -c '
/opt/jboss/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080/auth \
  --realm master \
  --user admin \
  --password admin

CLIENT_ID=$(/opt/jboss/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=backstage | grep "\"id\"" | head -1 | sed "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/")

/opt/jboss/keycloak/bin/kcadm.sh get clients/$CLIENT_ID/client-secret -r cnoe | grep "\"value\""
'
```

---

## 🗄️ PostgreSQL

### Keycloak Database

- **Database:** `keycloak`
- **User:** `postgres`
- **Password:** Configurado dinamicamente pelo Helm chart

### Backstage Database

- **Database:** `backstage`
- **User:** `postgres`
- **Password:** `backstage123`

---

## ⚠️ IMPORTANTE

**Estas credenciais são para ambiente de desenvolvimento/POC.**

Para ambientes de produção:
1. Use senhas fortes e aleatórias
2. Armazene credenciais no AWS Secrets Manager
3. Use rotação automática de secrets
4. Habilite MFA onde possível
5. Implemente políticas de senha robustas no Keycloak
