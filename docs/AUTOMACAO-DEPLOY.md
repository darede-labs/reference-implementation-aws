# Automação Completa do Deploy - Zero Intervenção Manual

Este documento lista **TODAS** as automações aplicadas para garantir que o próximo `terraform apply` + `install.sh` funcione **sem nenhuma intervenção manual**.

---

## ✅ Arquivos Modificados para Automação

### 1. **Terraform: AWS Secrets Manager**
**Arquivo:** `cluster/terraform/secrets.tf`

**O que faz:**
- Cria automaticamente o secret `cnoe-ref-impl/config` no AWS Secrets Manager
- Armazena configurações do domínio e path routing
- External Secrets usa este secret para configurar aplicações

```hcl
resource "aws_secretsmanager_secret" "config" {
  name        = "cnoe-ref-impl/config"
  description = "CNOE Reference Implementation configuration for External Secrets"
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id = aws_secretsmanager_secret.config.id
  secret_string = jsonencode({
    domain       = local.domain
    path_routing = local.path_routing
  })
}
```

---

### 2. **Install Script: Configurações Fixas + Variáveis do config.yaml**
**Arquivo:** `scripts/install.sh`

**Automações aplicadas:**

#### a) GitHub Token do config.yaml
```bash
# Ler GitHub token do config.yaml (linha 161)
GITHUB_TOKEN=$(yq eval '.github_token' ${REPO_ROOT}/config.yaml)

# Usado automaticamente no secret do Backstage
kubectl create secret generic backstage-env-vars \
  --from-literal=GITHUB_TOKEN=${GITHUB_TOKEN} \
  ...
```

#### b) Helm Repositories com Retry Logic
```bash
add_helm_repo_with_retry() {
  local name=$1
  local url=$2
  local max_attempts=3
  # ... retry logic
}

add_helm_repo_with_retry "argo" "https://argoproj.github.io/argo-helm"
add_helm_repo_with_retry "external-secrets" "https://charts.external-secrets.io"
add_helm_repo_with_retry "backstage" "https://backstage.github.io/charts"
add_helm_repo_with_retry "codecentric" "https://codecentric.github.io/helm-charts"
add_helm_repo_with_retry "ingress-nginx" "https://kubernetes.github.io/ingress-nginx"
```

#### c) External Secrets IRSA Annotation
```bash
# Obter ARN da role IRSA do Terraform output
EXTERNAL_SECRETS_ROLE_ARN=$(cd ${REPO_ROOT}/cluster/terraform && terraform output -raw external_secrets_role_arn)

# Injetar dinamicamente no values.yaml do External Secrets
cat "$EXTERNAL_SECRETS_STATIC_VALUES_FILE" | \
  sed "s|\\${EXTERNAL_SECRETS_ROLE_ARN}|${EXTERNAL_SECRETS_ROLE_ARN}|g" \
  > "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"
```

#### d) Client Secret Fixo do Backstage
```bash
# Backstage secret com client secret FIXO
kubectl create secret generic backstage-env-vars \
  --namespace backstage \
  --from-literal=BACKSTAGE_CLIENT_SECRET=backstage-secret-2024 \
  --from-literal=KEYCLOAK_NAME_METADATA=https://keycloak.${DOMAIN_NAME}/auth/realms/cnoe/.well-known/openid-configuration \
  ...
```

---

### 3. **Keycloak Bootstrap Job: Configuração Completa Automática**
**Arquivo:** `packages/keycloak/keycloak-bootstrap-job.yaml`

**Automações aplicadas:**

#### a) Realm `cnoe` (idempotente)
```bash
REALM_EXISTS=$($KC_BIN get realms/cnoe 2>&1 | grep -c "realm" || echo "0")
if [ "$REALM_EXISTS" = "0" ]; then
  $KC_BIN create realms -s realm=cnoe -s enabled=true
fi
```

#### b) Client `backstage` com Client Secret Fixo
```bash
FIXED_CLIENT_SECRET="backstage-secret-2024"

$KC_BIN create clients -r cnoe \
  -s clientId=backstage \
  -s enabled=true \
  -s protocol=openid-connect \
  -s publicClient=false \
  -s 'redirectUris=["https://backstage.timedevops.click/*","http://localhost:7007/*"]' \
  ...

# Configurar client secret FIXO
$KC_BIN update clients/$ID -r cnoe -s "secret=$FIXED_CLIENT_SECRET"
```

