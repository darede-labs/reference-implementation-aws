# Respostas da Auditoria - 2026-01-05

## ✅ Questão 1: Password Padrão ao Criar Usuário

**CORRIGIDO:** Template `user-management` agora inclui:

```yaml
temporaryPassword:
  title: "Temporary Password"
  type: string
  description: "Temporary password (min 8 chars, uppercase, lowercase, number, special char). User will be forced to change on first login."
  ui:widget: password
```

**Output do template agora mostra:**
```bash
aws cognito-idp admin-create-user \
  --user-pool-id ${COGNITO_USER_POOL_ID} \
  --username <email> \
  --user-attributes Name=email,Value=<email> Name=email_verified,Value=true \
  --temporary-password "<your-temp-password>" \
  --message-action SUPPRESS \
  --profile darede
```

**Comportamento Cognito:**
- Usuário criado com senha temporária
- Primeiro login força troca de senha
- ✅ Requisitos de senha validados

---

## ✅ Questão 2: Todas Edições Via Arquivo?

**SIM.** Todas mudanças commitadas no Git:

**Commits recentes:**
1. `ad3e5eb` - feat: add temporary password field to user-management
2. `322f155` - cleanup: remove obsolete keycloak and scripts
3. `950e95a` - feat: add sync-config script
4. `952c367` - fix: simplify catalog locations
5. `66e4548` - fix: update catalog-info
6. `a2ea6de` - fix: update terraform-unlock
7. `5a2434c` - feat: add RBAC, user management, terraform unlock

**Verificação:**
```bash
git status
# On branch main
# nothing to commit, working tree clean
```

✅ **Não há mudanças manuais pendentes**

---

## ⚠️ Questão 3: Instalação Limpa Funciona?

**PROBLEMAS IDENTIFICADOS:**

### install.sh Ainda Referencia Keycloak
**Linhas problemáticas:**
- L12: `KEYCLOAK_REALM=...`
- L16: `for ns in argocd keycloak backstage...` ← cria namespace keycloak
- L60-66: Configura OIDC com Keycloak
- L266-275: Cria secrets Keycloak
- L277-298: Cria ConfigMap domain-config com KEYCLOAK_SUBDOMAIN
- L347-434: Configura ArgoCD OIDC com Keycloak
- L382-433: Executa keycloak bootstrap job
- L512-539: Cria Keycloak Ingress

**AÇÃO NECESSÁRIA:**
❌ install.sh precisa ser completamente reescrito para usar Cognito
❌ Todas referências Keycloak devem ser removidas
❌ OIDC deve apontar para Cognito User Pool

### config.yaml Contém Seções Obsoletas
```yaml
# OBSOLETO - Sistema usa Cognito
keycloak:
  realm: "cnoe"
  clients:
    argocd: ...
    backstage: ...

secrets:
  keycloak:  # ← OBSOLETO
    admin_user: "admin"
    admin_password: "admin"

subdomains:
  keycloak: "keycloak"  # ← OBSOLETO
```

**STATUS:** ❌ Instalação limpa NÃO funcionará até limpar install.sh

---

## ⚠️ Questão 4: Valores Hardcoded

### Hardcoded ACEITÁVEIS (defaults com override)
```yaml
# Templates Backstage
TERRAFORM_BACKEND_BUCKET: default('poc-idp-tfstate')  # ✅ OK - env var override
TERRAFORM_BACKEND_REGION: default('us-east-1')        # ✅ OK - env var override
owner_email: default('admin@darede.com.br')           # ✅ OK - user context override
```

### Hardcoded PROBLEMÁTICOS
```yaml
# URLs específicas do domínio
templates/backstage/user-management/template.yaml:116
  ❌ "https://backstage.timedevops.click"

templates/backstage/resource-manager/template.yaml:23
  ❌ "https://backstage.timedevops.click/api/resources/resources?owner=admin"

templates/backstage/terraform-s3/template.yaml:93
  ❌ "https://backstage.timedevops.click/catalog/..."

templates/backstage/terraform-unlock/template.yaml:99
  ❌ "https://console.aws.amazon.com/s3/buckets/poc-idp-tfstate"
```

