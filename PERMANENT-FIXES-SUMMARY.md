# Correções Permanentes Aplicadas

**Data:** 2026-01-21
**Objetivo:** Corrigir scheduling de pods e garantir persistência das configurações

## ❌ Problemas com Patches (NÃO PERSISTEM)

Os seguintes comandos foram executados mas **NÃO persistem** após reinstalação:
```bash
kubectl patch daemonset loki-canary ...
kubectl patch daemonset promtail ...
kubectl scale deployment karpenter --replicas=1 ...
kubectl taint nodes ...
```

## ✅ Correções Permanentes Aplicadas

### 1. **Bootstrap Node Taint (Terraform)**
**Arquivo:** `cluster/terraform/karpenter.tf` (linhas 220-230)

```hcl
labels = {
  role                                = "karpenter-bootstrap"
  "karpenter.sh/discovery"            = module.eks.cluster_name
  "node-role.kubernetes.io/bootstrap" = "true"
}

# CRITICAL: Taint to prevent workload pods from scheduling on bootstrap node
taint {
  key    = "node-role.kubernetes.io/bootstrap"
  value  = "true"
  effect = "NoSchedule"
}
```

**Status:** ✅ Aplicado no Terraform
**Efeito:** Bootstrap node não receberá workloads após próxima instalação

---

### 2. **Loki Storage Configuration**
**Arquivo:** `argocd-apps/platform/loki.yaml.tpl` (linhas 34-44)

```yaml
storage_config:
  filesystem:
    directory: /var/loki/chunks
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem  # Mudado de s3
      schema: v13
```

**Status:** ✅ Aplicado no template
**Efeito:** Loki usa filesystem, não S3 (adequado para MVP)

---

### 3. **Loki Canary Tolerations**
**Arquivo:** `argocd-apps/platform/loki.yaml.tpl` (linhas 82-87)

```yaml
lokiCanary:
  enabled: true
  # CRITICAL: DaemonSet must tolerate bootstrap node taint
  tolerations:
    - key: node-role.kubernetes.io/bootstrap
      operator: Exists
      effect: NoSchedule
```

**Status:** ✅ Aplicado no template
**Efeito:** loki-canary DaemonSet roda em todos os nodes

---

### 4. **Promtail Tolerations**
**Arquivo:** `argocd-apps/platform/promtail.yaml` (linhas 50-53)

```yaml
# CRITICAL: DaemonSets must run on ALL nodes including bootstrap
tolerations:
  - key: node-role.kubernetes.io/bootstrap
    operator: Exists
    effect: NoSchedule
```

**Status:** ✅ Aplicado no arquivo
**Efeito:** promtail DaemonSet roda em todos os nodes

---

### 5. **Loki SingleBinary NodeSelector**
**Arquivo:** `argocd-apps/platform/loki.yaml.tpl` (linhas 60-63)

```yaml
singleBinary:
  replicas: 1
  # ... outras configs ...
  # Evita agendamento no bootstrap node
  nodeSelector:
    workload-type: general
  tolerations: []
```

**Status:** ✅ Aplicado no template
**Efeito:** Loki StatefulSet roda apenas em nodes do Karpenter

---

## ⚠️ Correções PENDENTES (Precisam ser aplicadas no Terraform)

### 1. **Karpenter Replicas**
**Arquivo:** `cluster/terraform/karpenter.tf`
**Adicionar:**

```hcl
# CRITICAL: Set replicas to 1 (not 2)
set {
  name  = "replicas"
  value = "1"
}
```

**Status:** ⚠️ NÃO aplicado ainda
**Ação:** Adicionar no `helm_release.karpenter`

---

### 2. **Karpenter Tolerations**
**Arquivo:** `cluster/terraform/karpenter.tf`
**Adicionar:**

```hcl
# CRITICAL: Tolerate bootstrap taint
set {
  name  = "tolerations[0].key"
  value = "node-role.kubernetes.io/bootstrap"
}

set {
  name  = "tolerations[0].operator"
  value = "Exists"
}

set {
  name  = "tolerations[0].effect"
  value = "NoSchedule"
}
```

