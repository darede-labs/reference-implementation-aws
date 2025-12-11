# Correções Implementadas - Ciclo 1

## 🔍 Problemas Encontrados e Corrigidos

### 1. ❌ AWS Load Balancer Controller Não Gerado
**Problema:** ApplicationSet não gerava Application do AWS Load Balancer Controller.

**Causa Raiz:** Hub cluster secret não tinha label `clusterName`.

**Solução:**
```bash
kubectl label secret hub-cluster-secret -n argocd clusterName=idp-poc-cluster
```

**Status:** ✅ CORRIGIDO - AWS Load Balancer Controller instalado e rodando.

---

### 2. ❌ Ingress NGINX Deployment Não Criado
**Problema:** Ingress NGINX Service existia mas Deployment não estava sendo criado.

**Causa Raiz 1:** AWS Load Balancer Controller ausente (necessário para `loadBalancerClass: service.k8s.aws/nlb`).

**Causa Raiz 2:** ArgoCD sync travado esperando Service ficar healthy antes de criar Deployment (deadlock).

**Solução:**
1. Instalado AWS Load Balancer Controller (via correção #1)
2. Deletado Service órfão
3. Instalado manualmente via Helm

```bash
kubectl delete svc ingress-nginx-controller -n ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.7.0 \
  --values packages/ingress-nginx/values.yaml
```

**Status:** ✅ CORRIGIDO - Ingress NGINX rodando com Load Balancer provisionado.

**Load Balancer DNS:** `cnoe-5321b8e8238096ee.elb.us-east-1.amazonaws.com`

---

### 3. ⏳ Applications OutOfSync (Keycloak, Backstage, Argo Workflows)
**Problema:** Applications ficam OutOfSync e não sincronizam automaticamente.

**Causa Potencial:** Auto-sync não está funcionando corretamente ou há dependências não resolvidas.

**Status:** ⏳ EM INVESTIGAÇÃO

---

## 🔧 Mudanças Necessárias no Código

### 1. Hub Cluster Secret - Adicionar Label `clusterName`

**Arquivo:** `packages/argo-cd/manifests/hub-cluster-secret-direct.yaml`

**Mudança:**
```yaml
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: control-plane
    path_routing: "${PATH_ROUTING}"
    auto_mode: "${AUTO_MODE}"
    clusterName: "${CLUSTER_NAME}"  # ← ADICIONAR ESTA LINHA
```

### 2. Script de Instalação - Adicionar Label ao Aplicar Secret

**Arquivo:** `scripts/install.sh`

Já gera o secret mas precisa garantir que a label `clusterName` seja aplicada.

---

## 📊 Status Atual dos Componentes

| Componente | Status | Pods | Observações |
|------------|--------|------|-------------|
| **ArgoCD** | ✅ Healthy | 6/6 Running | Core funcionando |
| **AWS LB Controller** | ✅ Healthy | 2/2 Running | Instalado com sucesso |
| **Ingress NGINX** | ✅ Healthy | 1/1 Running | Load Balancer provisionado |
| **Cert Manager** | ✅ Healthy | 3/3 Running | Funcionando |
| **Crossplane** | ✅ Healthy | 5/5 Running | Funcionando |
| **External Secrets** | ✅ Healthy | 3/3 Running | Funcionando (IRSA) |
| **External DNS** | ✅ Healthy | 1/1 Running | Funcionando |
| **Keycloak** | ⏳ OutOfSync | 0 | Aguardando sync |
| **Backstage** | ⏳ OutOfSync | 0 | Aguardando sync |
| **Argo Workflows** | ⏳ OutOfSync | 0 | Aguardando sync |

---

## 🎯 Próximos Passos

1. ✅ Atualizar código com label `clusterName`
2. ⏳ Investigar e corrigir sync de Keycloak/Backstage/Argo Workflows
3. ⏳ Validar acesso via port-forward
4. ⏳ Configurar DNS no Route53
5. ⏳ Testar funcionalidades da plataforma
6. ⏳ Executar 2 ciclos destroy/apply

---

## 📝 Comandos Úteis Para Troubleshooting

```bash
# Ver status de todas applications
kubectl get applications -n argocd

# Ver logs do ApplicationSet controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100

# Forçar sync de uma application
kubectl -n argocd patch application <name> --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'

# Ver labels do hub-cluster-secret
kubectl get secret hub-cluster-secret -n argocd -o jsonpath='{.metadata.labels}' | jq .

# Ver Load Balancer DNS
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

**Data:** 2025-12-10
**Autor:** Validação Ciclo 1
