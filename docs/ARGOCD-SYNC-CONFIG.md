# 🔄 Configuração de Auto-Sync do ArgoCD

## ⚙️ Configuração Atual

### Sync Interval (Reconciliation Timeout)

**Localização:** ConfigMap `argocd-cm` no namespace `argocd`

**Valor configurado:** `60s` (1 minuto)

```bash
# Ver valor atual
kubectl -n argocd get configmap argocd-cm -o jsonpath='{.data.timeout\.reconciliation}'

# Deve retornar: 60s
```

### Application SyncPolicy

**Aplicação:** `infrastructure`

```yaml
syncPolicy:
  automated:
    prune: true      # Remove recursos deletados do Git
    selfHeal: true   # Corrige drifts automaticamente
  syncOptions:
    - CreateNamespace=true
```

---

## 🔧 Como Alterar Sync Interval

### Opção 1: Via kubectl (RECOMENDADO)

```bash
# Alterar para 60s (1 minuto)
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"60s"}}'

# Reiniciar controller para aplicar
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-application-controller
```

### Opção 2: Via Helm Values

**Arquivo:** `packages/argo-cd/values.yaml`

```yaml
configs:
  cm:
    timeout.reconciliation: 60s
```

Depois aplicar:
```bash
helm upgrade argocd argo/argo-cd -n argocd -f packages/argo-cd/values.yaml
```

---

## 🎯 Valores Recomendados

| Ambiente | Sync Interval | Motivo |
|----------|---------------|--------|
| **Desenvolvimento** | `30s` | Feedback rápido, muitas mudanças |
| **Staging** | `60s` | Balanceado (padrão atual) ✅ |
| **Produção** | `180s` | Menos carga, mudanças menos frequentes |

**Atual:** 60s (ideal para staging/POC)

---

## 📊 Monitorar Auto-Sync

### Verificar se está funcionando:

```bash
# Ver última sincronização
kubectl -n argocd get application infrastructure -o jsonpath='{.status.sync.status}'
# Deve retornar: Synced

# Ver commit atual
kubectl -n argocd get application infrastructure -o jsonpath='{.status.sync.revision}' | cut -c1-7

# Comparar com GitHub
cd ~/infrastructureidp && git rev-parse HEAD | cut -c1-7

# Devem ser IGUAIS após max 60 segundos de um novo commit
```

### Ver histórico de syncs:

```bash
kubectl -n argocd get application infrastructure -o jsonpath='{.status.history}' | jq
```

---

## 🚨 Troubleshooting

### ArgoCD não detecta mudanças:

1. **Verificar sync interval:**
   ```bash
   kubectl -n argocd get configmap argocd-cm -o jsonpath='{.data.timeout\.reconciliation}'
   ```

2. **Forçar refresh:**
   ```bash
   kubectl -n argocd patch application infrastructure --type merge \
     -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
   ```

3. **Reiniciar repo-server (limpa cache Git):**
   ```bash
   kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server
   ```

4. **Reiniciar controller:**
   ```bash
   kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-application-controller
   ```

### Sync manual forçado:

```bash
# Via kubectl
kubectl -n argocd patch application infrastructure --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":true}}}'
```

---

## ✅ Checklist de Verificação

- [x] Sync interval configurado: `60s`
- [x] Auto-sync habilitado: `automated: true`
- [x] Prune habilitado: `prune: true`
- [x] Self-heal habilitado: `selfHeal: true`
- [x] Application status: `Synced`
- [x] Health status: `Healthy`

**Status:** ✅ Configurado corretamente

---

## 📝 Notas Importantes

### O config.yaml NÃO controla sync interval

O arquivo `/config.yaml` é usado apenas pelo **Terraform** para criar o cluster EKS.

**ArgoCD sync interval** é configurado via:
- ConfigMap `argocd-cm` (depois que ArgoCD está instalado)
- Helm values em `packages/argo-cd/values.yaml`

### Fluxo de detecção:

1. **Backstage cria PR** → GitHub
2. **Você faz merge** → main branch
3. **ArgoCD poll Git** (a cada 60s)
4. **ArgoCD detecta mudança** → OutOfSync
5. **Auto-sync aplica** → Synced
6. **Crossplane provisiona** → AWS

**Tempo total:** ~60-90 segundos do merge até recursos começarem a provisionar

---

**Última atualização:** 11/12/2025
**Configuração aplicada e testada:** ✅
