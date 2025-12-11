# Guia Completo do config.yaml

Todas as configurações centralizadas em um único arquivo.

---

## 📋 Seções do config.yaml

### 1. Repositório de Código (linhas 4-8)

```yaml
repo:
  url: "https://github.com/darede-labs/reference-implementation-aws"
  revision: "main"
  basepath: "packages"
```

**Uso:** ArgoCD usa para localizar os packages da plataforma.

---

### 2. Configuração do Cluster EKS (linhas 10-28)

```yaml
cluster_name: "idp-poc-cluster"
region: "us-east-1"
auto_mode: "false"
iam_auth_method: "irsa"
```

**Importante:**
- `cluster_name` - Nome do cluster EKS (usado no Terraform)
- `region` - Região AWS onde tudo será criado
- `auto_mode` - EKS Auto Mode vs Standard Mode
- `iam_auth_method` - IRSA (recomendado) ou Pod Identity

---

### 3. Configuração de Rede (linhas 30-54)

```yaml
vpc:
  mode: "create"  # ou "existing"
  cidr: "10.0.0.0/16"
  availability_zones: 3
  nat_gateway_mode: "single"  # ou "one_per_az"
```

---

### 4. Node Groups (linhas 56-88)

```yaml
node_groups:
  capacity_type: "SPOT"  # ou "ON_DEMAND"
  instance_types:
    - "t3.medium"
    - "t3a.medium"
    - "t2.medium"
  scaling:
    min_size: 3
    max_size: 6
    desired_size: 4
  disk_size: 50
  labels:
    pool: "spot"
```

---

### 5. 🔧 **Backstage Integration (linhas 90-108)** ⭐ NOVO

```yaml
################################################################################
# Backstage Integration Repositories
################################################################################

# GitHub organization/user onde repositórios serão criados
github_org: "darede-labs"

# GitHub Personal Access Token para integração Backstage
# Scopes necessários: repo, workflow, read:org, read:user
# Gerar em: https://github.com/settings/tokens
github_token: "ghp_seu_token_aqui"

# Repositório para recursos de infraestrutura (S3, RDS, EKS, etc.)
# Backstage criará Pull Requests aqui ao provisionar recursos
infrastructure_repo: "infrastructureidp"

# Repositório para templates do Backstage
# Contém Software Templates para criar aplicações e recursos
templates_repo: "backstage-templates"
```

**Onde é usado:**
- `github_org` - Organização/usuário GitHub
- `github_token` - **Lido automaticamente pelo `install.sh`** e adicionado no secret `backstage-env-vars`
- `infrastructure_repo` - Repo onde Backstage cria PRs com recursos AWS
- `templates_repo` - Repo com Software Templates

**Fluxo Automático:**
```
config.yaml (github_token)
    ↓
install.sh lê o token
    ↓
Cria secret backstage-env-vars
    ↓
Backstage usa token automaticamente
```

---

### 6. Domínio e DNS (linhas 110-127)

```yaml
domain: "timedevops.click"

subdomains:
  argocd: "argocd"        # argocd.timedevops.click
  backstage: "backstage"  # backstage.timedevops.click
  keycloak: "keycloak"    # keycloak.timedevops.click

route53_hosted_zone_id: "Z09212782MXWNY5EYNICO"

path_routing: "false"  # false = subdomain, true = path
```

---

### 7. Tags AWS (linhas 129-139)

```yaml
tags:
  githubRepo: "github.com/darede-labs/reference-implementation-aws"
  env: "poc"
  project: "idp"
  owner: "platform-team"
  cost-center: "engineering"
```

---

## 🔄 Como o config.yaml é Usado

### Terraform

```hcl
# cluster/terraform/main.tf
locals {
  config = yamldecode(file("${path.module}/../../config.yaml"))

  cluster_name = local.config.cluster_name
  region       = local.config.region
  github_org   = local.config.github_org
  # ...
}
```

### Install Script

```bash
# scripts/install.sh

# Ler valores
DOMAIN_NAME=$(yq eval '.domain' config.yaml)
CLUSTER_NAME=$(yq eval '.cluster_name' config.yaml)
GITHUB_TOKEN=$(yq eval '.github_token' config.yaml)

# Usar nos secrets
kubectl create secret generic backstage-env-vars \
  --from-literal=GITHUB_TOKEN=${GITHUB_TOKEN} \
  ...
```

### Templates Backstage

```yaml
# template.yaml
parameters:
  - properties:
      repoUrl:
        default: github.com?repo=infrastructureidp&owner=darede-labs
```

---

## ✅ Checklist de Configuração

Antes de rodar `terraform apply` + `install.sh`:

### Obrigatório

