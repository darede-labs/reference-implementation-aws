# Guia Passo a Passo: Como Usar o Backstage para Criar Recursos AWS

**Para iniciantes - Explicando TUDO do zero!**

---

## 🎯 Entendendo o Workflow (Como funciona)

```
┌─────────────┐
│ Você        │
│ (Backstage) │
└──────┬──────┘
       │ 1. Preenche formulário
       │    "Quero criar um S3 bucket"
       ▼
┌──────────────────┐
│ Backstage cria   │
│ Pull Request     │
│ no GitHub        │
└──────┬───────────┘
       │ 2. PR com arquivo YAML
       │    do recurso
       ▼
┌──────────────────┐
│ Você aprova e    │
│ faz MERGE do PR  │
└──────┬───────────┘
       │ 3. Arquivo vai para branch main
       ▼
┌──────────────────┐
│ ArgoCD detecta   │
│ mudança no repo  │
└──────┬───────────┘
       │ 4. Aplica no cluster
       ▼
┌──────────────────┐
│ Crossplane lê    │
│ o YAML           │
└──────┬───────────┘
       │ 5. Cria recurso na AWS
       ▼
┌──────────────────┐
│ ✅ Bucket S3     │
│    criado!       │
└──────────────────┘
```

---

## 📁 Estrutura de Repositórios

Você vai precisar de **2 repositórios** no GitHub:

### 1. **reference-implementation-aws** (ESTE repo)
- **O que é:** Configuração da plataforma (Backstage, Crossplane, ArgoCD)
- **Onde está:** `https://github.com/darede-labs/reference-implementation-aws`
- **Você mexe aqui:** Só quando quiser adicionar novos templates

### 2. **infrastructure** (NOVO repo - você vai criar)
- **O que é:** Onde os recursos AWS ficam salvos (S3, RDS, EKS, etc.)
- **Onde criar:** Configurável em `config.yaml` (default: `https://github.com/darede-labs/infrastructure`)
- **Você mexe aqui:** Via Pull Requests do Backstage (automático)

---

## ⚙️ Configurar Repositórios (config.yaml)

**ANTES de criar os repositórios**, edite `config.yaml`:

```yaml
# config.yaml (linhas 90-103)

# GitHub organization/user onde repositórios serão criados
github_org: "darede-labs"  # ← Mude para sua org

# Repositório para recursos de infraestrutura
infrastructure_repo: "infrastructure"  # ← Mude se quiser outro nome

# Repositório para templates do Backstage
templates_repo: "backstage-templates"  # ← Mude se quiser outro nome
```

**Depois salve e use esses valores nos próximos passos.**

---

## 🚀 Passo a Passo Completo

### **PASSO 1: Criar Repositório de Infraestrutura**

#### 1.1 Criar repo no GitHub

```bash
# Via GitHub CLI (se tiver instalado)
gh repo create darede-labs/infrastructure --public --description "Infrastructure as Code via Crossplane"

# OU via web: https://github.com/new
```

#### 1.2 Criar repositório de infraestrutura

```bash
# Criar no GitHub usando valores do config.yaml
gh repo create $GITHUB_ORG/$INFRA_REPO --public --description "Infrastructure as Code via Crossplane"

# Clone e crie estrutura
cd ~/
git clone https://github.com/$GITHUB_ORG/$INFRA_REPO.git
cd $INFRA_REPO

mkdir -p s3-buckets rds-databases dynamodb-tables eks-clusters vpc-networks
cat > README.md <<'EOF'
# Infrastructure

Recursos AWS provisionados via Crossplane e gerenciados pelo Backstage.

## Estrutura

- `s3-buckets/` - Buckets S3
- `rds-databases/` - Bancos de dados RDS
- `dynamodb-tables/` - Tabelas DynamoDB
- `eks-clusters/` - Clusters EKS
- `vpc-networks/` - VPCs e Redes

## Como Criar Recursos

Não edite diretamente! Use o Backstage:

1. Acesse https://backstage.timedevops.click
2. Clique em **Create**
3. Selecione o template do recurso desejado
4. Preencha o formulário
5. Aguarde PR ser criado
6. Aprove e faça merge
7. Recurso será criado automaticamente na AWS

EOF

# Criar .gitignore
cat > .gitignore <<'EOF'
.DS_Store
*.swp
*.swo
*~
EOF

# Commit e push
git add .
git commit -m "Initial structure"
git push origin main
```

