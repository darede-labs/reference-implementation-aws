# Guia de Uso do Backstage - Software Templates

Este guia explica como usar o Backstage para criar aplicações e recursos AWS via **Software Templates**.

---

## 🎯 O que é o Backstage?

O Backstage é uma **plataforma de desenvolvedor (IDP)** que permite:

1. **Software Catalog** - Catálogo de todos os serviços, APIs, bibliotecas da organização
2. **Software Templates** - Templates para criar novos serviços, aplicações, recursos
3. **TechDocs** - Documentação técnica centralizada
4. **Plugins** - Integrações com Kubernetes, ArgoCD, GitHub, etc.

---

## 📋 Funcionalidades Principais

### 1. Software Catalog (Catálogo de Serviços)

**O que é:**
- Inventário centralizado de todos os componentes da organização
- Cada componente tem: owner, tipo, lifecycle, dependências, documentação

**Como registrar um componente:**

1. Criar arquivo `catalog-info.yaml` no repositório:
```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: meu-servico
  description: Microserviço de exemplo
  annotations:
    github.com/project-slug: darede-labs/meu-servico
    argocd/app-name: meu-servico
spec:
  type: service
  lifecycle: production
  owner: team-platform
  system: idp
```

2. No Backstage, ir em **Create** → **Register Existing Component**
3. Inserir URL do `catalog-info.yaml`:
   ```
   https://github.com/darede-labs/meu-servico/blob/main/catalog-info.yaml
   ```

---

### 2. Software Templates (Criação de Aplicações)

**O que são:**
Templates para scaffolding de novos serviços, aplicações ou recursos.

**Exemplos de templates úteis:**
- ✅ Microserviço Node.js com CI/CD
- ✅ API REST Python com FastAPI
- ✅ Frontend React
- ✅ Recurso AWS (S3, RDS, DynamoDB) via Crossplane
- ✅ Helm Chart customizado

---

## 🚀 Como Criar um Software Template

### Estrutura de um Template

Um Software Template é composto por:

1. **`template.yaml`** - Definição do template
2. **`skeleton/`** - Código skeleton da aplicação
3. **`docs/`** - Documentação (opcional)

### Exemplo 1: Template de Microserviço Node.js

#### 1.1 Criar repositório do template

```bash
mkdir -p backstage-templates/nodejs-microservice
cd backstage-templates/nodejs-microservice
```

#### 1.2 Criar `template.yaml`

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: nodejs-microservice
  title: Node.js Microservice
  description: Cria um microserviço Node.js com Express, Docker e CI/CD
  tags:
    - nodejs
    - microservice
    - recommended
spec:
  owner: team-platform
  type: service

  parameters:
    - title: Informações do Serviço
      required:
        - name
        - description
        - owner
      properties:
        name:
          title: Nome do Serviço
          type: string
          description: Nome único do serviço (lowercase, hífens)
          pattern: '^[a-z0-9-]+$'
          ui:autofocus: true
        description:
          title: Descrição
          type: string
          description: Descrição curta do serviço
        owner:
          title: Owner
          type: string
          description: Time responsável
          ui:field: OwnerPicker
          ui:options:
            catalogFilter:
              kind: Group

    - title: Configuração do Repositório
      required:
        - repoUrl
      properties:
        repoUrl:
          title: Repository Location
          type: string
          ui:field: RepoUrlPicker
          ui:options:
            allowedHosts:
              - github.com

  steps:
    - id: fetch
      name: Fetch Skeleton
      action: fetch:template
      input:
        url: ./skeleton
        values:
          name: ${{ parameters.name }}
          description: ${{ parameters.description }}
          owner: ${{ parameters.owner }}

    - id: publish
      name: Publish to GitHub
      action: publish:github
      input:
        allowedHosts: ['github.com']
        description: ${{ parameters.description }}
        repoUrl: ${{ parameters.repoUrl }}
        defaultBranch: main

    - id: register
      name: Register Component
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: '/catalog-info.yaml'

    - id: create-argocd-app
      name: Create ArgoCD Application
      action: argocd:create-application
      input:
        appName: ${{ parameters.name }}
        projectName: default
        repoUrl: ${{ steps.publish.output.remoteUrl }}
        path: k8s/

  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
      - title: Open in catalog
        icon: catalog
        entityRef: ${{ steps.register.output.entityRef }}
