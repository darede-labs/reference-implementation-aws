# Setup: Repositório infrastructureidp

Guia para configurar o repositório privado `infrastructureidp` criado.

---

## ✅ PASSO 1: Atualizar config.yaml

**Já feito!** ✓

```yaml
# config.yaml (linha 99)
infrastructure_repo: "infrastructureidp"
```

---

## 🔧 PASSO 2: Criar Estrutura no Repositório

```bash
export AWS_PROFILE=darede

# Ler configuração
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

# Clonar repo
cd ~/
git clone https://github.com/$GITHUB_ORG/$INFRA_REPO.git
cd $INFRA_REPO

# Criar estrutura de pastas
mkdir -p s3-buckets
mkdir -p rds-databases
mkdir -p dynamodb-tables
mkdir -p eks-clusters
mkdir -p vpc-networks

# Criar README
cat > README.md <<EOF
# Infrastructure IDP

Recursos AWS provisionados via Crossplane e gerenciados pelo Backstage.

## Estrutura

\`\`\`
.
├── s3-buckets/         # Buckets S3
├── rds-databases/      # Bancos de dados RDS
├── dynamodb-tables/    # Tabelas DynamoDB
├── eks-clusters/       # Clusters EKS
└── vpc-networks/       # VPCs e Redes
\`\`\`

## Como Criar Recursos

**Não edite diretamente!** Use o Backstage:

1. Acesse https://backstage.timedevops.click
2. Login: admin / admin
3. Clique em **Create**
4. Selecione o template do recurso desejado
5. Preencha o formulário
6. Aguarde PR ser criado
7. Aprove e faça merge
8. Recurso será criado automaticamente na AWS via Crossplane

## Monitoramento

Este repositório é monitorado pelo ArgoCD:
- Qualquer merge na branch \`main\` é aplicado automaticamente no cluster
- ArgoCD detecta mudanças e aplica via Crossplane
- Crossplane cria/atualiza recursos na AWS

## Organização

- **Organização:** $GITHUB_ORG
- **Repositório:** $INFRA_REPO
- **Visibilidade:** Private
EOF

# Criar .gitignore
cat > .gitignore <<'EOF'
.DS_Store
*.swp
*.swo
*~
.terraform/
*.tfstate
*.tfstate.backup
EOF

# Commit inicial
git add .
git commit -m "Initial structure for Infrastructure IDP"
git push origin main
```

---

## 🔑 PASSO 3: Configurar GitHub Token (Para Repo Privado)

### 3.1 Criar Personal Access Token

**Repositório privado precisa de token com permissões específicas!**

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
2. **Generate new token (classic)**
3. Nome: `backstage-argocd-integration`
4. Expiration: `No expiration` (ou 1 ano)
5. **Scopes necessários para repo privado:**
   - ✅ `repo` (full control) - **OBRIGATÓRIO**
   - ✅ `workflow`
   - ✅ `read:org`
   - ✅ `read:user`
6. **Generate token**
7. **COPIE O TOKEN** (ex: `ghp_abc123...`)

### 3.2 Adicionar Token ao Backstage

```bash
export AWS_PROFILE=darede

# Cole seu token aqui
GITHUB_TOKEN="ghp_seu_token_aqui"

# Atualizar secret do Backstage
kubectl patch secret backstage-env-vars -n backstage \
  -p "{\"data\":{\"GITHUB_TOKEN\":\"$(echo -n $GITHUB_TOKEN | base64)\"}}"

# Reiniciar Backstage para carregar novo token
kubectl rollout restart deployment/backstage -n backstage

# Aguardar pod ficar pronto
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=120s

echo "✅ GitHub Token configurado no Backstage"
```

### 3.3 Testar Token

```bash
# Ler token do secret
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)

# Testar acesso ao repo privado
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$GITHUB_ORG/$INFRA_REPO

# Se retornar JSON com dados do repo: ✅ Token OK
# Se retornar 404: ❌ Token sem acesso ao repo
```

