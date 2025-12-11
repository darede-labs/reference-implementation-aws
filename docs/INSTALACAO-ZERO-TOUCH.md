# Instalação Zero-Touch - Tudo Automatizado

Documentação de TODAS as automações implementadas no `install.sh`.

---

## ✅ O Que É Criado Automaticamente

### 1. **GitHub Token & Repositórios** ✓

**Configuração:** `config.yaml`
```yaml
github_org: "darede-labs"
github_token: "ghp_..."
infrastructure_repo: "infrastructureidp"
templates_repo: "backstage-templates"
```

**Automação:**
- ✅ Secret `backstage-env-vars` com `GITHUB_TOKEN`
- ✅ Secret `repo-infrastructureidp-credentials` no ArgoCD (formato OAuth correto)
- ✅ Backstage acessa repos privados automaticamente
- ✅ ArgoCD acessa repos privados automaticamente

---

### 2. **Domínios & Subdomínios Dinâmicos** ✓

**Configuração:** `config.yaml`
```yaml
domain: "timedevops.click"
subdomains:
  argocd: "argocd"
  backstage: "backstage"
  keycloak: "keycloak"
```

**Automação:**
- ✅ ConfigMap `domain-config` criado no namespace `keycloak`
- ✅ Keycloak bootstrap lê ConfigMap e constrói URLs dinâmicas
- ✅ Clients Backstage e ArgoCD criados com redirect URIs corretas
- ✅ TUDO baseado no config.yaml - sem hardcode

---

### 3. **Keycloak SSO Completo** ✓

**Automação:**
- ✅ Realm `cnoe` criado
- ✅ Client `backstage` criado com scopes: openid, profile, email, groups
- ✅ Client `argocd` criado com scopes: openid, profile, email, groups
- ✅ Grupo `superuser` criado
- ✅ Usuário `admin` adicionado ao grupo `superuser`
- ✅ Client secrets fixos: `backstage-secret-2024`, `argocd-secret-2024`
- ✅ RBAC ArgoCD: grupo `superuser` → `role:admin`

**Login funcionando:**
- Backstage: https://backstage.timedevops.click → admin/admin via Keycloak
- ArgoCD: https://argocd.timedevops.click → admin/admin via Keycloak OU admin/[secret] local

---

### 4. **Crossplane Providers & Compositions** ✓

**Providers instalados automaticamente:**
```yaml
- dynamodb
- s3
- ec2
- vpc
- iam
- eks
- rds
- lambda
```

**Compositions criadas automaticamente:**
- ✅ S3 Bucket (XRD + Composition)
  - Bucket
  - BucketVersioning
  - BucketServerSideEncryptionConfiguration
  - BucketPublicAccessBlock

**Path:** `packages/crossplane-compositions/`

---

### 5. **ArgoCD Application "infrastructure"** ✓

**Criada automaticamente pelo install.sh:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/{GITHUB_ORG}/{INFRA_REPO}
    path: s3-buckets
    directory:
      exclude: 'catalog-info.yaml'
  destination:
    namespace: crossplane-system
  syncPolicy:
    automated:
      selfHeal: true
```

**Monitora:**
- Pasta `s3-buckets/` no repo privado
- Ignora arquivos `catalog-info.yaml` (Backstage metadata)
- Sync automático a cada mudança no repo
- Self-heal ativado

---

## 🚀 Fluxo Automático Completo

### Instalação (Uma Vez)

```bash
# 1. Configurar config.yaml
vim config.yaml  # Adicionar github_token, domínios, etc

# 2. Executar install.sh
export AWS_PROFILE=darede
./scripts/install.sh
```

**O que acontece automaticamente:**
1. ✅ Cluster EKS criado
2. ✅ ArgoCD instalado
3. ✅ Keycloak instalado e configurado (clients + SSO)
4. ✅ Backstage instalado com GitHub token
5. ✅ Crossplane instalado com providers AWS
6. ✅ Compositions S3 aplicadas
7. ✅ Secret ArgoCD para repo privado criado
8. ✅ Application "infrastructure" criada
9. ✅ ConfigMap domain-config criado
10. ✅ Ingresses com TLS configurados

**Tempo total:** ~15-20 minutos

---

### Uso (Pós-Instalação)

#### **1. Criar Bucket S3 via Backstage**

1. Acesse: https://backstage.timedevops.click
2. Login: `admin` / `admin`
3. Create → S3 Bucket Template
4. Preencha: nome, região, owner
5. **Submit**

**O que acontece automaticamente:**
1. ✅ Backstage cria PR no repo `infrastructureidp`
2. ✅ PR adiciona `s3-buckets/bucket.yaml` e `catalog-info.yaml`
3. ✅ Você faz merge do PR no GitHub
4. ✅ ArgoCD detecta mudança (< 3 min)
5. ✅ ArgoCD aplica `s3-buckets/bucket.yaml` no cluster
6. ✅ Crossplane cria bucket na AWS (< 1 min)
7. ✅ Status visível no ArgoCD UI

**Tempo total:** ~3-5 minutos (após merge)

---

#### **2. Monitorar Recursos**

**ArgoCD UI:**
- https://argocd.timedevops.click
- Application "infrastructure" → Tree View
- Ver S3Bucket + recursos filhos
- Status: Synced/OutOfSync, Healthy/Degraded

**CLI:**
```bash
# Ver buckets provisionados
kubectl get s3bucket -n crossplane-system