---

### **PASSO 2: Configurar ArgoCD para Monitorar o Repo**

#### 2.1 Criar Application do ArgoCD

```bash
export AWS_PROFILE=darede

# Ler valores do config.yaml
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

# Criar Application no ArgoCD usando config.yaml
cat > /tmp/argocd-infra.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      selfHeal: true
EOF

kubectl apply -f /tmp/argocd-infra.yaml

echo "✅ ArgoCD configurado para monitorar: https://github.com/${GITHUB_ORG}/${INFRA_REPO}"
```

#### 2.2 Verificar Application criada

```bash
# Listar applications
kubectl get applications -n argocd

# Ver detalhes
kubectl describe application infrastructure -n argocd
```

---

### **PASSO 3: Criar e Registrar Templates no Backstage**

#### 3.1 Criar repositório de templates

```bash
# Criar repo para templates
cd ~/
mkdir backstage-templates
cd backstage-templates

git init
```

#### 3.2 Criar template S3 Bucket

```bash
# Criar estrutura
mkdir -p s3-bucket/skeleton

# Criar template.yaml
cat > s3-bucket/template.yaml <<'EOF'
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: aws-s3-bucket
  title: AWS S3 Bucket
  description: Cria um bucket S3 via Crossplane
  tags:
    - aws
    - s3
    - storage
    - recommended
spec:
  owner: team-platform
  type: resource

  parameters:
    - title: Configuração do Bucket S3
      required:
        - bucketName
        - region
      properties:
        bucketName:
          title: Nome do Bucket
          type: string
          description: Nome único (lowercase, sem underscores)
          pattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
          ui:autofocus: true

        region:
          title: AWS Region
          type: string
          enum:
            - us-east-1
            - us-west-2
            - sa-east-1
          default: us-east-1

  steps:
    - id: fetch
      name: Fetch Template
      action: fetch:template
      input:
        url: ./skeleton
        values:
          bucketName: ${{ parameters.bucketName }}
          region: ${{ parameters.region }}

    - id: pr
      name: Create Pull Request
      action: publish:github:pull-request
      input:
        repoUrl: github.com?repo=infrastructure&owner=darede-labs
        branchName: add-s3-${{ parameters.bucketName }}
        title: 'Add S3 bucket: ${{ parameters.bucketName }}'
        description: |
          Bucket S3: ${{ parameters.bucketName }}
          Region: ${{ parameters.region }}

  output:
    links:
      - title: Pull Request
        url: ${{ steps.pr.output.remoteUrl }}
EOF

# Criar skeleton (arquivo que será criado)
cat > s3-bucket/skeleton/bucket.yaml <<'EOF'
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: ${{ values.bucketName }}
spec:
  forProvider:
    region: ${{ values.region }}
  providerConfigRef:
    name: aws-provider-config
EOF

git add .
git commit -m "Add S3 template from config.yaml"
git push

echo "✅ Template criado usando config.yaml!"
echo "   GitHub Org: $GITHUB_ORG"
echo "   Infra Repo: $INFRA_REPO"
```

#### 3.4 Registrar template no Backstage

**Via UI (Recomendado):**

1. Acesse https://backstage.timedevops.click
2. Login: `admin` / `admin`
3. Clique em **Create** (menu lateral)
4. Clique em **Register Existing Component**
5. Cole a URL:
   ```
   https://github.com/darede-labs/backstage-templates/blob/main/s3-bucket/template.yaml
   ```
6. Clique **Analyze**
7. Clique **Import**

**Via kubectl (Avançado):**