---

## 🔄 PASSO 4: Configurar ArgoCD para Repo Privado

### 4.1 Adicionar Credenciais do GitHub no ArgoCD

```bash
export AWS_PROFILE=darede

# Ler configuração
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

# Ler GitHub token
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)

# Criar secret com credenciais GitHub para ArgoCD
kubectl create secret generic infrastructureidp-repo \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/$GITHUB_ORG/$INFRA_REPO \
  --from-literal=password=$GITHUB_TOKEN \
  --from-literal=username=git \
  --dry-run=client -o yaml | kubectl apply -f -

# Adicionar label para ArgoCD reconhecer
kubectl label secret infrastructureidp-repo \
  -n argocd \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "✅ Credenciais do repo privado adicionadas ao ArgoCD"
```

### 4.2 Verificar Credenciais

```bash
# Listar repositórios configurados no ArgoCD
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository

# Ver detalhes
kubectl get secret infrastructureidp-repo -n argocd -o yaml
```

---

## 📦 PASSO 5: Criar ArgoCD Application

```bash
export AWS_PROFILE=darede

# Ler configuração
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

# Criar Application do ArgoCD
cat > /tmp/argocd-infrastructure-app.yaml <<EOF
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
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

kubectl apply -f /tmp/argocd-infrastructure-app.yaml

echo "✅ ArgoCD Application criada"
```

### 5.2 Verificar Application

```bash
# Ver status
kubectl get application infrastructure -n argocd

# Ver detalhes
kubectl describe application infrastructure -n argocd

# Ver sync status
kubectl get application infrastructure -n argocd -o jsonpath='{.status.sync.status}'
# Deve retornar: Synced

# Ver URL do repo
kubectl get application infrastructure -n argocd -o jsonpath='{.spec.source.repoURL}'
# Deve retornar: https://github.com/darede-labs/infrastructureidp.git
```

---

## ✅ PASSO 6: Validar Tudo

```bash
export AWS_PROFILE=darede

echo "🔍 Validando configuração..."
echo ""

# 1. Config.yaml
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

echo "📋 Config.yaml:"
echo "  Org: $GITHUB_ORG"
echo "  Repo: $INFRA_REPO"
echo ""

# 2. Repositório existe e tem conteúdo
echo "📦 Repositório GitHub:"
gh repo view $GITHUB_ORG/$INFRA_REPO --json name,visibility,defaultBranchRef \
  --jq '"  Nome: \(.name)\n  Visibilidade: \(.visibility)\n  Branch: \(.defaultBranchRef.name)"'
echo ""

# 3. GitHub Token configurado
echo "🔑 GitHub Token:"
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' 2>/dev/null | base64 -d)
if [ -n "$GITHUB_TOKEN" ]; then
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)
  if [ "$RESPONSE" = "200" ]; then
    echo "  ✅ Token válido"

    # Testar acesso ao repo
    REPO_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG/$INFRA_REPO)
    if [ "$REPO_RESPONSE" = "200" ]; then
      echo "  ✅ Token tem acesso ao repo privado"
    else
      echo "  ❌ Token NÃO tem acesso ao repo (HTTP $REPO_RESPONSE)"
    fi
  else
    echo "  ❌ Token inválido (HTTP $RESPONSE)"
  fi
else
  echo "  ❌ Token não encontrado"
fi
echo ""

# 4. ArgoCD credenciais
echo "🔐 ArgoCD Credenciais:"
if kubectl get secret infrastructureidp-repo -n argocd &>/dev/null; then
  echo "  ✅ Secret do repo privado configurado"
else
  echo "  ❌ Secret do repo privado NÃO encontrado"
fi
echo ""

# 5. ArgoCD Application
echo "🔄 ArgoCD Application:"
if kubectl get application infrastructure -n argocd &>/dev/null; then
  SYNC_STATUS=$(kubectl get application infrastructure -n argocd -o jsonpath='{.status.sync.status}')
  HEALTH_STATUS=$(kubectl get application infrastructure -n argocd -o jsonpath='{.status.health.status}')
  echo "  ✅ Application existe"
  echo "  Sync: $SYNC_STATUS"
  echo "  Health: $HEALTH_STATUS"
else
  echo "  ❌ Application NÃO encontrada"
fi
echo ""

# 6. Crossplane
echo "⚙️  Crossplane:"
CROSSPLANE_PODS=$(kubectl get pods -n crossplane-system -l app=crossplane --no-headers 2>/dev/null | wc -l)
if [ "$CROSSPLANE_PODS" -gt 0 ]; then
  echo "  ✅ Crossplane instalado ($CROSSPLANE_PODS pods)"

  PROVIDERS=$(kubectl get providers --no-headers 2>/dev/null | wc -l)
  echo "  ✅ Providers instalados: $PROVIDERS"
else
  echo "  ❌ Crossplane não encontrado"
fi
echo ""

echo "✅ Validação concluída!"
```

