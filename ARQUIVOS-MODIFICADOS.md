# Arquivos Modificados para Deploy Automático

## ✅ Todos os arquivos abaixo foram atualizados para garantir deploy 100% automático

---

## 🔧 Terraform

### 1. `cluster/terraform/secrets.tf` ✨ NOVO
**Criado automaticamente:**
- Secret `cnoe-ref-impl/config` no AWS Secrets Manager
- Armazena domain e path_routing do config.yaml
- Usado pelo External Secrets para configurar apps

---

## 📦 Scripts de Instalação

### 2. `scripts/install.sh` ✏️ MODIFICADO
**Automações adicionadas:**
- **Linhas 53-82:** Helm repos com retry logic (argo, external-secrets, backstage, codecentric, ingress-nginx)
- **Linhas 96-120:** External Secrets IRSA annotation dinâmica do Terraform output
- **Linha 165:** Client secret fixo `backstage-secret-2024`
- **Linha 166:** KEYCLOAK_NAME_METADATA com URL HTTPS pública

---

## 🔐 Keycloak

### 3. `packages/keycloak/keycloak-bootstrap-job.yaml` ✏️ MODIFICADO
**Automações configuradas:**
- **Linha 29:** Client secret fixo `backstage-secret-2024`
- **Linhas 34-41:** Criação idempotente do realm `cnoe`
- **Linhas 46-63:** Criação do client `backstage` com redirect URIs
- **Linhas 74-89:** Criação do scope `groups` SIMPLES (OPTIONAL) para compatibilidade com frontend do Backstage
- **Linhas 91-212:** Criação e associação do scope `email` com protocol mappers
- **Linhas 214-230:** Criação do usuário `admin/admin` no realm `cnoe`
- **Linha 234:** Configuração do client secret fixo no Keycloak

### 4. `packages/keycloak/codecentric-values.yaml` ✏️ MODIFICADO
**Configuração aplicada:**
- **Linhas 4-10:** KEYCLOAK_FRONTEND_URL para URLs públicas HTTPS nos metadados OIDC
- PostgreSQL configurado com imagem bitnamilegacy

### 5. `packages/keycloak/keycloak-ingress.yaml` ✏️ MODIFICADO
- Ingress com TLS cert-manager
- Service correto: `keycloak-http`

### 6. `packages/keycloak/values.yaml` ✏️ MODIFICADO
- Imagens bitnamilegacy para Keycloak e PostgreSQL
- Autenticação simplificada

---

## 🎭 Backstage

### 7. `packages/backstage/values.yaml` ✏️ MODIFICADO
**Configurações aplicadas:**
- **Linha 110:** Scope `openid profile email` (sem groups - adicionado pelo frontend)
- **Linhas 112-119:** Configurações para desabilitar adição automática de scopes problemáticos
  - `dangerouslyAllowSignInWithoutUserInCatalog: true`
  - `resolver: {}`
  - `signIn.resolvers` com emailMatchingUserEntityProfileEmail
- PostgreSQL com imagem bitnamilegacy

### 8. `packages/backstage/backstage-ingress.yaml` ✏️ MODIFICADO
- Ingress com TLS cert-manager
- Secret correto: `backstage-server-tls`

---

## 🔑 External Secrets

### 9. `packages/external-secrets/values.yaml` ✏️ MODIFICADO
**Configuração:**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${EXTERNAL_SECRETS_ROLE_ARN}
```
- Placeholder substituído dinamicamente pelo `install.sh`

---

## 📚 Documentação

### 10. `docs/CREDENCIAIS.md` ✨ NOVO
- Todas as credenciais fixas da plataforma
- Comandos para verificar client secret
- Avisos de segurança para produção

### 11. `docs/KEYCLOAK-BACKSTAGE-AUTH.md` ✨ NOVO
- Configuração completa de autenticação Keycloak + Backstage
- Troubleshooting detalhado
- Comandos de validação e correção

### 12. `docs/AUTOMACAO-DEPLOY.md` ✨ NOVO
- Resumo completo de todas as automações
- Processo de deploy passo a passo
- Checklist de validação pós-deploy
- Problemas resolvidos e automatizados

### 13. `ARQUIVOS-MODIFICADOS.md` ✨ NOVO (este arquivo)
- Lista completa de todos os arquivos modificados

---

## 🎯 Resumo por Categoria

### Terraform (1 arquivo)
- ✨ `cluster/terraform/secrets.tf`

### Scripts (1 arquivo)
- ✏️ `scripts/install.sh`

### Keycloak (4 arquivos)
- ✏️ `packages/keycloak/keycloak-bootstrap-job.yaml`
- ✏️ `packages/keycloak/codecentric-values.yaml`
- ✏️ `packages/keycloak/keycloak-ingress.yaml`
- ✏️ `packages/keycloak/values.yaml`

### Backstage (2 arquivos)
- ✏️ `packages/backstage/values.yaml`
- ✏️ `packages/backstage/backstage-ingress.yaml`

### External Secrets (1 arquivo)
- ✏️ `packages/external-secrets/values.yaml`

### Documentação (4 arquivos)
- ✨ `docs/CREDENCIAIS.md`
- ✨ `docs/KEYCLOAK-BACKSTAGE-AUTH.md`
- ✨ `docs/AUTOMACAO-DEPLOY.md`
- ✨ `ARQUIVOS-MODIFICADOS.md`

---

## ✅ Total: 13 arquivos

- **4 novos**
- **9 modificados**

---

## 🚀 Próximo Deploy será 100% Automático

```bash
# 1. Terraform
cd cluster/terraform
export AWS_PROFILE=darede
terraform apply -auto-approve

# 2. Install
cd ../..
export AWS_PROFILE=darede
export AUTO_CONFIRM=yes
./scripts/install.sh

# 3. Aguardar ~15-20 minutos

# 4. Testar login
# URL: https://backstage.timedevops.click
# User: admin
# Pass: admin
```

**✨ Nenhuma intervenção manual necessária! ✨**

---

**Legenda:**
- ✨ NOVO - Arquivo criado
- ✏️ MODIFICADO - Arquivo existente atualizado
