# Como Adicionar Templates no Catálogo do Backstage

Guia para registrar os templates S3, VPC, EC2, RDS, EKS no Backstage.

---

## 📋 Pré-requisitos

- ✅ Backstage rodando: https://backstage.timedevops.click
- ✅ Templates criados no repo `infrastructureidp`
- ✅ GitHub token configurado (já está no secret `backstage-env-vars`)

---

## 🎯 Métodos de Registro

### **Método 1: Via UI (Recomendado para POC)** 🖱️

**1. Acesse Backstage:**
```
https://backstage.timedevops.click
Login: admin / admin
```

**2. Registre o Template:**
- Sidebar esquerda → **"Create"**
- Botão superior direito → **"REGISTER EXISTING COMPONENT"**
- Cole a URL do template:
  ```
  https://github.com/darede-labs/infrastructureidp/blob/main/backstage-templates/s3-bucket-template.yaml
  ```
- Clique **"ANALYZE"**
- Se validar OK → Clique **"IMPORT"**

**3. Repita para cada template** (se criar mais)

---

### **Método 2: Via Catalog Entity (Recomendado para Produção)** 📦

Crie um arquivo que registra **TODOS** os templates de uma vez.

**1. Criar catalog para templates:**

```bash
cd ~/infrastructureidp

cat > catalog-info.yaml <<'EOF'
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: infrastructure-templates
  description: Templates de infraestrutura AWS via Crossplane
  annotations:
    backstage.io/managed-by-location: 'url:https://github.com/darede-labs/infrastructureidp/blob/main/catalog-info.yaml'
spec:
  type: url
  targets:
    # Template S3
    - https://github.com/darede-labs/infrastructureidp/blob/main/backstage-templates/s3-bucket-template.yaml
    # Adicione mais templates aqui quando criar
    # - https://github.com/darede-labs/infrastructureidp/blob/main/backstage-templates/vpc-template.yaml
    # - https://github.com/darede-labs/infrastructureidp/blob/main/backstage-templates/ec2-template.yaml
EOF

git add catalog-info.yaml
git commit -m "Add Backstage catalog for infrastructure templates"
git push origin main
```

**2. Registrar o catalog no Backstage:**
- Acesse: https://backstage.timedevops.click
- **Create** → **REGISTER EXISTING COMPONENT**
- URL: `https://github.com/darede-labs/infrastructureidp/blob/main/catalog-info.yaml`
- **IMPORT**

**Resultado:** Todos os templates são registrados automaticamente! 🎉

---

### **Método 3: Configuração Permanente (app-config.yaml)** ⚙️

Para que o Backstage **sempre** carregue os templates automaticamente na inicialização.

**Arquivo:** `packages/backstage/values.yaml`

Adicione na seção `appConfig`:

```yaml
catalog:
  locations:
    # Templates de infraestrutura
    - type: url
      target: https://github.com/darede-labs/infrastructureidp/blob/main/catalog-info.yaml
      rules:
        - allow: [Template, Location]
```

**Vantagem:** Templates aparecem automaticamente após cada restart do Backstage.

---

## 📂 Estrutura Recomendada do Repo

```
infrastructureidp/
├── catalog-info.yaml                    # Catalog principal
├── backstage-templates/
│   ├── s3-bucket-template.yaml         # Template S3
│   ├── vpc-template.yaml               # Template VPC (criar)
│   ├── ec2-template.yaml               # Template EC2 (criar)
│   ├── rds-template.yaml               # Template RDS (criar)
│   ├── eks-template.yaml               # Template EKS (criar)
│   └── content/                        # Conteúdo dos templates
│       ├── s3-bucket.yaml
│       ├── vpc.yaml
│       └── ...
└── s3-buckets/                         # Recursos provisionados
    ├── bucket.yaml
    └── catalog-info.yaml
```

---

## ✅ Validar Templates Registrados

### No Backstage UI:

**1. Ver templates disponíveis:**
- Sidebar → **"Create"**
- Deve aparecer: **"Criar Bucket S3"** (e outros quando adicionar)

**2. Ver catalog entities:**
- Sidebar → **"Catalog"**
- Filtro: **"Kind: Template"**
- Deve listar: `s3-bucket-template`

**3. Testar template:**
- **Create** → **"Criar Bucket S3"**
- Preencher formulário
- **Create** → Deve criar PR no GitHub

---

## 🔧 Troubleshooting

### ❌ "Failed to fetch template"

**Causa:** Backstage não consegue acessar repo privado.

**Solução:**
```bash
# Verificar se token está correto
kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d

# Se necessário, reiniciar Backstage
kubectl rollout restart deployment/backstage -n backstage
```

---

### ❌ Template não aparece na lista

**Verificar:**
1. URL do template está correta?
2. Arquivo tem `kind: Template`?
3. Backstage processou? (Ver logs):
```bash
kubectl logs -n backstage deployment/backstage --tail=50 | grep -i template
```

---

### ❌ "Invalid template"

**Causas comuns:**
- YAML inválido (indentação)
- `apiVersion` incorreta (deve ser `scaffolder.backstage.io/v1beta3`)
- Faltando campos obrigatórios (`spec.owner`, `spec.type`)

**Validar YAML:**
```bash
cd ~/infrastructureidp
cat backstage-templates/s3-bucket-template.yaml | yq eval
```

---

## 📝 Template Backstage Mínimo

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: s3-bucket-template
  title: Criar Bucket S3
  description: Provisionar bucket S3 na AWS
  tags:
    - aws
    - s3
spec:
  owner: platform-team
  type: infrastructure

  parameters:
    - title: Configuração do Bucket
      required:
        - bucketName
      properties:
        bucketName:
          title: Nome do Bucket
          type: string

  steps:
    - id: fetch
      name: Fetch Template
      action: fetch:template
      input:
        url: ./content
        values:
          bucketName: ${{ parameters.bucketName }}

    - id: publish
      name: Create Pull Request
      action: publish:github:pull-request
      input:
        repoUrl: github.com?owner=darede-labs&repo=infrastructureidp
        branchName: bucket-${{ parameters.bucketName }}
        title: 'feat: Add bucket ${{ parameters.bucketName }}'
        targetPath: s3-buckets

  output:
    links:
      - title: Pull Request
        url: ${{ steps.publish.output.remoteUrl }}
```

---

## 🚀 Próximos Passos

Depois de registrar o template S3, **criar templates para:**

1. **VPC Template** → Criar VPC via UI
2. **EC2 Template** → Criar instância via UI
3. **RDS Template** → Criar database via UI
4. **EKS Template** → Criar cluster via UI

**Quer que eu crie os templates Backstage para VPC e EC2?**

---

## 📊 Fluxo Completo

```
1. Registrar Template no Backstage
   └─ Via UI ou catalog-info.yaml

2. Template aparece em "Create"
   └─ Usuário preenche formulário

3. Backstage cria PR no GitHub
   └─ Com manifesto YAML (S3Bucket, VPC, etc)

4. Usuário aprova merge
   └─ PR merged para main

5. ArgoCD detecta mudança (< 3 min)
   └─ Aplica manifesto no cluster

6. Crossplane provisiona na AWS
   └─ Cria bucket, VPC, EC2, etc

7. Recurso disponível
   └─ Visível no ArgoCD UI e AWS Console
```

---

**Última atualização:** 11 de Dezembro de 2025