#### c) Client Scope `groups` SIMPLES (para compatibilidade com frontend do Backstage)
```bash
# Frontend do Backstage adiciona 'groups' automaticamente (hardcoded)
# Criar scope vazio para aceitar requisição sem retornar dados
$KC_BIN create client-scopes -r cnoe \
  -s name=groups \
  -s protocol=openid-connect \
  -s "description=Empty groups scope for Backstage frontend compatibility"

# Associar como OPTIONAL (não incluído no token automaticamente)
curl -X PUT "http://keycloak-http:80/auth/admin/realms/cnoe/clients/$ID/optional-client-scopes/$GROUPS_SCOPE_ID"
```

#### d) Client Scope `email` com Protocol Mappers
```bash
# Criar scope email
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "email",
    "protocol": "openid-connect",
    "attributes": {
      "include.in.token.scope": "true",
      "display.on.consent.screen": "true"
    }
  }' \
  "http://keycloak-http:80/auth/admin/realms/cnoe/client-scopes"

# Adicionar protocol mappers (email, email_verified)
# Associar ao client backstage como default
```

#### e) Usuário `admin/admin` no realm `cnoe`
```bash
$KC_BIN create users -r cnoe \
  -s username=admin \
  -s enabled=true \
  -s email=admin@example.com \
  -s firstName=Admin \
  -s lastName=User

$KC_BIN set-password -r cnoe --username admin --new-password admin
```

---

### 4. **Backstage Values: Scopes Corretos**
**Arquivo:** `packages/backstage/values.yaml`

