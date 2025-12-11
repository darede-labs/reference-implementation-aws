# Changelog - Darede Labs Edition

## 🎯 Objetivo das Mudanças

Tornar a instalação 100% automatizada, compatível com SCPs restritivas, e completamente reproduzível sem intervenção manual.

## 📝 Mudanças Implementadas

### 1. Configuração IAM Dual (IRSA + Pod Identity)

#### Arquivos Modificados:
- `config.yaml` - Adicionado `iam_auth_method: "irsa"`
- `cluster/terraform/locals.tf` - Lógica para detectar método IAM
- `cluster/terraform/main.tf` - Suporte dual IRSA e Pod Identity
- `cluster/terraform/outputs.tf` - Outputs do método IAM e ARN do role

#### Mudança:
```terraform
# Antes: Apenas Pod Identity
module "external_secrets_pod_identity" { ... }

# Depois: Dual support
module "external_secrets_pod_identity" {
  count = local.use_pod_identity ? 1 : 0
  ...
}

module "external_secrets_irsa" {
  count = local.use_irsa ? 1 : 0
  ...
}
```

**Benefício:** Compatibilidade com SCPs que bloqueiam assumed roles do Pod Identity.

---

### 2. Cluster Secret Direto (Workaround SCP)

#### Arquivos Criados:
- `packages/argo-cd/manifests/hub-cluster-secret-direct.yaml` (NOVO)

#### Arquivos Modificados:
- `scripts/install.sh` - Geração e aplicação do secret

#### Mudança:
```bash
# Antes: Dependia de External Secrets + Secrets Manager
kubectl apply -f hub-cluster-secret.yaml  # ExternalSecret

# Depois: Criado diretamente do config.yaml
# 1. Lê config.yaml
# 2. Substitui placeholders no template
# 3. Aplica secret diretamente no Kubernetes
```

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hub-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: control-plane
    path_routing: "${PATH_ROUTING}"
    auto_mode: "${AUTO_MODE}"  # ← Label crítica para ApplicationSets
  annotations:
    domain: "${DOMAIN}"  # ← Annotation crítica para ingress URLs
    route53_hosted_zone_id: "${ROUTE53_HOSTED_ZONE_ID}"
    # ... outras annotations necessárias
```

**Benefício:** Zero dependência do Secrets Manager, funciona com qualquer SCP.

---

### 3. Auto-Sync Habilitado por Padrão

#### Arquivos Modificados:
- `packages/appset-chart/values.yaml`

#### Mudança:
```yaml
# Antes:
syncPolicy:
  automated:
    selfHeal: false
    prune: false

# Depois:
syncPolicy:
  automated:
    selfHeal: true
    prune: true
```

**Benefício:** Applications sincronizam automaticamente, sem intervenção manual.

---

### 4. Auto-Confirmação em Scripts

#### Arquivos Modificados:
- `scripts/utils.sh` - Suporte `AUTO_CONFIRM=yes` em todos prompts

#### Mudança:
```bash
# Antes:
read -p '(yes/no): ' response
if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
  exit 0
fi

# Depois:
if [[ "${AUTO_CONFIRM}" == "yes" ]]; then
  echo "✅ Auto-confirmed"
  response="yes"
else
  read -p '(yes/no): ' response
fi
```

**Uso:**
```bash
export AUTO_CONFIRM=yes
./scripts/install.sh  # Sem prompts!
```

**Benefício:** Instalação totalmente automatizada, ideal para CI/CD.

---

### 5. IRSA Support em External Secrets

#### Arquivos Modificados:
- `scripts/install.sh` - Detecção e configuração IRSA

#### Mudança:
```bash
# Detecta método IAM do Terraform output
IAM_AUTH_METHOD=$(yq '.iam_auth_method' ${CONFIG_FILE})

if [[ "${IAM_AUTH_METHOD}" == "irsa" ]]; then
  ROLE_ARN=$(terraform output -raw external_secrets_role_arn)

  # Adiciona annotation ao ServiceAccount do External Secrets
  cat <<EOF >> "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "${ROLE_ARN}"
EOF
fi
```

**Benefício:** External Secrets funciona com IRSA automaticamente.

---

### 6. AWS Profile Support Completo

#### Arquivos Modificados:
- `scripts/utils.sh`
- `scripts/create-config-secrets.sh`
- `scripts/create-cluster.sh`

#### Mudança:
```bash
# Antes:
aws eks update-kubeconfig --region $AWS_REGION ...

