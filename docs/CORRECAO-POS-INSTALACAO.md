# Correção Pós-Instalação: Como Ajustar Configurações

## 🎯 O que o install.sh FAZ e NÃO FAZ

### ✅ O que install.sh FAZ:

```
1. Instala ArgoCD no cluster
2. Instala External Secrets
3. Instala Cert Manager
4. Instala Ingress NGINX
5. Instala ExternalDNS
6. Configura Helm repos
7. Cria secrets do Backstage (client secret, etc.)
8. Instala Keycloak (via ArgoCD)
9. Instala Backstage (via ArgoCD)
10. Configura IRSA roles
```

### ❌ O que install.sh NÃO FAZ:

```
1. NÃO cria repositórios no GitHub
2. NÃO configura ArgoCD Application "infrastructure"
3. NÃO registra templates no Backstage
4. NÃO cria GitHub token
5. NÃO executa bootstrap do Keycloak
```

**Conclusão:** Se você rodar `install.sh` novamente:
- ✅ Plataforma será reinstalada (ArgoCD, Backstage, Crossplane, etc.)
- ❌ Repositórios continuam como estão (você criou manualmente)
- ❌ Configurações de ArgoCD Applications permanecem
- ❌ Templates registrados no Backstage permanecem

---

## 🔧 Cenário: Errei o Nome do Repo de Infra

### Situação:

```yaml
# config.yaml (ERRADO)
github_org: "darede-labs"
infrastructure_repo: "infra"  # ❌ Queria "infrastructure"
```

**Você já:**
1. ✅ Rodou `terraform apply`
2. ✅ Rodou `install.sh`
3. ✅ Criou repo `infra` no GitHub (nome errado)
4. ✅ Configurou ArgoCD Application apontando para `infra`
5. ✅ Criou templates apontando para `infra`

**Agora quer mudar para `infrastructure`**

---

## 🚀 Solução: Corrigir Sem Reinstalar Tudo

### Opção 1: Renomear Repositório no GitHub (Mais Simples)

```bash
# 1. No GitHub, renomear o repo
# Settings do repo "infra" → General → Rename
# Mudar de "infra" para "infrastructure"

# 2. Atualizar config.yaml
vim config.yaml
# Mudar linha:
infrastructure_repo: "infrastructure"

# 3. Atualizar local clone
cd ~/infra
git remote set-url origin https://github.com/darede-labs/infrastructure.git

# 4. Atualizar ArgoCD Application
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

kubectl patch application infrastructure -n argocd --type merge -p "{
  \"spec\": {
    \"source\": {
      \"repoURL\": \"https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git\"
    }
  }
}"

# 5. Verificar
kubectl get application infrastructure -n argocd -o jsonpath='{.spec.source.repoURL}'

# ✅ PRONTO! Nada mais precisa ser feito.
# GitHub redireciona automaticamente o nome antigo para o novo
```

---

### Opção 2: Criar Novo Repo e Migrar (Mais Trabalho)

```bash
# 1. Criar novo repo com nome correto
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
gh repo create $GITHUB_ORG/infrastructure --public

# 2. Clonar repo antigo e fazer mirror
cd ~/
git clone --mirror https://github.com/$GITHUB_ORG/infra.git
cd infra.git
git push --mirror https://github.com/$GITHUB_ORG/infrastructure.git

# 3. Atualizar config.yaml
vim config.yaml
# Mudar:
infrastructure_repo: "infrastructure"

# 4. Deletar ArgoCD Application antiga
kubectl delete application infrastructure -n argocd

# 5. Criar nova Application
cat > /tmp/argocd-infra.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_ORG}/infrastructure.git
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

# 6. (Opcional) Deletar repo antigo no GitHub
gh repo delete $GITHUB_ORG/infra --yes

# 7. Atualizar templates (se já criados)
# Editar cada template.yaml e mudar repoUrl default
cd ~/backstage-templates
# ... editar templates ...
git add .
git commit -m "Update repo name to infrastructure"
git push
```

---

## 🔄 Outros Cenários Comuns

### Cenário 2: Mudei de Organização GitHub

```yaml
# ANTES
github_org: "old-org"

# DEPOIS
github_org: "new-org"
```

**Solução:**

```bash
# 1. Transferir repos no GitHub
# Repo → Settings → Transfer ownership → new-org

# 2. Atualizar config.yaml
vim config.yaml

# 3. Atualizar ArgoCD Application
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

kubectl patch application infrastructure -n argocd --type merge -p "{
  \"spec\": {
    \"source\": {
      \"repoURL\": \"https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git\"
    }
  }
}"

# 4. Atualizar templates (repoUrl default)
# ... editar templates ...

# 5. Re-registrar templates no Backstage com nova URL
```

---

### Cenário 3: Mudei Nome do Repo de Templates

```yaml
# ANTES
templates_repo: "backstage-templates"

# DEPOIS
templates_repo: "templates"
```

**Solução:**

```bash
# 1. Renomear repo no GitHub
# Settings → Rename: "backstage-templates" → "templates"

# 2. Atualizar config.yaml
vim config.yaml

# 3. No Backstage UI, deletar templates antigos
# Catalog → Templates → ... → Unregister Entity

# 4. Re-registrar com nova URL
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
TEMPLATES_REPO=$(yq eval '.templates_repo' config.yaml)

# Nova URL:
echo "https://github.com/${GITHUB_ORG}/${TEMPLATES_REPO}/blob/main/s3-bucket/template.yaml"

# Backstage → Create → Register Existing Component → colar URL
```