**Configuração aplicada:**
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
        scope: 'openid profile email'  # SEM 'groups' - será adicionado pelo frontend
        prompt: auto
        dangerouslyAllowSignInWithoutUserInCatalog: true
        resolver: {}
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
```

**Nota:** O frontend do Backstage adiciona `groups` automaticamente ao scope via JavaScript, por isso criamos o scope `groups` vazio no Keycloak.

---

### 5. **External Secrets Values: IRSA Annotation Dinâmica**
**Arquivo:** `packages/external-secrets/values.yaml`

**Configuração:**
```yaml
installCRDs: true

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${EXTERNAL_SECRETS_ROLE_ARN}
```

**Nota:** O placeholder `${EXTERNAL_SECRETS_ROLE_ARN}` é substituído pelo `install.sh` com o valor real do Terraform output.

---

## 🔑 Credenciais Configuradas

| Componente | Credential | Valor | Onde está configurado |
|------------|-----------|-------|-----------------------|
| **GitHub Token** | Personal Access Token | `config.yaml` | config.yaml → install.sh → backstage-env-vars secret |
| **Keycloak Master Realm** | admin / admin | Fixo | Helm chart codecentric |
| **Keycloak Realm cnoe** | admin / admin | Fixo | keycloak-bootstrap-job.yaml |
| **Backstage Client ID** | backstage | Fixo | keycloak-bootstrap-job.yaml |
| **Backstage Client Secret** | backstage-secret-2024 | **Fixo** | keycloak-bootstrap-job.yaml + install.sh |
| **PostgreSQL Backstage** | postgres / backstage123 | Fixo | install.sh |

---

## 📋 Client Scopes Configurados Automaticamente

### Default Client Scopes (incluídos automaticamente no token):
- ✅ `openid` (implícito no protocolo OIDC)
- ✅ `profile`
- ✅ `email`
- ✅ `web-origins`
- ✅ `roles`

### Optional Client Scopes (solicitados explicitamente):
- ✅ `groups` (vazio, para compatibilidade com frontend do Backstage)

---

## 🚀 Processo de Deploy Automatizado

### 1. Terraform Apply
```bash
cd cluster/terraform
export AWS_PROFILE=darede
terraform apply -auto-approve
```

**O que é criado automaticamente:**
- ✅ Cluster EKS
- ✅ Node groups
- ✅ VPC, subnets, security groups
- ✅ IRSA roles (External Secrets, Load Balancer Controller, etc.)
- ✅ **AWS Secrets Manager** com configuração `cnoe-ref-impl/config`

### 2. Install Script
```bash
export AWS_PROFILE=darede
export AUTO_CONFIRM=yes
./scripts/install.sh
```

**O que é instalado/configurado automaticamente:**
- ✅ ArgoCD
- ✅ External Secrets com IRSA annotation dinâmica
- ✅ Cert Manager
- ✅ Ingress NGINX
- ✅ ExternalDNS
- ✅ Keycloak (via ArgoCD ou Helm direto)
- ✅ **Keycloak Bootstrap Job** (configura realm, client, scopes, usuário)
- ✅ Backstage (via ArgoCD ou Helm direto)
- ✅ Secrets `backstage-env-vars` com client secret fixo

### 3. Validação Automática
Após ~15-20 minutos:
- ✅ Keycloak: https://keycloak.timedevops.click/auth
- ✅ Backstage: https://backstage.timedevops.click
- ✅ Login com `admin/admin` **deve funcionar imediatamente**

---

## 🐛 Problemas Resolvidos e Automatizados

### 1. ❌ Erro: `invalid_scope (Invalid scopes: openid profile email groups)`
**Causa:** Frontend do Backstage adiciona `groups` automaticamente (hardcoded)

**Solução Automatizada:**
- Scope `groups` SIMPLES criado no Keycloak (sem protocol mappers)
- Associado como OPTIONAL ao client `backstage`
- Aceita a requisição mas não retorna dados no token

**Arquivo:** `keycloak-bootstrap-job.yaml` linhas 74-89

---

### 2. ❌ Erro: `502 Bad Gateway`
**Causa:** Scope `groups` com atributos malformados causava erro de desserialização no Keycloak

**Solução Automatizada:**
- Scope `groups` criado SEM atributos customizados
- Apenas `name`, `protocol` e `description`

**Arquivo:** `keycloak-bootstrap-job.yaml` linhas 77-80

---

### 3. ❌ Erro: `invalid_client_secret`
**Causa:** Client secret gerado aleatoriamente não sincronizava entre Keycloak e Backstage

**Solução Automatizada:**
- Client secret **FIXO**: `backstage-secret-2024`
- Configurado no Keycloak: `keycloak-bootstrap-job.yaml` linha 234
- Configurado no Backstage: `install.sh` linha 165

---

### 4. ❌ Erro: External Secrets não consegue acessar AWS Secrets Manager
**Causa:** ServiceAccount do External Secrets sem annotation IRSA

**Solução Automatizada:**
- `install.sh` obtém ARN da role IRSA do Terraform output
- Injeta dinamicamente no `values.yaml` do External Secrets
- ServiceAccount criado com annotation correta

**Arquivo:** `install.sh` linhas 96-120

---

### 5. ❌ Erro: Helm repo 503 Service Unavailable
**Causa:** Repositórios Helm indisponíveis temporariamente

**Solução Automatizada:**
- Retry logic com 3 tentativas
- Sleep de 5s entre tentativas

**Arquivo:** `install.sh` linhas 55-72

---

## ✅ Checklist de Validação Pós-Deploy

Após executar `terraform apply` + `install.sh`:

- [ ] Keycloak acessível via HTTPS: https://keycloak.timedevops.click/auth
- [ ] Backstage acessível via HTTPS: https://backstage.timedevops.click
- [ ] Login no Backstage com `admin/admin` funciona
- [ ] Certificados TLS válidos (Let's Encrypt)
- [ ] Realm `cnoe` existe no Keycloak
- [ ] Client `backstage` configurado corretamente
- [ ] Client secret é `backstage-secret-2024`
- [ ] Scopes: `openid`, `profile`, `email`, `web-origins`, `roles`, `groups` (optional)
- [ ] Usuário `admin/admin` existe no realm `cnoe`
- [ ] External Secrets operacional (sem erros de permissão)

---

## 📚 Documentação Adicional

- **Credenciais:** `docs/CREDENCIAIS.md`
- **Troubleshooting Keycloak/Backstage:** `docs/KEYCLOAK-BACKSTAGE-AUTH.md`
- **Guia de Uso:** `docs/GUIA-USO-PLATAFORMA.md`

---

## 🎯 Resumo: O que NÃO precisa mais ser feito manualmente

❌ **Antes (manual):**
1. Criar realm `cnoe` no Keycloak
2. Criar client `backstage`
3. Configurar redirect URIs
4. Gerar e copiar client secret
5. Criar scopes `email` e `groups`
6. Associar scopes ao client
7. Criar usuário `admin/admin`
8. Criar secret `backstage-env-vars` no Kubernetes
9. Adicionar annotation IRSA no External Secrets
10. Adicionar Helm repositories manualmente

✅ **Agora (automatizado):**
1. `terraform apply`
2. `./scripts/install.sh`
3. ✨ **Tudo funciona!**

---

## 🔐 Segurança para Produção

**⚠️ IMPORTANTE:** As credenciais fixas são para POC/desenvolvimento.

Para produção:
1. Gerar senhas fortes e aleatórias
2. Armazenar no AWS Secrets Manager
3. Usar External Secrets para injetar nos pods
4. Habilitar rotação automática de secrets
5. Configurar MFA no Keycloak
6. Usar políticas de senha robustas

---

**Última atualização:** 11 de Dezembro de 2025
**Versão Keycloak:** 17.0.1
**Versão Backstage:** Chart backstage/backstage