# Ver recursos AWS individuais
kubectl get bucket,bucketversioning -A

# Ver status completo
kubectl describe s3bucket <nome> -n crossplane-system
```

**AWS Console:**
- S3 Console: ver bucket criado
- Tags: owner, created-via: backstage, managed-by: crossplane

---

## 🔧 Validação Pós-Instalação

### Checklist Automático

```bash
export AWS_PROFILE=darede

echo "1. ArgoCD rodando:"
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

echo "2. Keycloak rodando:"
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak

echo "3. Backstage rodando:"
kubectl get pods -n backstage -l app.kubernetes.io/name=backstage

echo "4. Crossplane rodando:"
kubectl get pods -n crossplane-system -l app=crossplane

echo "5. GitHub token no Backstage:"
kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d | head -c 20 && echo "..."

echo "6. ArgoCD repo credential:"
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository

echo "7. Application infrastructure:"
kubectl get application infrastructure -n argocd

echo "8. Compositions S3:"
kubectl get xrd xs3buckets.darede.io
kubectl get composition xs3bucket.darede.io

echo "9. ConfigMap domain-config:"
kubectl get configmap domain-config -n keycloak
```

---

## 📊 Resumo: O Que NÃO Precisa Mais de Intervenção Manual

| Item | Antes | Agora |
|------|-------|-------|
| GitHub Token | Criar secret manualmente | ✅ Lido do config.yaml automaticamente |
| ArgoCD repo credential | Criar secret manualmente | ✅ Criado com formato OAuth correto |
| Keycloak clients | Criar via UI | ✅ Bootstrap job cria automaticamente |
| Keycloak redirect URIs | Hardcoded | ✅ Dinâmico via ConfigMap |
| ArgoCD OIDC | Configurar manualmente | ✅ Configurado via install.sh |
| Crossplane Compositions | Aplicar manualmente | ✅ Aplicadas no install.sh |
| Application infrastructure | Criar manualmente | ✅ Criada automaticamente |
| Backstage SSO | Configurar manualmente | ✅ Automático via secret |
| ArgoCD SSO | Sem SSO | ✅ Keycloak SSO funcionando |

---

## 🎯 Garantias

**Após executar `./scripts/install.sh`, você tem:**

1. ✅ **Backstage** acessando repos privados GitHub
2. ✅ **ArgoCD** acessando repos privados GitHub
3. ✅ **Keycloak SSO** funcionando para Backstage e ArgoCD
4. ✅ **Crossplane** pronto para provisionar S3, EKS, RDS, etc
5. ✅ **Application infrastructure** monitorando repo automaticamente
6. ✅ **Templates Backstage** prontos para criar recursos
7. ✅ **Fluxo completo** Backstage → GitHub → ArgoCD → Crossplane → AWS

**ZERO configuração manual necessária!**

---

## 📝 Arquivo de Configuração Único

**Tudo controlado por:** `config.yaml`

```yaml
# Cluster
cluster_name: darede-idp
region: us-east-1

# GitHub Integration
github_org: darede-labs
github_token: ghp_...
infrastructure_repo: infrastructureidp
templates_repo: backstage-templates

# Domínios
domain: timedevops.click
subdomains:
  argocd: argocd
  backstage: backstage
  keycloak: keycloak
```

**Mude qualquer valor → reinstale → tudo se adapta automaticamente.**

---

## 🚨 Troubleshooting

Se algo não funcionar após instalação:

```bash
# Ver logs do Keycloak bootstrap
kubectl logs -n keycloak job/keycloak-bootstrap --tail=100

# Ver status da Application
kubectl get application infrastructure -n argocd -o yaml

# Forçar refresh (se necessário)
kubectl patch application infrastructure -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Reiniciar Backstage (se token não funcionou)
kubectl rollout restart deployment/backstage -n backstage

# Reiniciar ArgoCD repo-server (se credential não funcionou)
kubectl rollout restart deployment/argocd-repo-server -n argocd
```

---

**Última atualização:** 11 de Dezembro de 2025