---

## 🎯 Próximos Passos

Agora que o repo está configurado:

### 1. Criar Repo de Templates

```bash
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
TEMPLATES_REPO=$(yq eval '.templates_repo' config.yaml)

# Criar repo de templates (pode ser público)
gh repo create $GITHUB_ORG/$TEMPLATES_REPO --public --description "Backstage Software Templates"

cd ~/
git clone https://github.com/$GITHUB_ORG/$TEMPLATES_REPO.git
cd $TEMPLATES_REPO

mkdir -p s3-bucket/skeleton

# Criar template S3 (exemplo)
# ... (ver docs/GUIA-PASSO-A-PASSO-BACKSTAGE.md PASSO 3)
```

### 2. Criar Primeiro Template

Ver guia completo: `docs/GUIA-PASSO-A-PASSO-BACKSTAGE.md` - PASSO 3

### 3. Registrar Template no Backstage

```
1. https://backstage.timedevops.click
2. Create → Register Existing Component
3. URL: https://github.com/darede-labs/backstage-templates/blob/main/s3-bucket/template.yaml
```

### 4. Testar Criação de Recurso

```
1. Backstage → Create → AWS S3 Bucket
2. Nome: test-bucket-123
3. Create
4. Aguardar PR
5. Merge PR
6. Verificar: kubectl get buckets -n crossplane-system
```

---

## 🐛 Troubleshooting

### ArgoCD não consegue acessar repo

**Sintoma:** Application status: "ComparisonError" ou "Failed to load repository"

**Solução:**
```bash
# Recriar secret com credenciais
kubectl delete secret infrastructureidp-repo -n argocd
# Depois executar PASSO 4.1 novamente
```

### Backstage não consegue criar PR

**Sintoma:** Erro "Repository not found" ao tentar criar recurso

**Solução:**
```bash
# Verificar token tem escopo 'repo'
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r .login

# Se falhar, criar novo token com scope 'repo' completo
```

### Recurso não é criado após merge

**Sintoma:** PR merged mas recurso não aparece na AWS

**Solução:**
```bash
# Ver logs do ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50

# Ver status da Application
kubectl describe application infrastructure -n argocd

# Forçar sync
kubectl patch application infrastructure -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

## 📋 Checklist de Conclusão

- [x] config.yaml atualizado com `infrastructure_repo: "infrastructureidp"`
- [ ] Estrutura criada no repo (pastas, README)
- [ ] GitHub token criado com scope `repo`
- [ ] Token configurado no Backstage
- [ ] Credenciais do repo privado adicionadas ao ArgoCD
- [ ] ArgoCD Application criada e Synced
- [ ] Validação executada com sucesso
- [ ] Próximos passos: criar repo de templates

---

**Última atualização:** 11 de Dezembro de 2025
