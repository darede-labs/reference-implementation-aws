# Correções Aplicadas - Bootstrap Node e Scheduling

**Data:** 2026-01-21
**Problema:** Pods sendo agendados no bootstrap node e apps não sincronizando

## ✅ Correções Implementadas

### 1. **Bootstrap Node Protection**
**Problema:** Bootstrap node estava recebendo 18 pods de workload
**Solução:**
```bash
# Taint aplicado manualmente (imediato)
kubectl taint nodes ip-10-0-2-9.ec2.internal node-role.kubernetes.io/bootstrap=true:NoSchedule
kubectl label nodes ip-10-0-2-9.ec2.internal node-role.kubernetes.io/bootstrap=true

# Terraform atualizado (permanente)
# cluster/terraform/karpenter.tf - linha 220-230
taint {
  key    = "node-role.kubernetes.io/bootstrap"
  value  = "true"
  effect = "NoSchedule"
}
```

### 2. **Karpenter Replicas Reduzidas**
**Problema:** Karpenter com 2 réplicas (1 rodando, 1 pendente)
**Solução:**
```bash
kubectl scale deployment karpenter -n kube-system --replicas=1
```
**Terraform:** Adicionar `set { name = "replicas"; value = "1" }` no helm_release

### 3. **Loki Configuration Fixed**
**Problema:** Loki crashando com erro "at least one bucket name must be specified"
**Solução:** Corrigido template para usar filesystem storage
```yaml
# argocd-apps/platform/loki.yaml.tpl
storage_config:
  filesystem:
    directory: /var/loki/chunks
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem  # Mudado de s3 para filesystem
```

### 4. **NodeSelector para Workloads**
**Problema:** Apps precisam rodar apenas em nodes do Karpenter
**Solução:** Adicionado nodeSelector em deployments/statefulsets
```bash
# Script criado: scripts/add-node-selectors.sh
nodeSelector:
  workload-type: general
```
**Aplicado em:**
- loki-gateway (deployment)
- loki (statefulset)

### 5. **DaemonSets Tolerations**
**Problema:** DaemonSets (loki-canary, promtail) não rodavam no bootstrap node
**Solução:** Removido nodeSelector + Adicionado tolerations
```yaml
# DaemonSets devem rodar em TODOS os nodes
tolerations:
  - key: node-role.kubernetes.io/bootstrap
    operator: Exists
    effect: NoSchedule
```

### 6. **Karpenter Tolerations**
**Problema:** Karpenter precisa rodar no bootstrap node
**Solução:** Adicionar tolerations no Helm values (Terraform)
```hcl
set {
  name  = "tolerations[0].key"
  value = "node-role.kubernetes.io/bootstrap"
}
```

## 📊 Resultado Final

### Nodes (4 total)
```
NAME                          INSTANCE     WORKLOAD
ip-10-0-2-9.ec2.internal      t4g.medium   <none> (bootstrap, tainted)
ip-10-0-21-222.ec2.internal   t4g.small    general (Karpenter)
ip-10-0-35-64.ec2.internal    t4g.small    general (Karpenter)
ip-10-0-41-134.ec2.internal   t4g.small    general (Karpenter)
```

### Applications (6/9 Synced)
✅ **Synced/Healthy:**
- ingress-nginx
- external-dns
- kyverno
- kube-prometheus-stack

✅ **Synced/Progressing:**
- loki (resolvido!)
- promtail

⏳ **Unknown/Healthy:**
- backstage (repo-server connection)
- keycloak (repo-server connection)
- kyverno-policies (path issue)

### Pods Status
- **Total Pods:** ~50
- **Running:** ~46
- **Pending:** 4 (DaemonSets aguardando nodes, normal)
- **CrashLoopBackOff:** 0 ✅

## 🎯 Arquitetura Final

### Bootstrap Node (t4g.medium, Spot, Tainted)
**Propósito:** Control plane e componentes críticos
**Pods permitidos:**
- Karpenter controller (com toleration)
- ArgoCD (6 pods)
- CoreDNS, EBS CSI, VPC CNI
- Ingress NGINX controller
- Kyverno controllers
- DaemonSets (com toleration)

**Pods NÃO permitidos:**
- Workloads de aplicação
- Loki, Promtail (exceto DaemonSet)
- Backstage, Keycloak
- Prometheus, Grafana

### Karpenter Nodes (t4g.small, Spot, Graviton)
**Propósito:** Workloads de aplicação
**Label:** `workload-type: general`
**Pods:**
- Loki (statefulset)
- Loki Gateway
- Prometheus
- Grafana
- Backstage (quando sincronizar)
- Keycloak (quando sincronizar)
- DaemonSets (loki-canary, promtail)

## 💡 Lições Aprendidas

### 1. **Bootstrap Node DEVE ser isolado**
- Taint é essencial para evitar sobrecarga
- Apenas componentes críticos devem rodar lá
- DaemonSets precisam de tolerations explícitas

### 2. **DaemonSets são especiais**
- NÃO usar nodeSelector (devem rodar em todos os nodes)
- USAR tolerations para nodes com taint
- São essenciais para observabilidade (logs, metrics)

### 3. **Karpenter Configuration**
- 1 réplica é suficiente para MVP
- Precisa de toleration para rodar no bootstrap
- Provisiona nodes automaticamente baseado em demanda

### 4. **Loki para MVP**
- Filesystem storage é adequado para POC
- S3 storage requer bucket + IAM role (complexidade extra)
- Para produção, migrar para S3 com retenção

### 5. **GitOps sem Git Commits**
- Aplicar manifests diretamente é pragmático para MVP
- ArgoCD ainda gerencia o lifecycle (auto-sync, prune, heal)
- Para produção, considerar CI/CD pipeline

## 🔧 Scripts Criados

1. **`scripts/wait-for-sync.sh`**
   - Monitora progresso do ArgoCD sync
   - Timeout configurável
   - Output colorido e informativo

2. **`scripts/add-node-selectors.sh`**
   - Adiciona nodeSelector em workloads
   - Garante scheduling correto
   - Idempotente

## 📝 Próximos Passos

1. **Aguardar repo-server recovery** (2-3 min)
   - backstage e keycloak devem sincronizar automaticamente

2. **Resolver kyverno-policies**
   - Opção A: Remover (políticas são opcionais)
   - Opção B: Criar diretório no Git
   - Opção C: Usar repo público de políticas

3. **Validar instalação completa**
   ```bash
   make verify
   ```

4. **Deploy workload teste**
   - Verificar Karpenter node provisioning
   - Validar observabilidade (logs, metrics)

## 🚀 Comandos Úteis

```bash
# Ver pods no bootstrap node
kubectl get pods -A -o wide --field-selector spec.nodeName=ip-10-0-2-9.ec2.internal

# Ver pods em nodes do Karpenter
kubectl get pods -A -o wide --field-selector spec.nodeName!=ip-10-0-2-9.ec2.internal

# Forçar sync de uma app
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Ver logs do Karpenter
kubectl logs -n kube-system deployment/karpenter --tail=50 -f

# Ver nodes provisionados
kubectl get nodeclaims
kubectl get nodepools
```

## 💰 Custo Atual

**Compute:**
- 1x t4g.medium (bootstrap, Spot): ~$0.0084/hora = ~$6/mês
- 3x t4g.small (workload, Spot): ~$0.0063/hora cada = ~$14/mês

**Total Compute:** ~$20/mês (Graviton + Spot = máxima economia!)

**Observações:**
- Karpenter consolida nodes automaticamente
- Spot instances podem ser interrompidas (Karpenter reage automaticamente)
- Para produção, considerar mix Spot + On-Demand