- [ ] `cluster_name` - Nome único do cluster
- [ ] `region` - Região AWS válida
- [ ] `domain` - Domínio registrado
- [ ] `route53_hosted_zone_id` - ID da hosted zone
- [ ] `github_org` - Sua organização GitHub
- [ ] `github_token` - Token válido com scopes corretos
- [ ] `infrastructure_repo` - Nome do repo de infra
- [ ] `templates_repo` - Nome do repo de templates

### Opcional (tem defaults)

- [ ] `vpc.mode` - create ou existing
- [ ] `node_groups.capacity_type` - SPOT ou ON_DEMAND
- [ ] `node_groups.instance_types` - Lista de tipos
- [ ] `nat_gateway_mode` - single ou one_per_az

---

## 🔍 Validar config.yaml

```bash
# Verificar sintaxe YAML
yq eval '.' config.yaml > /dev/null && echo "✅ YAML válido" || echo "❌ YAML inválido"

# Ver valores específicos
yq eval '.cluster_name' config.yaml
yq eval '.github_org' config.yaml
yq eval '.github_token' config.yaml
yq eval '.infrastructure_repo' config.yaml

# Validar GitHub token
GITHUB_TOKEN=$(yq eval '.github_token' config.yaml)
curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login'
# Deve retornar seu username GitHub

# Validar repos existem
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

gh repo view $GITHUB_ORG/$INFRA_REPO
```

---

## 🔒 Segurança do GitHub Token

### ⚠️ IMPORTANTE: Não commitar token no Git

O `github_token` contém credencial sensível. **Nunca commitar no Git!**

#### Opção 1: Gitignore o config.yaml

```bash
# .gitignore
config.yaml
```

**Criar `config.yaml.example`:**
```yaml
github_token: "ghp_YOUR_TOKEN_HERE"  # Substitua pelo seu token
```

#### Opção 2: Usar Variável de Ambiente

```yaml
# config.yaml
github_token: "${GITHUB_TOKEN}"  # Referência a env var
```

```bash
# Antes de rodar install.sh
export GITHUB_TOKEN="ghp_seu_token_aqui"
envsubst < config.yaml > config-resolved.yaml
```

#### Opção 3: AWS Secrets Manager

```bash
# Armazenar token no Secrets Manager
aws secretsmanager create-secret \
  --name github-backstage-token \
  --secret-string "ghp_seu_token_aqui"

# install.sh busca do Secrets Manager
GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id github-backstage-token \
  --query SecretString \
  --output text)
```

---

## 📝 Exemplo Completo

```yaml
### Config for CNOE AWS Reference Implementation ###

repo:
  url: "https://github.com/darede-labs/reference-implementation-aws"
  revision: "main"
  basepath: "packages"

cluster_name: "idp-prod-cluster"
region: "us-east-1"
auto_mode: "false"
iam_auth_method: "irsa"

vpc:
  mode: "create"
  cidr: "10.0.0.0/16"
  availability_zones: 3
  nat_gateway_mode: "single"

node_groups:
  capacity_type: "SPOT"
  instance_types:
    - "t3.medium"
    - "t3a.medium"
  scaling:
    min_size: 3
    max_size: 10
    desired_size: 4
  disk_size: 50

# BACKSTAGE INTEGRATION
github_org: "minha-empresa"
github_token: "ghp_abc123xyz..."  # ← Seu token aqui
infrastructure_repo: "infrastructure-aws"
templates_repo: "platform-templates"

domain: "plataforma.minhaempresa.com"
subdomains:
  argocd: "argocd"
  backstage: "backstage"
  keycloak: "auth"
route53_hosted_zone_id: "Z123456789ABC"
path_routing: "false"

tags:
  env: "production"
  project: "internal-platform"
  owner: "platform-team"
  cost-center: "engineering"
```

---

## 🚀 Workflow Completo

```bash
# 1. Editar config.yaml
vim config.yaml
# Preencher: github_org, github_token, infrastructure_repo, etc.

# 2. Validar
yq eval '.' config.yaml
./scripts/validate-config.sh  # Se existir

# 3. Criar repos GitHub
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

gh repo create $GITHUB_ORG/$INFRA_REPO --private

# 4. Terraform
cd cluster/terraform
export AWS_PROFILE=darede
terraform init
terraform apply -auto-approve

# 5. Install
cd ../..
export AWS_PROFILE=darede
export AUTO_CONFIRM=yes
./scripts/install.sh

# ✅ GitHub token é lido automaticamente do config.yaml
# ✅ Secret backstage-env-vars criado automaticamente
# ✅ Backstage pode criar PRs imediatamente
```

---

**Última atualização:** 11 de Dezembro de 2025
