# Análise de Diretórios - Reference Implementation AWS

## 📊 Status Geral

| Diretório | Status | Ação Recomendada |
|-----------|--------|------------------|
| catalog/ | ❌ VAZIO | **DELETAR** |
| cluster/ | ✅ CRÍTICO | **MANTER** |
| deploy/ | ⚠️ DUPLICADO | **REVISAR/DELETAR** |
| docs/ | ⚠️ OBSOLETO | **LIMPAR** |
| examples/ | ⚠️ VAZIO | **DELETAR** |
| packages/ | ✅ CRÍTICO | **MANTER** |
| platform/ | ⚠️ DUPLICADO | **REVISAR** |
| private/ | ⚠️ TEMPLATES | **DELETAR** |
| scripts/ | ✅ ESSENCIAL | **MANTER** |
| templates/ | ✅ CRÍTICO | **MANTER** |

---

## 📁 ANÁLISE DETALHADA

### 1. `catalog/` - ❌ DELETAR
```
catalog/
└── resources/ (VAZIO - 0 items)
```

**Propósito:** Deveria conter recursos do Backstage catalog
**Status:** Completamente vazio
**Uso:** Nenhum
**Decisão:** ❌ **DELETAR - 100% seguro**

**Motivo:**
- Diretório vazio sem conteúdo
- Backstage catalog usa `templates/backstage/catalog-info.yaml`
- Não referenciado em lugar nenhum

---

### 2. `cluster/` - ✅ MANTER (CRÍTICO)
```
cluster/
├── eksctl/ (3 items)
├── iam-policies/ (2 items)
└── terraform/ (17 items - cluster EKS, Cognito, IAM)
```

**Propósito:** Infraestrutura do cluster EKS
**Status:** ✅ ATIVO e ESSENCIAL
**Uso:** Criação e configuração do cluster

**Conteúdo Crítico:**
- `terraform/main.tf` - EKS cluster definition
- `terraform/cognito.tf` - AWS Cognito User Pool (autenticação)
- `terraform/atlantis.tf` - Atlantis configuration
- `terraform/locals.tf` - Variables
- `iam-policies/` - IAM policies para IRSA

**Decisão:** ✅ **MANTER - ESSENCIAL**

**Motivo:**
- Contém o Terraform que cria o EKS cluster
- Cognito User Pool configuration
- IAM roles e policies
- **Crítico para instalação limpa**

---

### 3. `deploy/` - ⚠️ REVISAR/DELETAR
```
deploy/
└── platform/ (7 items)
```

**Propósito:** Deployment alternativo da plataforma
**Status:** ⚠️ Potencialmente obsoleto/duplicado

**Verificar:**
- Parece duplicar conteúdo de `packages/`
- `install.sh` não usa este diretório
- Pode ser abordagem alternativa não usada

**Decisão:** ⚠️ **REVISAR conteúdo, provavelmente DELETAR**

**Ação:**
```bash
ls -la deploy/platform/
# Se não for usado por install.sh → DELETAR
```

---

### 4. `docs/` - ⚠️ LIMPAR (muito conteúdo obsoleto)
```
docs/
├── 35 arquivos .md
├── Muitos sobre Keycloak (OBSOLETO)
├── Guias desatualizados
└── images/ (VAZIO)
```

**Propósito:** Documentação do projeto
**Status:** ⚠️ Mistura de atual e obsoleto

**Obsoletos (Keycloak):**
- ❌ `ARGOCD-SSO-KEYCLOAK.md`
- ❌ `KEYCLOAK-BACKSTAGE-AUTH.md`
- ❌ Vários mencionam configurações antigas

**Úteis (manter):**
- ✅ `00-INDICE-DOCUMENTACAO.md`
- ✅ `CONFIG-YAML-COMPLETO.md`
- ✅ `GUIA-USO-PLATAFORMA.md`

**Decisão:** ⚠️ **LIMPAR SELETIVAMENTE**

