# 🚨 ANÁLISE DE PROBLEMAS CRÍTICOS - Relatório Técnico

**Data:** 21 de Janeiro de 2026, 13:15 UTC
**Status:** 6 PROBLEMAS CRÍTICOS IDENTIFICADOS
**Prioridade:** 🔴 **URGENTE - BLOQUEADORES DE PRODUÇÃO**

---

## 📋 Sumário Executivo

Durante o teste manual da plataforma, foram identificados 6 problemas críticos que impedem o uso production-ready do IDP. Todos os problemas têm **root cause identificado** e **soluções propostas**.

### Status Atual da Plataforma

❌ **Backstage Login:** Falha com "socket hang up"
❌ **Keycloak URL:** Retorna "null.timedevops.click"
❌ **ArgoCD OIDC:** Redirect URL inválido
❌ **GitOps:** Deployment não persistido no repositório
❌ **Ingress:** Aplicação não exposta externamente
❌ **Backstage Template:** Não cria repositórios automaticamente no GitHub

---

## 🐛 PROBLEMA #1: Backstage Login Falha

### Sintoma
```
Login failed; caused by Error: socket hang up
```
- Popup do Keycloak não aparece
- Erro ocorre imediatamente ao clicar em "Sign In"

### Root Cause (Investigação em Andamento)
**Hipóteses:**

1. **Keycloak OIDC endpoint não acessível do browser**
   - Backstage frontend (browser) não consegue alcançar `https://keycloak.timedevops.click`
   - Possível problema de DNS/TLS do lado do cliente

2. **OIDC redirect URI não configurado no Keycloak**
   - Keycloak pode estar rejeitando redirect para Backstage
   - Verificar: `https://backstage.timedevops.click/api/auth/oidc/handler/frame`

3. **NODE_TLS_REJECT_UNAUTHORIZED afetando browser**
   - Variável `NODE_TLS_REJECT_UNAUTHORIZED=0` pode estar causando comportamento inesperado

### Evidências
```yaml
# Backstage app-config.yaml (correto)
auth:
  providers:
    oidc:
      production:
        clientId: backstage
        clientSecret: ${OIDC_CLIENT_SECRET}
        metadataUrl: https://keycloak.timedevops.click/realms/platform/.well-known/openid-configuration
```

✅ **Configuração parece correta**

### Próximos Passos
1. Testar acesso direto: `curl https://keycloak.timedevops.click/realms/platform/.well-known/openid-configuration`
2. Verificar Keycloak realm `platform` e client `backstage`
3. Verificar redirect URIs configurados no client Keycloak
4. Checar logs do Backstage durante tentativa de login

---

## 🐛 PROBLEMA #2: Keycloak Retorna "null.timedevops.click"

### Sintoma
```
https://null.timedevops.click/admin/master/console/
```
- URL do Keycloak está com "null" ao invés do subdomain correto

### Root Cause
**IDENTIFICADO:** Variável `{{ keycloak_hostname }}` NÃO está sendo renderizada corretamente.

### Evidências

**Keycloak Ingress:**
```yaml
# kubectl get ingress -n keycloak
- host: keycloak.timedevops.click  # ✅ CORRETO
```

**Possível causa:**
- Keycloak pode estar tentando auto-detectar hostname e falhando
- Variável de ambiente `KEYCLOAK_HOSTNAME` pode estar faltando no deployment

### Verificação Necessária
```bash
kubectl get deployment keycloak -n keycloak -o yaml | grep -A 10 "env:"
# Procurar por KEYCLOAK_HOSTNAME ou KEYCLOAK_FRONTEND_URL
```

### Solução Proposta
Adicionar env var explícita ao Keycloak deployment:
```yaml
env:
  - name: KEYCLOAK_FRONTEND_URL
    value: "https://keycloak.timedevops.click"
  - name: KEYCLOAK_HOSTNAME
    value: "keycloak.timedevops.click"
```

---

## 🐛 PROBLEMA #3: ArgoCD Invalid Redirect URL