# Depois:
aws eks update-kubeconfig ${AWS_PROFILE:+--profile $AWS_PROFILE} --region $AWS_REGION ...
```

**Aplicado em TODOS comandos AWS CLI:**
- `aws sts get-caller-identity`
- `aws eks update-kubeconfig`
- `aws secretsmanager create-secret`
- `aws iam create-policy`
- etc.

**Benefício:** Funciona perfeitamente com AWS SSO e múltiplos profiles.

---

## 📊 Resumo das Mudanças

| Componente | Arquivos Modificados | Arquivos Criados | Linhas Modificadas |
|------------|---------------------|------------------|-------------------|
| Terraform | 3 | 0 | ~100 |
| Scripts | 4 | 0 | ~80 |
| Manifestos | 1 | 2 | ~50 |
| Documentação | 1 | 2 | ~300 |
| **TOTAL** | **9** | **4** | **~530** |

## 🎯 Resultado Final

### Antes:
- ❌ Requer intervenção manual para labels/annotations
- ❌ Depende de Secrets Manager (bloqueado por SCP)
- ❌ Prompts interativos impedem automação
- ❌ Auto-sync desabilitado (Applications ficam OutOfSync)
- ❌ Não funciona com AWS SSO profiles consistentemente

### Depois:
- ✅ 100% automatizado, zero intervenção manual
- ✅ Funciona com qualquer SCP (não depende de Secrets Manager)
- ✅ `AUTO_CONFIRM=yes` para CI/CD
- ✅ Auto-sync habilitado (Applications sempre sincronizadas)
- ✅ Suporte completo AWS SSO e múltiplos profiles
- ✅ Suporte dual IRSA e Pod Identity
- ✅ Reproduzível e idempotente
- ✅ Configuração centralizada em `config.yaml`

## 🔄 Processo de Instalação

### Antes:
```bash
1. terraform apply
2. ./scripts/install.sh
3. [Digitar "yes" manualmente]
4. [Aguardar erro de External Secrets]
5. kubectl create secret hub-cluster-secret ...  # Manual!
6. kubectl label secret ...  # Manual!
7. kubectl annotate secret ...  # Manual!
8. kubectl patch application ... --type merge  # Manual!
9. [Repetir para cada application]
```

### Depois:
```bash
1. terraform apply -auto-approve
2. AUTO_CONFIRM=yes ./scripts/install.sh
   # FIM! Tudo automático.
```

## 📖 Documentação Criada

1. **`docs/SCP-WORKAROUND.md`** - Solução completa para SCPs
2. **`docs/GUIA-USO-PLATAFORMA.md`** - Guia completo de uso e validação
3. **`docs/CORRECOES-CICLO1.md`** - Correções identificadas no ciclo 1
4. **`CHANGELOG-DAREDE.md`** - Este arquivo
5. **`README.md`** - Atualizado com melhorias

## 🐛 Correções Pós-Deploy (Ciclo 1)

### ✅ Label `clusterName` Faltante
**Problema:** AWS Load Balancer Controller ApplicationSet não gerava Application.
**Causa:** Hub cluster secret não tinha label `clusterName`.
**Correção:** Adicionado `clusterName: "${CLUSTER_NAME}"` em `hub-cluster-secret-direct.yaml`.

### ✅ Ingress NGINX Deployment Não Criado
**Problema:** Service existia mas Deployment não era criado.
**Causa:**
1. AWS Load Balancer Controller ausente (necessário para NLB)
2. ArgoCD sync travado em deadlock

**Correção:** Com AWS LB Controller instalado, ingress-nginx funciona corretamente.

## 🧪 Testado e Validado

- ✅ Ciclo completo deploy
- ✅ Com `AUTO_CONFIRM`
- ✅ IRSA funcionando
- ✅ Com SCPs restritivas (workaround implementado)
- ✅ Múltiplos AWS profiles (SSO)
- ✅ AWS Load Balancer Controller
- ✅ Ingress NGINX com NLB
- ✅ ArgoCD, Cert Manager, Crossplane, External Secrets/DNS
- ⏳ Keycloak, Backstage, Argo Workflows (em validação)

## 🚀 Próximos Passos Sugeridos

1. ✅ **Implementado** - Suporte IRSA
2. ✅ **Implementado** - Cluster secret direto
3. ✅ **Implementado** - Auto-confirmação
4. ✅ **Implementado** - Auto-sync
5. 🔜 **Futuro** - Detecção automática de SCP e fallback
6. 🔜 **Futuro** - Modo híbrido (Secrets Manager quando disponível)
7. 🔜 **Futuro** - Criptografia de valores sensíveis no config.yaml

---

**Mantido por:** Darede Labs
**Versão:** 1.0.0-darede
**Data:** 2025-12-10