**Ação:**
1. Deletar docs sobre Keycloak
2. Atualizar docs principais com Cognito
3. Remover `images/` (vazio)
4. Consolidar guias duplicados

---

### 5. `examples/` - ❌ DELETAR
```
examples/
├── app-with-aws-resources.md (32 bytes - quase vazio)
├── spark/ (1 item)
└── template-generation/ (1 item)
```

**Propósito:** Exemplos de uso
**Status:** ❌ Praticamente vazio

**Decisão:** ❌ **DELETAR - Seguro**

**Motivo:**
- Conteúdo mínimo/incompleto
- Não usado por install.sh
- Templates reais estão em `templates/`

---

### 6. `packages/` - ✅ MANTER (CRÍTICO)
```
packages/
├── addons/
├── appset-chart/
├── argo-cd/
├── argo-workflows/
├── backstage/ ⭐ CRÍTICO
├── bootstrap/
├── cert-manager/
├── crossplane/
├── crossplane-aws-upbound/
├── crossplane-compositions/
├── external-dns/
├── external-secrets/
└── ingress-nginx/
```

**Propósito:** Helm charts e configurações dos componentes da plataforma
**Status:** ✅ 100% ESSENCIAL

**Conteúdo Crítico:**
- `backstage/values.yaml` - Configuração Backstage
- `backstage/users-catalog.yaml` - Usuários
- `backstage/rbac-policy.yaml` - RBAC
- `argo-cd/` - ArgoCD configuration
- `crossplane-compositions/` - Infraestrutura como código

**Decisão:** ✅ **MANTER - ABSOLUTAMENTE CRÍTICO**

**Motivo:**
- Usado diretamente por `install.sh`
- Contém todas as configurações dos serviços
- **Deletar = sistema quebra completamente**

---

### 7. `platform/` - ⚠️ REVISAR
```
platform/
└── terraform/ (8 items)
```

**Propósito:** Terraform adicional para recursos da plataforma
**Status:** ⚠️ Pode duplicar `cluster/terraform/`

**Verificar:**
- Diferença com `cluster/terraform/`
- Se é usado por algum processo
- Pode ser infraestrutura de exemplo

**Decisão:** ⚠️ **REVISAR e provavelmente DELETAR**

**Ação:**
```bash
ls -la platform/terraform/
git log --oneline platform/terraform/ | head -10
# Se não usado → DELETAR
```

---

### 8. `private/` - ❌ DELETAR
```
private/
├── argocd-github.yaml.template (261 bytes)
└── backstage-github.yaml.template (182 bytes)
```

**Propósito:** Templates de secrets GitHub
**Status:** ❌ Obsoleto - `install.sh` cria secrets dinamicamente

**Decisão:** ❌ **DELETAR - Seguro**

**Motivo:**
- `install.sh` cria secrets via kubectl
- Lê do `config.yaml` diretamente
- Templates não são mais usados

---

### 9. `scripts/` - ✅ MANTER (ESSENCIAL)
```
scripts/
├── cleanup-crds.sh
├── create-cluster.sh
├── create-config-secrets.sh
├── e2e-all-templates.sh
├── e2e-full-test.sh
├── get-urls.sh
├── install-using-idpbuilder.sh
├── install.sh ⭐ CRÍTICO
├── list-my-resources.sh
├── manage-users.sh
├── template.sh
├── uninstall.sh
└── utils.sh
```

**Propósito:** Scripts de instalação, gerenciamento e testes
**Status:** ✅ ESSENCIAL

**Críticos:**
- `install.sh` - **Instalação principal**
- `utils.sh` - Funções compartilhadas
- `uninstall.sh` - Limpeza
- `create-cluster.sh` - Criação do cluster

**Úteis:**
- `get-urls.sh` - URLs dos serviços
- `list-my-resources.sh` - Lista recursos
- `manage-users.sh` - Gerenciar usuários

**Questionáveis:**
- `install-using-idpbuilder.sh` - Abordagem alternativa, pode deletar
- `e2e-*` - Scripts de teste, úteis mas não críticos

