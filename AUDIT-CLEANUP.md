# Auditoria e Limpeza do Repositório

## 1. Valores Hardcoded Encontrados

### Templates Backstage
**Padrão correto:** Todos usam `${{ env.TERRAFORM_BACKEND_BUCKET | default('poc-idp-tfstate') }}`
- ✅ Valor default adequado para fallback
- ✅ Sobrescrito via variável de ambiente do config.yaml

**URLs hardcoded:**
- `templates/backstage/user-management/template.yaml:116` → `https://backstage.timedevops.click`
- `templates/backstage/terraform-s3/template.yaml:93` → `https://backstage.timedevops.click/catalog/...`
- `templates/backstage/resource-manager/template.yaml:23` → `https://backstage.timedevops.click/api/resources/...`
- `templates/backstage/terraform-unlock/template.yaml:99` → `https://console.aws.amazon.com/s3/buckets/poc-idp-tfstate`

**Avaliação:** URLs são específicas do domínio e bucket. Devem ser parametrizadas via config.yaml.

### Emails Default
- `admin@darede.com.br` aparece em vários templates como fallback
- ✅ Aceitável como default, sobrescrito por user.entity.spec.profile.email

---

## 2. Componentes Obsoletos Identificados

### Keycloak (OBSOLETO - Sistema usa Cognito)
**Diretórios:**
- `packages/keycloak/` - 9 arquivos (14 KB)

**Referências em install.sh:**
- 76 referências ao Keycloak
- Criação de namespace keycloak
- Secrets keycloak
- ConfigMap domain-config
- Ingress keycloak
- Cliente OIDC keycloak
- Bootstrap job keycloak

**Referências em config.yaml:**
- Seção `keycloak:` com realm e clients
- Seção `secrets.keycloak` com senhas
- Subdomain keycloak

**Status:** Sistema atual usa AWS Cognito. Keycloak completamente obsoleto.

---

### External-DNS
**Diretório:** `packages/external-dns/`

**Status:** Verificar se está sendo usado. NLB pode estar usando external-dns para Route53.

---

### Scripts Obsoletos
**Candidatos para remoção:**
- `scripts/install-v2.sh` - versão alternativa?
- `scripts/install-auto.sh` - versão alternativa?
- `scripts/test-oidc.sh` - testa Keycloak OIDC

---

## 3. Validação config.yaml

### Parâmetros Controlados
✅ domain_name
✅ github_token
✅ github_org
✅ infrastructure_repo
✅ aws_region
✅ acm_certificate_arn
✅ terraform_backend_bucket
✅ cognito.user_pool_id
✅ cognito.user_pool_client_id
✅ subdomains.argocd
✅ subdomains.backstage

### Parâmetros Obsoletos em config.yaml
❌ keycloak.realm
❌ keycloak.clients
❌ secrets.keycloak
❌ subdomains.keycloak

---

## 4. Instalação Limpa

### Processo Esperado
1. Editar `config.yaml` com valores do ambiente
2. Executar `scripts/install.sh`
3. Sistema deve subir 100% funcional

### Problemas Atuais
❌ install.sh ainda tenta instalar Keycloak
❌ install.sh cria secrets Keycloak
❌ install.sh configura OIDC com Keycloak
❌ Referências hardcoded não parametrizadas

---

## 5. Ações Necessárias

### Remoção
- [ ] Remover `packages/keycloak/`
- [ ] Remover seção keycloak de `config.yaml`
- [ ] Remover referências Keycloak de `install.sh`
- [ ] Remover scripts obsoletos (install-v2.sh, install-auto.sh, test-oidc.sh)
- [ ] Verificar e remover external-dns se não usado

### Parametrização
- [ ] Parametrizar URLs hardcoded nos templates
- [ ] Adicionar BACKSTAGE_URL ao config.yaml
- [ ] Injetar via env vars no Backstage

### Validação
- [ ] Testar install.sh em cluster limpo
- [ ] Validar que apenas config.yaml precisa ser editado
- [ ] Documentar processo de instalação atualizado

---

## 6. Diretórios a Revisar
- `packages/addons/` - verificar uso
- `packages/appset-chart/` - verificar uso
- `packages/crossplane-compositions/` - verificar uso
- `catalog/` - verificar uso
- `deploy/` - verificar uso
- `examples/` - verificar uso
- `platform/` - verificar uso
- `private/` - verificar uso

---

Data: 2026-01-05
Status: Auditoria em andamento
