# Como Usar config.yaml nos Templates do Backstage

## 📋 Configuração no config.yaml

As configurações dos repositórios estão em:

```yaml
# config.yaml (linhas 90-103)

################################################################################
# Backstage Integration Repositories
################################################################################

# GitHub organization/user onde repositórios serão criados
github_org: "darede-labs"

# Repositório para recursos de infraestrutura (S3, RDS, EKS, etc.)
# Backstage criará Pull Requests aqui ao provisionar recursos
infrastructure_repo: "infrastructure"

# Repositório para templates do Backstage
# Contém Software Templates para criar aplicações e recursos
templates_repo: "backstage-templates"
```

---

## 🔧 Como Usar nos Templates

### Opção 1: Hardcoded (Simples, mas menos flexível)

```yaml
# template.yaml
steps:
  - id: pr
    name: Create Pull Request
    action: publish:github:pull-request
    input:
      repoUrl: github.com?repo=infrastructure&owner=darede-labs
      branchName: add-s3-${{ parameters.bucketName }}
      title: 'Add S3 bucket: ${{ parameters.bucketName }}'
```

**Problema:** Se mudar o nome do repo ou org, precisa editar todos os templates.

---

### Opção 2: Variável no Template (Recomendado)

```yaml
# template.yaml
parameters:
  - title: Repositório de Infraestrutura
    properties:
      repoUrl:
        title: Infrastructure Repository
        type: string
        description: Repositório onde os manifestos serão commitados
        default: github.com?repo=infrastructure&owner=darede-labs
        ui:readonly: true

steps:
  - id: pr
    name: Create Pull Request
    action: publish:github:pull-request
    input:
      repoUrl: ${{ parameters.repoUrl }}
      branchName: add-s3-${{ parameters.bucketName }}
      title: 'Add S3 bucket: ${{ parameters.bucketName }}'
```

**Vantagem:** Valor padrão vem do config.yaml, mas pode ser mudado se necessário.

---

### Opção 3: Usar Backstage App Config (Mais Avançado)

#### 3.1 Adicionar no app-config do Backstage

**Arquivo:** `packages/backstage/values.yaml`

```yaml
backstage:
  appConfig:
    organization:
      name: darede
    integrations:
      github:
        - host: github.com
          organization: darede-labs

    # Configurações customizadas
    custom:
      infrastructure:
        githubOrg: darede-labs
        infrastructureRepo: infrastructure
        templatesRepo: backstage-templates
```

#### 3.2 Usar no template via App Config

```yaml
# template.yaml
steps:
  - id: pr
    name: Create Pull Request
    action: publish:github:pull-request
    input:
      # Referência ao app-config
      repoUrl: github.com?repo=${{ app.custom.infrastructure.infrastructureRepo }}&owner=${{ app.custom.infrastructure.githubOrg }}
      branchName: add-s3-${{ parameters.bucketName }}
```

---

## 📝 Template Completo Usando config.yaml

### Exemplo: S3 Bucket Template

```yaml
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
          pattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'

        region:
          title: AWS Region
          type: string
          enum:
            - us-east-1
            - us-west-2
            - sa-east-1
          default: us-east-1

    # Repositório configurável via config.yaml
    - title: Repositório
      properties:
        repoUrl:
          title: Infrastructure Repository
          type: string
          # Valor padrão vem do config.yaml
          default: github.com?repo=infrastructure&owner=darede-labs
          ui:readonly: true
          ui:help: "Definido em config.yaml (github_org e infrastructure_repo)"

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
        # Usa variável do parameter
        repoUrl: ${{ parameters.repoUrl }}
        branchName: add-s3-${{ parameters.bucketName }}
        title: 'feat: Add S3 bucket ${{ parameters.bucketName }}'
        description: |
          ## S3 Bucket Configuration

          - **Bucket:** ${{ parameters.bucketName }}
          - **Region:** ${{ parameters.region }}

          Provisioned via Backstage (config.yaml)

  output:
    links:
      - title: Pull Request
        url: ${{ steps.pr.output.remoteUrl }}
```

---

## 🔄 Script Helper para Gerar Templates

Crie um script que lê o `config.yaml` e gera templates automaticamente:

**`scripts/generate-templates.sh`:**

```bash
#!/bin/bash

# Ler config.yaml e extrair valores
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)
TEMPLATES_REPO=$(yq eval '.templates_repo' config.yaml)

echo "📦 Gerando templates com:"
echo "  GitHub Org: $GITHUB_ORG"
echo "  Infra Repo: $INFRA_REPO"
echo "  Templates Repo: $TEMPLATES_REPO"

# Criar template S3
cat > ~/backstage-templates/s3-bucket/template.yaml <<EOF
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: aws-s3-bucket
  title: AWS S3 Bucket
spec:
  parameters:
    - title: Repositório
      properties:
        repoUrl:
          default: github.com?repo=${INFRA_REPO}&owner=${GITHUB_ORG}
          ui:readonly: true
  steps:
    - id: pr
      action: publish:github:pull-request
      input:
        repoUrl: \${{ parameters.repoUrl }}
EOF

echo "✅ Template gerado em ~/backstage-templates/s3-bucket/template.yaml"
```

---

## 📚 Atualizar Guia Passo a Passo

### Antes de Criar Templates

```bash
# 1. Editar config.yaml com suas configurações
vim config.yaml

# Alterar:
github_org: "sua-org"              # Sua organização GitHub
infrastructure_repo: "infra-aws"    # Nome do seu repo de infra
templates_repo: "templates"         # Nome do seu repo de templates

# 2. Gerar templates automaticamente
./scripts/generate-templates.sh

# 3. Fazer push dos templates
cd ~/backstage-templates
git add .
git commit -m "Generated from config.yaml"
git push
```

---

## ✅ Vantagens desta Abordagem

1. **Centralizado:** Todas configurações em um único lugar (config.yaml)
2. **Reutilizável:** Mesmo config.yaml para Terraform, ArgoCD e Backstage
3. **Fácil de mudar:** Atualiza config.yaml e regenera templates
4. **Documentado:** Comentários no config.yaml explicam cada opção
5. **Validável:** Pode criar schema YAML para validar config

---

## 🔍 Verificar Configuração

```bash
# Ver configurações atuais
yq eval '.github_org' config.yaml
yq eval '.infrastructure_repo' config.yaml
yq eval '.templates_repo' config.yaml

# Validar config.yaml
yq eval '.' config.yaml > /dev/null && echo "✅ YAML válido" || echo "❌ YAML inválido"
```

---

## 📋 Checklist

Ao criar novos templates, lembrar de:

- [ ] Ler valores de `github_org` e `infrastructure_repo` do config.yaml
- [ ] Usar como default no parameter `repoUrl`
- [ ] Marcar como `ui:readonly: true` se não deve ser editável
- [ ] Adicionar `ui:help` explicando que vem do config.yaml
- [ ] Testar template após mudar config.yaml

---

**Última atualização:** 11 de Dezembro de 2025