```bash
cat > /tmp/backstage-location.yaml <<'EOF'
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: s3-bucket-template
spec:
  type: url
  target: https://github.com/darede-labs/backstage-templates/blob/main/s3-bucket/template.yaml
EOF

kubectl apply -f /tmp/backstage-location.yaml -n backstage
```

---

### **PASSO 4: Configurar GitHub Token no Backstage**

O Backstage precisa de acesso ao GitHub para criar PRs.

#### 4.1 Criar Personal Access Token

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. **Generate new token (classic)**
3. Nome: `backstage-integration`
4. Scopes:
   - ✅ `repo` (full control)
   - ✅ `workflow`
   - ✅ `read:org`
   - ✅ `read:user`
5. **Generate token**
6. **COPIE O TOKEN** (ex: `ghp_abc123...`)

#### 4.2 Adicionar token ao Backstage

```bash
export AWS_PROFILE=darede

# Substitua pelo seu token real
GITHUB_TOKEN="ghp_seu_token_aqui"

kubectl patch secret backstage-env-vars -n backstage \
  -p "{\"data\":{\"GITHUB_TOKEN\":\"$(echo -n $GITHUB_TOKEN | base64)\"}}"

# Reiniciar Backstage para carregar novo token
kubectl rollout restart deployment/backstage -n backstage

# Aguardar pod ficar pronto
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=120s
```

---

### **PASSO 5: USAR O BACKSTAGE! 🎉**

Agora está tudo pronto. Vamos criar um bucket S3:

#### 5.1 Acessar Backstage

```
URL: https://backstage.timedevops.click
User: admin
Pass: admin
```

#### 5.2 Criar recurso via template

1. **Clicar em "Create"** (menu lateral esquerdo)
2. **Ver lista de templates** (deve aparecer "AWS S3 Bucket")
3. **Clicar no template "AWS S3 Bucket"**
4. **Preencher formulário:**
   - Nome do Bucket: `meu-teste-bucket-123`
   - Region: `us-east-1`
5. **Clicar "Review"**
6. **Clicar "Create"**

#### 5.3 Aguardar PR ser criado

O Backstage vai:
1. ✅ Criar arquivo `bucket.yaml`
2. ✅ Criar branch `add-s3-meu-teste-bucket-123`
3. ✅ Criar Pull Request no repo `infrastructure`
4. ✅ Mostrar link do PR

#### 5.4 Aprovar e fazer merge do PR

1. **Clicar no link do PR** que apareceu no Backstage
2. **Revisar as mudanças**
3. **Clicar "Merge pull request"**
4. **Clicar "Confirm merge"**

#### 5.5 Aguardar Crossplane criar o bucket

```bash
export AWS_PROFILE=darede

# Ver recurso sendo criado (pode levar 1-2 minutos)
kubectl get buckets -n crossplane-system

# Ver detalhes
kubectl describe bucket meu-teste-bucket-123 -n crossplane-system

# Verificar na AWS
aws s3 ls --profile darede | grep meu-teste-bucket-123
```

---

## 📍 Onde Cada Coisa Está Configurada

### Backstage

| O que | Onde está |
|-------|-----------|
| **Helm values** | `packages/backstage/values.yaml` |
| **Ingress** | `packages/backstage/backstage-ingress.yaml` |
| **Secrets** | `backstage-env-vars` (Kubernetes secret) |
| **GitHub token** | `backstage-env-vars` secret, chave `GITHUB_TOKEN` |
| **Client secret Keycloak** | `backstage-env-vars` secret, chave `BACKSTAGE_CLIENT_SECRET` |

### Crossplane

| O que | Onde está |
|-------|-----------|
| **Helm values** | `packages/crossplane/values.yaml` |
| **Providers AWS** | `packages/crossplane-aws-upbound/values.yaml` |
| **Compositions** | `packages/crossplane-compositions/` |
| **ProviderConfig** | Criado automaticamente com IRSA |

### Templates

| O que | Onde está |
|-------|-----------|
| **Templates do Backstage** | Repo `backstage-templates/` (você criou) |
| **Recursos provisionados** | Repo `infrastructure/` (você criou) |