**Status:** ⚠️ NÃO aplicado ainda
**Ação:** Adicionar no `helm_release.karpenter`

---

## 📊 Status Atual

### ✅ Funcionando
- Loki: Running (1/1)
- Promtail: 4 DaemonSet pods (tolerations corretas)
- Loki-canary: 6 DaemonSet pods (tolerations corretas)
- Bootstrap node: Tainted (via kubectl, precisa Terraform)

### ⚠️ Pendentes
- Karpenter: 1 réplica (via kubectl scale, precisa Terraform)
- Backstage: Namespace criado, manifestos aplicados (helm-values tem erro)
- Keycloak: Namespace criado, manifestos aplicados (helm-values tem erro)

### ❌ Problemas Conhecidos
1. **helm-values.yaml não são manifestos Kubernetes**
   - `platform/backstage/helm-values.yaml`
   - `platform/keycloak/helm-values.yaml`
   - São valores para Helm charts, não para `kubectl apply`

2. **Variáveis não renderizadas em platform/**
   - Arquivos em `platform/` têm templates `{{ variable }}`
   - Precisam ser renderizados antes de `kubectl apply`
   - Ou devem ser gerenciados via Helm/ArgoCD

---

## 🎯 Próximas Ações Necessárias

### 1. Aplicar Correções no Terraform
```bash
# Editar cluster/terraform/karpenter.tf
# Adicionar:
# - set { name = "replicas"; value = "1" }
# - tolerations para bootstrap node

# Aplicar
cd cluster/terraform
terraform apply
```

### 2. Corrigir Backstage/Keycloak
**Opção A:** Gerenciar via Helm (recomendado)
```bash
# Instalar via Helm diretamente
helm install backstage ./packages/backstage-custom -f platform/backstage/helm-values.yaml
helm install keycloak codecentric/keycloak -f platform/keycloak/helm-values.yaml
```

**Opção B:** Remover helm-values.yaml de platform/
```bash
# Mover para packages/ ou remover
mv platform/backstage/helm-values.yaml packages/backstage/
mv platform/keycloak/helm-values.yaml packages/keycloak/
```

### 3. Validar Instalação Limpa
```bash
make clean
make terraform
make bootstrap
make verify
```

---

## 💡 Lições Aprendidas

### 1. **kubectl patch NÃO persiste**
- Sempre modificar arquivos fonte (Terraform, YAML templates)
- Patches são apenas para debugging/testes

### 2. **DaemonSets são especiais**
- Devem rodar em TODOS os nodes
- Precisam de tolerations para taints
- NÃO usar nodeSelector (exceto casos específicos)

### 3. **Helm values != Kubernetes manifests**
- `helm-values.yaml` não pode ser aplicado com `kubectl apply`
- Precisa ser usado com `helm install/upgrade`
- Ou gerenciado via ArgoCD Helm Application

### 4. **Templates precisam ser renderizados**
- Arquivos `.tpl` são templates
- Precisam de `render-templates.sh` antes de uso
- Ou gerenciados via ArgoCD (que renderiza automaticamente)

---

## 📝 Checklist de Instalação Limpa

- [ ] Terraform: Bootstrap node com taint
- [ ] Terraform: Karpenter com 1 réplica
- [ ] Terraform: Karpenter com tolerations
- [ ] Templates: Loki com filesystem storage
- [ ] Templates: Loki-canary com tolerations
- [ ] Templates: Promtail com tolerations
- [ ] Templates: Loki singleBinary com nodeSelector
- [ ] Backstage: Instalado via Helm ou ArgoCD
- [ ] Keycloak: Instalado via Helm ou ArgoCD
- [ ] Validação: `make verify` passa

---

## 🚀 Comando para Aplicar Tudo

```bash
# 1. Atualizar Terraform
cd cluster/terraform
# (Editar karpenter.tf manualmente)
terraform apply

# 2. Re-renderizar templates
cd ../..
./scripts/render-templates.sh

# 3. Aplicar via ArgoCD
kubectl apply -f argocd-apps/platform/loki.yaml
kubectl apply -f argocd-apps/platform/promtail.yaml

# 4. Aguardar sync
./scripts/wait-for-sync.sh 300
```
