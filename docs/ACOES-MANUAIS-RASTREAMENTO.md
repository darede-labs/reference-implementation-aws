# 📝 Rastreamento de Ações Manuais - Ciclo 1

Este documento rastreia TODAS as ações manuais realizadas para fazer a plataforma funcionar, para depois serem automatizadas no código.

---

## 1️⃣ Label `clusterName` no Hub Cluster Secret

**Data:** 2025-12-10 09:50
**Problema:** AWS Load Balancer Controller ApplicationSet não gerava Application
**Causa:** Faltava label `clusterName` no hub-cluster-secret

**Ação Manual:**
```bash
kubectl label secret hub-cluster-secret -n argocd clusterName=idp-poc-cluster --overwrite
```

**Código Ajustado:** ✅ FEITO
- Arquivo: `packages/argo-cd/manifests/hub-cluster-secret-direct.yaml`
- Adicionado: `clusterName: "${CLUSTER_NAME}"` nas labels

---

## 2️⃣ Instalação Manual do Ingress NGINX

**Data:** 2025-12-10 09:55
**Problema:** Ingress NGINX Deployment não era criado pelo ArgoCD (sync travado)
**Causa:** Service existente sem annotations do Helm impedia instalação

**Ação Manual:**
```bash
kubectl delete svc ingress-nginx-controller -n ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.7.0 \
  --values packages/ingress-nginx/values.yaml
```

**Código a Ajustar:**
- ⏳ Investigar por que ArgoCD não consegue criar automaticamente
- Possível solução: Sync hooks ou dependências melhor configuradas

---

## 3️⃣ Secrets Manuais para Keycloak e Backstage

**Data:** 2025-12-10 10:02
**Problema:** ExternalSecrets falhavam devido SCP bloqueando Secrets Manager
**Causa:** SCP com explicit deny em assumed roles

**Ação Manual:**
```bash
# Keycloak Secret
kubectl create secret generic keycloak-config -n keycloak \
  --from-literal=password="keycloak-postgres-pass-12345" \
  --from-literal=POSTGRES_PASSWORD="keycloak-postgres-pass-12345" \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD="cnoe-admin"

# Backstage Secret
kubectl create secret generic backstage-secrets -n backstage \
  --from-literal=POSTGRES_PASSWORD="backstage-postgres-pass-12345" \
  --from-literal=BACKEND_SECRET="backstage-backend-secret-12345" \
  --from-literal=GITHUB_TOKEN="ghp_dummy_token"
```

**Código a Ajustar:**
- ⏳ Gerar esses secrets automaticamente no `scripts/install.sh`
- ⏳ Alternativa: Usar generator de senhas do Kubernetes ou helmvalues

---

## 4️⃣ Instalação Manual do Keycloak via Helm

**Data:** 2025-12-10 10:05
**Problema:** ArgoCD não conseguia sincronizar devido a webhook do ingress-nginx
**Causa:** Certificado do webhook inválido + dependência de ExternalSecret

**Ação Manual:**
```bash
helm upgrade --install keycloak bitnami/keycloak \
  --namespace keycloak \
  --set auth.adminUser=cnoe-admin \
  --set auth.existingSecret=keycloak-config \
  --set auth.passwordSecretKey=KEYCLOAK_ADMIN_PASSWORD \
  --set postgresql.auth.existingSecret=keycloak-config \
  --set postgresql.auth.secretKeys.userPasswordKey=password \
  --set ingress.enabled=false
```

**Código a Ajustar:**
- ⏳ Corrigir webhook do ingress-nginx
- ⏳ Desabilitar dependência de ExternalSecret nas applications

---

## 5️⃣ Escalonamento do Node Group

**Data:** 2025-12-10 10:09
**Problema:** Pods em Pending com erro "Too many pods"
**Causa:** Cluster com apenas 2 nodes t3.medium sem recursos suficientes

**Ação Manual:**
```bash
aws eks update-nodegroup-config \
  --cluster-name idp-poc-cluster \
  --nodegroup-name nodes-20251210121232304600000023 \
  --scaling-config minSize=3,maxSize=6,desiredSize=4 \
  --region us-east-1 \
  --profile darede
```

**Código a Ajustar:** ✅ EM PROGRESSO
- Arquivo: `config.yaml`
- Mudança: `desired_size: 2` → `desired_size: 4`
- Alternativa: Ajustar requests/limits dos pods

---

## 6️⃣ Instalação Manual do Backstage via Helm

**Data:** 2025-12-10 10:06 (tentativa)
**Status:** ⏳ Aguardando recursos

**Ação Manual (planejada):**
```bash
helm upgrade --install backstage backstage/backstage \
  --namespace backstage \
  --values packages/backstage/values.yaml \
  --set ingress.enabled=false
```

**Código a Ajustar:**
- ⏳ Mesmo que Keycloak - desabilitar ExternalSecret

---

## 7️⃣ Instalação Manual do Argo Workflows via Helm

**Data:** 2025-12-10 10:06 (tentativa)
**Status:** ⏳ Aguardando recursos

**Ação Manual (planejada):**
```bash
helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo \
  --values packages/argo-workflows/values.yaml \
  --set ingress.enabled=false
```

**Código a Ajustar:**
- ⏳ Verificar se há dependência de ExternalSecret

---

## 📋 Checklist de Ajustes no Código

### Imediatos (Críticos)
- [x] Label `clusterName` no hub-cluster-secret
- [x] Desired nodes: 2 → 4 no config.yaml
- [x] Keycloak values.yaml com imagens bitnamilegacy
- [x] Keycloak extraEnvVars com KEYCLOAK_ADMIN
- [x] PostgreSQL com imagem digest correta
- [x] Remover dependência de existingSecret
- [x] Backstage PostgreSQL com bitnamilegacy

### Médio Prazo
- [ ] Gerar secrets dinamicamente no install.sh (opcional)
- [ ] Corrigir webhook ingress-nginx ou usar skip-validation
- [ ] Criar ingresses automaticamente no install.sh
- [ ] Testar sync automático após correções

### Longo Prazo
- [ ] Detectar automaticamente se SCP bloqueia Secrets Manager
- [ ] Fallback automático para secrets diretos
- [ ] Resource requests/limits otimizados

---

## 🎯 Status Atual

| Componente | Manual Install | Pods Running | Observações |
|------------|---------------|--------------|-------------|
| Hub Secret | ✅ | - | Label adicionada |
| AWS LB Ctrl | ✅ | 2/2 | Funcionando |
| Ingress NGINX | ✅ | 1/1 | Load Balancer OK |
| Keycloak | ⏳ | 0/1 Pending | Aguarda recursos |
| Backstage | ⏳ | 0/1 Pending | Aguarda recursos |
| Argo Workflows | ✅ | 2/2 | Funcionando |

**Aguardando:** Escalonamento de nodes (2 → 4) completar

---

**Última atualização:** 2025-12-10 10:38
**Próxima ação:** Validar todos pods Running + Criar ingresses + Testar HTTPS completo