### ArgoCD

| O que | Onde está |
|-------|-----------|
| **Applications** | `kubectl get applications -n argocd` |
| **Application infrastructure** | `/tmp/argocd-infrastructure-app.yaml` (você criou no passo 2) |

---

## 🔍 Comandos Úteis para Monitorar

### Ver recursos Crossplane

```bash
export AWS_PROFILE=darede

# Listar todos os managed resources
kubectl get managed -n crossplane-system

# Ver buckets S3
kubectl get buckets -n crossplane-system

# Ver clusters RDS
kubectl get instances.rds.aws.upbound.io -n crossplane-system

# Ver clusters EKS
kubectl get clusters.eks.aws.upbound.io -n crossplane-system
```

### Ver logs Crossplane

```bash
# Logs do Crossplane
kubectl logs -n crossplane-system -l app=crossplane --tail=50

# Logs de um provider específico
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

### Ver Applications ArgoCD

```bash
# Listar
kubectl get applications -n argocd

# Ver status
kubectl get application infrastructure -n argocd -o yaml

# Ver eventos
kubectl describe application infrastructure -n argocd
```

---

## 🐛 Troubleshooting Comum

### Template não aparece no Backstage

**Problema:** Registrou o template mas não aparece em "Create"

**Solução:**
```bash
# Verificar se Location foi criada
kubectl get locations -n backstage

# Ver logs do Backstage
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=100 | grep -i catalog

# Forçar refresh do catalog
kubectl rollout restart deployment/backstage -n backstage
```

### PR não é criado

**Problema:** Clica em "Create" mas PR não aparece

**Solução:**
```bash
# Verificar se GitHub token está configurado
kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d
echo # (deve mostrar seu token)

# Verificar logs
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=50 | grep -i github
```

### Recurso não é criado na AWS

**Problema:** PR foi merged mas recurso não aparece na AWS

**Solução:**
```bash
# 1. Verificar se ArgoCD aplicou
kubectl get application infrastructure -n argocd

# 2. Ver se manifest foi aplicado
kubectl get buckets -n crossplane-system

# 3. Ver detalhes do recurso
kubectl describe bucket nome-do-bucket -n crossplane-system

# 4. Ver eventos
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | tail -20

# 5. Ver logs do provider
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=100
```

---

## ✅ Checklist de Validação

Após seguir todos os passos, verificar:

- [ ] Repositório `infrastructure` criado no GitHub
- [ ] ArgoCD Application `infrastructure` criada
- [ ] Repositório `backstage-templates` criado no GitHub
- [ ] Template S3 registrado no Backstage
- [ ] GitHub token configurado no Backstage
- [ ] Template aparece em "Create" no Backstage
- [ ] Consegue criar bucket S3 via Backstage
- [ ] PR é criado automaticamente
- [ ] Após merge, ArgoCD aplica manifest
- [ ] Crossplane cria bucket na AWS
- [ ] Bucket aparece no `aws s3 ls`

---

## 📚 Próximos Passos

1. **Criar mais templates:**
   - RDS PostgreSQL
   - DynamoDB Table
   - EKS Cluster
   - VPC completa

2. **Configurar aprovações:**
   - Adicionar CODEOWNERS no repo infrastructure
   - Requerer aprovação para PRs

3. **Integrar com Catalog:**
   - Adicionar `catalog-info.yaml` nos recursos
   - Ver recursos no Catalog do Backstage

4. **Monitoramento:**
   - Ver status dos recursos no Backstage
   - Alertas quando criação falha

---

## 📖 Documentos Relacionados

- **Guia Completo AWS:** `docs/BACKSTAGE-PLATAFORMA-AWS.md`
- **Templates:** `docs/BACKSTAGE-USO-TEMPLATES.md`
- **Crossplane:** `docs/CROSSPLANE-JA-INSTALADO.md`
- **Credenciais:** `docs/CREDENCIAIS.md`

---

**Última atualização:** 11 de Dezembro de 2025

**Dúvidas?** Revise os passos ou veja os comandos de troubleshooting acima.
