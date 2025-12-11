# Configuração de Autenticação Keycloak + Backstage

## ⚠️ IMPORTANTE: Scope `groups` incompatível com Keycloak 17

O scope `groups` causa erro `Invalid parameter value for: scope` no Keycloak 17.0.1.

**NÃO** incluir `groups` nos scopes configurados.

---

## ✅ Configuração Correta

### 1. Keycloak Bootstrap Job

**Arquivo:** `packages/keycloak/keycloak-bootstrap-job.yaml`

**NÃO criar scope `groups`:**
```yaml
# NOTA: O scope 'groups' causa erro "Invalid parameter value" no Keycloak 17
# Removido para evitar problemas de autenticação
echo "⚠️  Scope 'groups' não será criado (incompatível com Keycloak 17)"
```

**Client Scopes que DEVEM ser criados:**
- `email` (criado automaticamente no bootstrap job)
- `profile` (padrão do realm)
- `web-origins` (padrão do realm)
- `roles` (padrão do realm)

### 2. Backstage Values

**Arquivo:** `packages/backstage/values.yaml`

```yaml
auth:
  environment: development
  providers:
    guest: {}
    keycloak-oidc:
      development:
        metadataUrl: ${KEYCLOAK_NAME_METADATA}
        clientId: backstage
        clientSecret: ${BACKSTAGE_CLIENT_SECRET}
        scope: 'openid profile email'  # SEM 'groups'
        prompt: auto
        dangerouslyAllowSignInWithoutUserInCatalog: true
```

### 3. Install Script

**Arquivo:** `scripts/install.sh`

```bash
# Backstage secret com client secret FIXO
kubectl create secret generic backstage-env-vars \
  --namespace backstage \
  --from-literal=BACKSTAGE_CLIENT_SECRET=backstage-secret-2024 \
  --from-literal=KEYCLOAK_NAME_METADATA=https://keycloak.${DOMAIN_NAME}/auth/realms/cnoe/.well-known/openid-configuration \
  ...
```

---

## 🔧 Credenciais Fixas

### Keycloak
- **Realm:** `cnoe`
- **Admin User:** `admin` / `admin`

### Backstage Client
- **Client ID:** `backstage`
- **Client Secret:** `backstage-secret-2024` (FIXO)
- **Redirect URIs:**
  - `https://backstage.timedevops.click/*`
  - `http://localhost:7007/*`

---

## 🐛 Troubleshooting

### Erro: "invalid_scope (Invalid scopes: openid profile email groups)"

**Causa:** O browser ou Backstage está adicionando `groups` automaticamente.

**Solução:**

1. **Limpar cache do browser:**
   ```
   Chrome: Ctrl+Shift+Delete → Limpar dados de navegação → Cookies e cache
   ```

2. **Usar aba anônima/privada:**
   - Abre uma janela anônima e acesse o Backstage

3. **Verificar ConfigMap do Backstage:**
   ```bash
   kubectl get configmap backstage-app-config -n backstage -o yaml | grep "scope:"
   # Deve retornar: scope: openid profile email
   ```

4. **Verificar client scopes no Keycloak:**
   ```bash
   kubectl exec -n keycloak keycloak-0 -- bash -c '
   /opt/jboss/keycloak/bin/kcadm.sh config credentials \
     --server http://localhost:8080/auth \
     --realm master --user admin --password admin

   CLIENT_ID=$(/opt/jboss/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=backstage | grep "\"id\"" | head -1 | sed "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/")

   /opt/jboss/keycloak/bin/kcadm.sh get clients/$CLIENT_ID/default-client-scopes -r cnoe --fields name
   '
   # NÃO deve retornar 'groups'
   ```

5. **Se `groups` existir, deletá-lo:**
   ```bash
   kubectl exec -n keycloak keycloak-0 -- bash -c '
   /opt/jboss/keycloak/bin/kcadm.sh config credentials \
     --server http://localhost:8080/auth \
     --realm master --user admin --password admin

   GROUPS_ID=$(/opt/jboss/keycloak/bin/kcadm.sh get client-scopes -r cnoe | grep -B 2 "\"name\" *: *\"groups\"" | grep "\"id\"" | head -1 | sed "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/")

   /opt/jboss/keycloak/bin/kcadm.sh delete client-scopes/$GROUPS_ID -r cnoe
   '
   ```

6. **Reiniciar Backstage:**
   ```bash
   kubectl delete pod -n backstage -l app.kubernetes.io/name=backstage
   ```

### Erro: "502 Bad Gateway"

**Causa:** Keycloak não está respondendo ou scope inválido.

**Solução:**
1. Verificar pods do Keycloak:
   ```bash
   kubectl get pods -n keycloak
   ```

2. Verificar logs do Keycloak:
   ```bash
   kubectl logs -n keycloak keycloak-0 --tail=50
   ```

3. Testar conectividade:
   ```bash
   curl -I https://keycloak.timedevops.click/auth/realms/cnoe
   ```

### Erro: "invalid_client_secret"

**Causa:** Client secret do Backstage não está sincronizado com o Keycloak.

**Solução:**
1. Verificar secret no Keycloak:
   ```bash
   kubectl exec -n keycloak keycloak-0 -- bash -c '
   /opt/jboss/keycloak/bin/kcadm.sh config credentials \
     --server http://localhost:8080/auth \
     --realm master --user admin --password admin

   CLIENT_ID=$(/opt/jboss/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=backstage | grep "\"id\"" | head -1 | sed "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/")

   /opt/jboss/keycloak/bin/kcadm.sh get clients/$CLIENT_ID/client-secret -r cnoe | grep "\"value\""
   '
   # Deve retornar: "value" : "backstage-secret-2024"
   ```

2. Atualizar secret do Backstage se necessário:
   ```bash
   kubectl patch secret backstage-env-vars -n backstage \
     -p '{"data":{"BACKSTAGE_CLIENT_SECRET":"'$(echo -n backstage-secret-2024 | base64)'"}}'

   kubectl delete pod -n backstage -l app.kubernetes.io/name=backstage
   ```

---

## ✅ Validação Final

Após deploy automático, validar:

1. ✅ Keycloak acessível: `https://keycloak.timedevops.click/auth`
2. ✅ Backstage acessível: `https://backstage.timedevops.click`
3. ✅ Login funciona com `admin/admin`
4. ✅ Scopes corretos (sem `groups`)
5. ✅ Client secret fixo: `backstage-secret-2024`

---

## 📚 Referências

- [Backstage Auth Documentation](https://backstage.io/docs/auth/)
- [Keycloak 17 OIDC](https://www.keycloak.org/docs/17.0/securing_apps/)
- Credenciais completas: `docs/CREDENCIAIS.md`