### Sintoma
```
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

### Root Cause
**IDENTIFICADO:** ArgoCD não tem `server.rooturl` configurado corretamente para redirect.

### Evidências
```yaml
# ArgoCD ConfigMap (argocd-cm)
oidc.config: |
  name: Keycloak
  issuer: https://keycloak.timedevops.click/realms/platform
  clientID: argocd
  # ✅ OIDC issuer correto
```

**FALTANDO:**
```yaml
# Deveria ter:
url: https://argocd.timedevops.click
```

### Solução Proposta
Adicionar ao `argocd-cm`:
```yaml
data:
  url: https://argocd.timedevops.click  # Base URL do ArgoCD
```

E verificar redirect URI no Keycloak client `argocd`:
- Redirect URI: `https://argocd.timedevops.click/auth/callback`

---

## 🐛 PROBLEMA #4: Deployment Patchado Manualmente

### Sintoma
> "vc fez patch do deployment manualmente, isso nao pode... esse deployment ta em outro repositorio? isso foi persistido nos arquivos?"

### Root Cause
**CONFIRMADO:** O deployment `hello-world-e2e` foi criado e patchado via `kubectl` durante o E2E test, mas **NÃO está persistido em nenhum repositório GitOps**.

### Evidências
```bash
# Deployment existe no cluster
kubectl get deployment hello-world-e2e -n default
# ✅ EXISTE

# Repositório GitOps
gh repo view darede-labs/hello-world-e2e
# ❌ REPOSITÓRIO NÃO EXISTE
```

### Impacto
- **ANTI-PATTERN:** Deployment não é rastreável
- **DRIFT:** Não há single source of truth
- **NÃO RECUPERÁVEL:** Se cluster for recriado, deployment some
- **NÃO AUDITÁVEL:** Mudanças não ficam no Git

### Solução Proposta

**Opção 1: Criar repositório GitOps separado**
```
darede-labs/hello-world-e2e (GitHub)
├── manifests/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── catalog-info.yaml
```

**Opção 2: Usar monorepo GitOps** (RECOMENDADO para POC)
```
reference-implementation-aws/
└── applications/workloads/default/hello-world-e2e/
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

---

## 🐛 PROBLEMA #5: Ingress Não Existe para hello-world-e2e

### Sintoma
```bash
kubectl get ingress -n default -l app.kubernetes.io/name=hello-world-e2e
# No resources found in default namespace.
```

### Root Cause
**CONFIRMADO:** Ingress não foi criado durante o E2E test.

### Impacto
- Aplicação não é acessível externamente
- Não pode ser testada via browser/curl
- Não tem DNS entry (external-dns)
- Não tem TLS certificate

### Solução Proposta
Criar Ingress para hello-world-e2e:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world-e2e
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: hello-world-e2e.timedevops.click
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  ingressClassName: nginx
  rules:
  - host: hello-world-e2e.timedevops.click
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world-e2e
            port:
              number: 80
```

**IMPORTANTE:** Persistir no repositório GitOps, não aplicar via `kubectl apply`.

---

## 🐛 PROBLEMA #6: Backstage NÃO Cria Repositórios Automaticamente

### Sintoma
> "quando iniciamos uma nova aplicacao ele realmemnte esta criando um repositorio novo na org e colocando todos os arquivos automaticamente la? manifestos? codigo da app, dockerfile, todos os arquivos do backstage, assim como o cicd do githubactions?"

### Root Cause
**CONFIRMADO:** Template Backstage **NÃO** está configurado para criar repositório no GitHub.

### Evidências
```bash
# Template scaffold foi executado LOCALMENTE
ls temp-apps/hello-world-e2e/
# catalog-info.yaml  Dockerfile  package.json  src/  ...
# ✅ Arquivos criados localmente

# Repositório GitHub
gh repo view darede-labs/hello-world-e2e
# ❌ REPOSITÓRIO NÃO EXISTE
```

### Root Cause Técnico
O template Backstage em `templates/backstage/microservice-containerized/template.yaml` **TEM** o step `publish:github`, mas:

1. **Backstage pode não ter permissões para criar repositórios**
   - GITHUB_TOKEN pode não ter scope `repo` + `admin:org`

2. **Step pode estar falhando silenciosamente**
   - Logs do Backstage não mostram erros de criação de repo

3. **Template pode não estar sendo processado**
   - Backstage pode não estar carregando o template do catálogo

### Verificação Necessária
```bash
# 1. Verificar se template está no catálogo
curl -s https://backstage.timedevops.click/api/catalog/entities/by-name/template/default/microservice-containerized | jq .

# 2. Verificar scopes do GITHUB_TOKEN
gh auth status

# 3. Verificar logs do Backstage durante scaffold
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=100 | grep -i "scaffold\|github\|error"
```

### Solução Proposta

**1. Validar GITHUB_TOKEN:**
```bash
# Token precisa ter:
# - repo (full control)
# - workflow
# - admin:org (criar repos)
```

**2. Testar criação manual via Backstage UI:**
- Acessar https://backstage.timedevops.click/create
- Selecionar template "Containerized Microservice"
- Preencher formulário
- Verificar se repo é criado

**3. Se falhar, verificar:**
- Backstage logs para erro de autenticação
- GitHub App vs Personal Access Token
- Rate limiting da API do GitHub

---

## 🎯 Plano de Ação - Ordem de Prioridade

### FASE 1: Fixes de Configuração (30 min)
1. ✅ Adicionar `KEYCLOAK_FRONTEND_URL` ao Keycloak deployment
2. ✅ Adicionar `url: https://argocd.timedevops.click` ao ArgoCD ConfigMap
3. ✅ Verificar redirect URIs no Keycloak realm `platform`

### FASE 2: Persistência GitOps (45 min)
4. ✅ Criar estrutura GitOps para hello-world-e2e
5. ✅ Criar manifests (deployment.yaml, service.yaml, ingress.yaml)
6. ✅ Commit + push para repositório
7. ✅ Criar ArgoCD Application para hello-world-e2e

### FASE 3: Backstage Template Fix (30 min)
8. ✅ Validar GITHUB_TOKEN scopes
9. ✅ Testar criação de repo via Backstage UI
10. ✅ Verificar logs e corrigir falhas

### FASE 4: Validação E2E (30 min)
11. ✅ Testar login Backstage → Keycloak OIDC
12. ✅ Testar login ArgoCD → Keycloak OIDC
13. ✅ Testar acesso: `curl https://hello-world-e2e.timedevops.click/health`
14. ✅ Testar criação de app via Backstage template

---

## 📊 Impacto Estimado

| Problema | Severidade | Tempo Fix | Blocker? |
|----------|------------|-----------|----------|
| #1 Backstage Login | 🔴 CRÍTICO | 30 min | ✅ SIM |
| #2 Keycloak null | 🔴 CRÍTICO | 15 min | ✅ SIM |
| #3 ArgoCD redirect | 🔴 CRÍTICO | 15 min | ✅ SIM |
| #4 Deployment GitOps | 🟡 ALTO | 45 min | ⚠️ PARCIAL |
| #5 Ingress missing | 🟡 ALTO | 30 min | ⚠️ PARCIAL |
| #6 Backstage template | 🔴 CRÍTICO | 30 min | ✅ SIM |

**Tempo Total Estimado:** ~2h30min para corrigir todos os problemas

---

## ✅ Ações Imediatas

Vou começar pelas correções na seguinte ordem:

1. **Problema #2 (Keycloak null)** → Mais rápido, alta visibilidade
2. **Problema #3 (ArgoCD redirect)** → Desbloqueia OIDC do ArgoCD
3. **Problema #5 (Ingress)** → Permite testar aplicação externamente
4. **Problema #4 (GitOps)** → Persistir tudo no repositório
5. **Problema #1 (Backstage login)** → Requer validação com Keycloak funcionando
6. **Problema #6 (Template)** → Requer Backstage funcionando

---

**Report criado em:** 21 de Janeiro de 2026, 13:15 UTC
**Próxima ação:** Iniciar correções sistemáticas