**SOLUÇÃO:**
1. Adicionar `backstage_url` ao config.yaml
2. Injetar via env var `BACKSTAGE_FRONTEND_URL`
3. Usar `${{ env.BACKSTAGE_FRONTEND_URL }}` nos templates

**STATUS:** ⚠️ URLs hardcoded impedem multi-ambiente

---

## ❌ Questão 5: config.yaml Controla Tudo?

**PARCIALMENTE.**

### O Que Funciona ✅
- `domain_name` → usado em install.sh
- `github_token` → injetado via secrets
- `github_org` → usado em templates
- `acm_certificate_arn` → usado em NLB
- `terraform_backend_bucket` → env var Backstage
- `cognito.user_pool_id` → env var Backstage
- `cognito.user_pool_client_id` → env var Backstage

### O Que NÃO Funciona ❌
- URLs hardcoded nos templates (não leem config.yaml)
- install.sh ainda usa seções obsoletas (keycloak)
- Algumas referências hardcoded ao domínio específico

**STATUS:** ⚠️ Precisa parametrização adicional

---

## ✅ Questão 6: Limpeza de Diretórios

### Removido
- ✅ `packages/keycloak/` - 9 arquivos, 14 KB
- ✅ `scripts/install-v2.sh`
- ✅ `scripts/install-auto.sh`
- ✅ `scripts/test-oidc.sh`

### A Verificar
- `packages/external-dns/` - ⚠️ Pode ser usado pelo NLB/Route53
- `packages/addons/` - ⚠️ Verificar conteúdo
- `packages/appset-chart/` - ⚠️ Verificar uso
- `packages/crossplane-compositions/` - ⚠️ Verificar uso
- `catalog/` - ⚠️ Vazio?
- `deploy/` - ⚠️ Verificar uso
- `examples/` - ⚠️ Pode manter como referência
- `platform/` - ⚠️ Verificar uso
- `private/` - ⚠️ Verificar conteúdo

---

## 📋 Ações Pendentes

### CRÍTICAS (Bloqueiam instalação limpa)
1. [ ] Limpar install.sh de todas referências Keycloak
2. [ ] Adicionar configuração Cognito OIDC no install.sh
3. [ ] Remover seções keycloak de config.yaml
4. [ ] Testar install.sh em cluster limpo

### IMPORTANTES (Melhoram portabilidade)
5. [ ] Parametrizar URLs hardcoded
6. [ ] Adicionar backstage_url ao config.yaml
7. [ ] Atualizar templates para usar env vars

### OPCIONAIS (Limpeza adicional)
8. [ ] Verificar e remover diretórios não usados
9. [ ] Atualizar READMEs obsoletos
10. [ ] Documentar processo de instalação atualizado

---

## 🎯 Resumo Executivo

| Questão | Status | Bloqueante? |
|---------|--------|-------------|
| 1. Password padrão | ✅ Corrigido | Não |
| 2. Edições via arquivo | ✅ Sim | Não |
| 3. Instalação limpa | ❌ Não funciona | **SIM** |
| 4. Valores hardcoded | ⚠️ Alguns problemáticos | Não |
| 5. config.yaml controla | ⚠️ Parcialmente | Não |
| 6. Limpeza diretórios | ⚠️ Parcial | Não |

**BLOQUEIO PRINCIPAL:** install.sh ainda tenta instalar/configurar Keycloak (obsoleto)

**RECOMENDAÇÃO:** Limpar install.sh completamente antes de próxima instalação.

---

Data: 2026-01-05 21:15 UTC-3
Autor: Cascade AI
Status: Auditoria completa - Ações pendentes identificadas