```

#### 1.3 Criar `skeleton/` com código do microserviço

```bash
mkdir -p skeleton/src skeleton/k8s
```

**`skeleton/package.json`:**
```json
{
  "name": "${{ values.name }}",
  "version": "1.0.0",
  "description": "${{ values.description }}",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
```

**`skeleton/src/index.js`:**
```javascript
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    service: '${{ values.name }}',
    description: '${{ values.description }}',
    status: 'healthy'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(port, () => {
  console.log(`${{ values.name }} running on port ${port}`);
});
```

**`skeleton/Dockerfile`:**
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY src/ ./src/
EXPOSE 3000
CMD ["npm", "start"]
```

**`skeleton/catalog-info.yaml`:**
```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ${{ values.name }}
  description: ${{ values.description }}
  annotations:
    github.com/project-slug: ${{ values.destination.owner + "/" + values.destination.repo }}
    argocd/app-name: ${{ values.name }}
spec:
  type: service
  lifecycle: experimental
  owner: ${{ values.owner }}
  system: platform
```

**`skeleton/k8s/deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${{ values.name }}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${{ values.name }}
  template:
    metadata:
      labels:
        app: ${{ values.name }}
    spec:
      containers:
      - name: app
        image: ghcr.io/darede-labs/${{ values.name }}:latest
        ports:
        - containerPort: 3000
        env:
        - name: PORT
          value: "3000"
---
apiVersion: v1
kind: Service
metadata:
  name: ${{ values.name }}
spec:
  selector:
    app: ${{ values.name }}
  ports:
  - port: 80
    targetPort: 3000
```

#### 1.4 Registrar o template no Backstage

1. Fazer push do template para GitHub:
```bash
git init
git add .
git commit -m "Add Node.js microservice template"
git remote add origin https://github.com/darede-labs/backstage-templates.git
git push -u origin main
```

2. No Backstage, registrar o template:
   - Ir em **Create** → **Register Existing Component**
   - URL: `https://github.com/darede-labs/backstage-templates/blob/main/nodejs-microservice/template.yaml`

---

## ☁️ Template para Recursos AWS (Crossplane)

### Exemplo 2: Template de Bucket S3

#### 2.1 Criar `template.yaml`

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
    - infrastructure
spec:
  owner: team-platform
  type: resource

  parameters:
    - title: Configuração do Bucket
      required:
        - bucketName
        - region
        - owner
      properties:
        bucketName:
          title: Nome do Bucket
          type: string
          description: Nome único do bucket S3 (lowercase, sem underscores)
          pattern: '^[a-z0-9-]+$'
        region:
          title: AWS Region
          type: string
          enum:
            - us-east-1
            - us-west-2
            - sa-east-1
          default: us-east-1
        encryption:
          title: Encryption
          type: boolean
          default: true
        versioning:
          title: Versioning
          type: boolean
          default: false
        owner:
          title: Owner Team
          type: string
          ui:field: OwnerPicker

  steps:
    - id: fetch
      name: Fetch Crossplane Resource
      action: fetch:template
      input:
        url: ./skeleton
        values:
          bucketName: ${{ parameters.bucketName }}
          region: ${{ parameters.region }}
          encryption: ${{ parameters.encryption }}
          versioning: ${{ parameters.versioning }}
          owner: ${{ parameters.owner }}

    - id: pr
      name: Create Pull Request
      action: publish:github:pull-request
      input:
        repoUrl: github.com?repo=infrastructure&owner=darede-labs
        branchName: add-s3-${{ parameters.bucketName }}
        title: 'Add S3 bucket: ${{ parameters.bucketName }}'
        description: 'Creates S3 bucket ${{ parameters.bucketName }} in ${{ parameters.region }}'

  output:
    links:
      - title: Pull Request
        url: ${{ steps.pr.output.remoteUrl }}
```

#### 2.2 Criar `skeleton/s3-bucket.yaml`

```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: ${{ values.bucketName }}
  labels:
    owner: ${{ values.owner }}
    managed-by: backstage
spec:
  forProvider:
    region: ${{ values.region }}
    {% if values.versioning %}
    versioning:
      - enabled: true
    {% endif %}
    {% if values.encryption %}
    serverSideEncryptionConfiguration:
      - rule:
          - applyServerSideEncryptionByDefault:
              - sseAlgorithm: AES256
    {% endif %}
  providerConfigRef:
    name: default
---
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: ${{ values.bucketName }}
  description: S3 bucket managed by Crossplane
  annotations:
    aws.amazon.com/region: ${{ values.region }}
spec:
  type: s3-bucket
  owner: ${{ values.owner }}
  dependsOn:
    - resource:aws-provider
```

---

## 🎨 Actions Disponíveis no Backstage

### Actions Básicas

| Action | Descrição |
|--------|-----------|
| `fetch:template` | Busca skeleton e substitui variáveis |
| `fetch:plain` | Busca arquivos sem substituição |
| `publish:github` | Cria repositório no GitHub |
| `publish:gitlab` | Cria repositório no GitLab |
| `publish:github:pull-request` | Cria Pull Request |
| `catalog:register` | Registra componente no catalog |
| `catalog:fetch` | Busca entidade do catalog |

### Actions de Infraestrutura

| Action | Descrição |
|--------|-----------|
| `argocd:create-application` | Cria aplicação no ArgoCD |
| `kubernetes:apply` | Aplica manifesto Kubernetes |
| `aws:s3:create` | Cria bucket S3 |
| `debug:log` | Log para debugging |

---

## 📚 Como Usar Templates no Backstage

### 1. Acessar Software Templates

1. Login no Backstage: https://backstage.timedevops.click
2. Clicar em **Create** no menu lateral
3. Ver lista de templates disponíveis

### 2. Criar novo serviço a partir de template

1. Selecionar template (ex: "Node.js Microservice")
2. Preencher formulário:
   - Nome do serviço
   - Descrição
   - Owner (time responsável)
   - Repositório GitHub
3. Clicar em **Create**
4. Aguardar execução das steps
5. Ver links de saída:
   - Repositório criado no GitHub
   - Componente registrado no Catalog
   - Aplicação criada no ArgoCD

### 3. Ver componente no Catalog

1. Ir em **Catalog** no menu lateral
2. Buscar pelo nome do serviço
3. Ver informações:
   - Overview
   - CI/CD (GitHub Actions)
   - Kubernetes (pods, deployments)
   - ArgoCD (sync status)
   - Dependencies
   - Docs

---

## 🔧 Configurações Adicionais

### Habilitar GitHub Integration

**No `app-config.yaml` do Backstage:**
```yaml
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

**Criar GitHub Token:**
1. GitHub → Settings → Developer settings → Personal access tokens
2. Scopes necessários:
   - `repo` (full control)
   - `workflow`
   - `read:org`
   - `read:user`

### Habilitar ArgoCD Plugin

**No `app-config.yaml`:**
```yaml
argocd:
  username: admin
  password: ${ARGOCD_ADMIN_PASSWORD}
  appLocatorMethods:
    - type: 'config'
      instances:
        - name: in-cluster
          url: https://argocd.timedevops.click
          username: admin
          password: ${ARGOCD_ADMIN_PASSWORD}
```

---

## 📖 Recursos Adicionais

### Documentação Oficial
- [Backstage Software Templates](https://backstage.io/docs/features/software-templates/)
- [Template Actions](https://backstage.io/docs/features/software-templates/builtin-actions)
- [Writing Templates](https://backstage.io/docs/features/software-templates/writing-templates)

### Exemplos de Templates
- [Backstage Sample Templates](https://github.com/backstage/software-templates)
- [Spotify Templates](https://github.com/spotify/backstage-templates)

### Plugins Úteis
- [@backstage/plugin-catalog-import](https://www.npmjs.com/package/@backstage/plugin-catalog-import)
- [@backstage/plugin-scaffolder](https://www.npmjs.com/package/@backstage/plugin-scaffolder)
- [@backstage/plugin-kubernetes](https://www.npmjs.com/package/@backstage/plugin-kubernetes)
- [@backstage/plugin-argocd](https://www.npmjs.com/package/@backstage/plugin-argocd)
- [@backstage/plugin-techdocs](https://www.npmjs.com/package/@backstage/plugin-techdocs)

---

## 🎯 Próximos Passos Recomendados

1. **Criar template básico de microserviço** seguindo o exemplo acima
2. **Configurar GitHub Token** para integração
3. **Testar criação de serviço** via template
4. **Criar templates de recursos AWS** (S3, RDS, DynamoDB via Crossplane)
5. **Configurar TechDocs** para documentação centralizada
6. **Adicionar Custom Actions** se necessário

---

**Última atualização:** 11 de Dezembro de 2025