---

### Cenário 4: Configurei GitHub Token Errado

```bash
# 1. Criar novo token correto no GitHub

# 2. Atualizar secret
GITHUB_TOKEN="ghp_novo_token_correto"

kubectl patch secret backstage-env-vars -n backstage \
  -p "{\"data\":{\"GITHUB_TOKEN\":\"$(echo -n $GITHUB_TOKEN | base64)\"}}"

# 3. Reiniciar Backstage
kubectl rollout restart deployment/backstage -n backstage

# 4. Verificar logs
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=50 | grep -i github
```

---

### Cenário 5: Backstage Não Consegue Criar PR

**Problema:** Erro "Repository not found" ou "Permission denied"

**Solução:**

```bash
# 1. Verificar se repo existe
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)

gh repo view $GITHUB_ORG/$INFRA_REPO

# 2. Verificar se token tem permissão
# GitHub → Settings → Personal access tokens → Verificar scopes:
# - repo (full control) ✅
# - workflow ✅

# 3. Testar token manualmente
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)

curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$GITHUB_ORG/$INFRA_REPO

# 4. Se falhar, criar novo token e atualizar
```

---

## 🛠️ Script de Validação Pós-Config

Rode este script após mudar `config.yaml`:

```bash
#!/bin/bash
# validate-config.sh

set -e

echo "🔍 Validando configuração..."

# Ler config
GITHUB_ORG=$(yq eval '.github_org' config.yaml)
INFRA_REPO=$(yq eval '.infrastructure_repo' config.yaml)
TEMPLATES_REPO=$(yq eval '.templates_repo' config.yaml)

echo ""
echo "📋 Configuração Atual:"
echo "  GitHub Org: $GITHUB_ORG"
echo "  Infra Repo: $INFRA_REPO"
echo "  Templates Repo: $TEMPLATES_REPO"
echo ""

# Verificar se repos existem
echo "✅ Verificando repositórios no GitHub..."
gh repo view $GITHUB_ORG/$INFRA_REPO > /dev/null && echo "  ✅ $INFRA_REPO existe" || echo "  ❌ $INFRA_REPO NÃO existe"
gh repo view $GITHUB_ORG/$TEMPLATES_REPO > /dev/null && echo "  ✅ $TEMPLATES_REPO existe" || echo "  ❌ $TEMPLATES_REPO NÃO existe"

# Verificar ArgoCD Application
echo ""
echo "🔄 Verificando ArgoCD Application..."
ARGOCD_REPO=$(kubectl get application infrastructure -n argocd -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "NOT_FOUND")

if [ "$ARGOCD_REPO" = "https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git" ]; then
  echo "  ✅ ArgoCD Application configurado corretamente"
else
  echo "  ⚠️  ArgoCD Application desatualizado!"
  echo "      Esperado: https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git"
  echo "      Atual: $ARGOCD_REPO"
  echo ""
  echo "  🔧 Para corrigir:"
  echo "      kubectl patch application infrastructure -n argocd --type merge -p '{\"spec\":{\"source\":{\"repoURL\":\"https://github.com/${GITHUB_ORG}/${INFRA_REPO}.git\"}}}'"
fi

# Verificar GitHub token
echo ""
echo "🔑 Verificando GitHub Token..."
GITHUB_TOKEN=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.GITHUB_TOKEN}' 2>/dev/null | base64 -d || echo "NOT_FOUND")

if [ "$GITHUB_TOKEN" = "NOT_FOUND" ]; then
  echo "  ❌ GitHub Token NÃO configurado!"
else
  # Testar token
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)
  if [ "$RESPONSE" = "200" ]; then
    echo "  ✅ GitHub Token válido"
  else
    echo "  ❌ GitHub Token inválido (HTTP $RESPONSE)"
  fi
fi

echo ""
echo "✅ Validação concluída!"
```

**Uso:**
```bash
chmod +x scripts/validate-config.sh
./scripts/validate-config.sh
```

---

## 📋 Checklist: Mudei config.yaml, e agora?

Após editar `config.yaml`:

1. **Repositórios GitHub:**
   - [ ] Repos existem com nomes corretos
   - [ ] Repos têm conteúdo (README, estrutura de pastas)

2. **ArgoCD:**
   - [ ] Application aponta para repo correto
   - [ ] Sync está funcionando
   - [ ] `kubectl get application infrastructure -n argocd`

3. **Backstage:**
   - [ ] GitHub token configurado
   - [ ] Templates registrados com URLs corretas
   - [ ] Templates aparecem em "Create"

4. **Testes:**
   - [ ] Criar recurso via template
   - [ ] PR é criado no repo correto
   - [ ] Merge funciona
   - [ ] Crossplane cria recurso

---

## 🎯 Resumo: Você NÃO Precisa Reinstalar

**Se errar configuração:**
- ❌ NÃO precisa rodar `terraform destroy`
- ❌ NÃO precisa rodar `install.sh` novamente
- ✅ Apenas edite `config.yaml`
- ✅ Atualize ArgoCD Application
- ✅ Re-registre templates (se necessário)

**Exceções (quando PRECISA reinstalar):**
- Mudou `cluster_name`
- Mudou `region`
- Mudou VPC ou networking
- Mudou configuração crítica do Terraform

**Repos podem ser corrigidos a qualquer momento sem reinstalar nada!**

---

**Última atualização:** 11 de Dezembro de 2025