**Decisão:** ✅ **MANTER (remover apenas idpbuilder se não usado)**

---

### 10. `templates/` - ✅ MANTER (CRÍTICO)
```
templates/
├── argo-workflow/ (7 items)
└── backstage/ (65 items) ⭐ TEMPLATES PRINCIPAIS
```

**Propósito:** Backstage templates para criar recursos
**Status:** ✅ 100% CRÍTICO

**Conteúdo:**
- `backstage/catalog-info.yaml` - **Lista de todos templates**
- `backstage/terraform-*/` - Templates Terraform (S3, VPC, EC2, etc)
- `backstage/user-management/` - Gerenciar usuários
- `backstage/terraform-unlock/` - Unlock states
- `backstage/resource-manager/` - Deletar recursos

**Decisão:** ✅ **MANTER - ABSOLUTAMENTE CRÍTICO**

**Motivo:**
- Core do Backstage
- 17 templates ativos
- **Deletar = Backstage fica sem funcionalidade**

---

## 🗑️ PLANO DE LIMPEZA

### Fase 1: Deletar Seguros (Vazio/Obsoleto)
```bash
# 100% seguro
rm -rf catalog/
rm -rf examples/
rm -rf private/

# Revisar conteúdo primeiro
ls -la deploy/platform/
# Se não usado:
rm -rf deploy/
```

### Fase 2: Limpar docs/ (Seletivo)
```bash
cd docs/

# Deletar docs obsoletos Keycloak
rm -f ARGOCD-SSO-KEYCLOAK.md
rm -f KEYCLOAK-BACKSTAGE-AUTH.md

# Remover imagens vazias
rm -rf images/

# Consolidar/atualizar docs principais
# (manual - revisar cada um)
```

### Fase 3: Revisar platform/
```bash
# Verificar se usado
git log --oneline platform/ | head -20
ls -la platform/terraform/

# Se não crítico:
rm -rf platform/
```

### Fase 4: Scripts opcionais
```bash
cd scripts/
# Remover idpbuilder se não usado
rm -f install-using-idpbuilder.sh
```

---

## 📋 RESUMO EXECUTIVO

### ✅ MANTER (CRÍTICOS)
- **cluster/** - Terraform EKS, Cognito
- **packages/** - Helm charts, configs
- **scripts/** - install.sh e utils
- **templates/** - Backstage templates

### ❌ DELETAR (Seguros)
- **catalog/** - Vazio
- **examples/** - Quase vazio
- **private/** - Templates obsoletos

### ⚠️ REVISAR/LIMPAR
- **deploy/** - Provavelmente duplicado
- **docs/** - Limpar Keycloak, consolidar
- **platform/** - Verificar se usado

---

## 💾 ECONOMIA ESTIMADA

| Ação | Arquivos | Espaço |
|------|----------|--------|
| Deletar catalog/ | 0 | 0 KB |
| Deletar examples/ | ~5 | ~50 KB |
| Deletar private/ | 2 | ~1 KB |
| Limpar docs/ | ~10 | ~100 KB |
| Deletar deploy/ | ~7 | ~50 KB |
| Deletar platform/ | ~8 | ~50 KB |
| **TOTAL** | **~32** | **~250 KB** |

---

## ⚠️ ANTES DE DELETAR

### Checklist de Segurança
```bash
# 1. Verificar se install.sh não referencia
grep -r "catalog/" scripts/install.sh
grep -r "examples/" scripts/install.sh
grep -r "private/" scripts/install.sh
grep -r "deploy/" scripts/install.sh
grep -r "platform/" scripts/install.sh

# 2. Verificar se templates não referenciam
grep -r "catalog/" templates/
grep -r "examples/" templates/

# 3. Backup antes de deletar
git add -A
git commit -m "backup: antes de limpeza de diretórios"
git push origin main
```

---

Data: 2026-01-05 22:00 UTC-3
Status: Análise completa
Próximo: Executar limpeza fase 1 (seguros)
