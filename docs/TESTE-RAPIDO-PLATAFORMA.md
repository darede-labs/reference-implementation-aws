# 🧪 Teste Rápido da Plataforma - 10 Minutos

## ✅ Pré-requisitos

```bash
export AWS_PROFILE=darede
kubectl cluster-info
```

---

## 1️⃣ Testar ArgoCD (ESSENCIAL)

### Obter Senha Admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

**Copie a senha!**

### Port-Forward

Em um terminal separado (deixe rodando):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Acessar

1. Abra: https://localhost:8080
2. Aceite certificado auto-assinado
3. Login:
   - Username: `admin`
   - Password: [senha do passo anterior]

### Validar

- [ ] Conseguiu fazer login?
- [ ] Vê lista de Applications?
- [ ] Quantas Applications estão Synced vs OutOfSync?

**Screenshot recomendado:** Tire print da tela de Applications!

---

## 2️⃣ Verificar Components Core

```bash
# Ver todas applications
kubectl get applications -n argocd

# Ver pods de todos namespaces
kubectl get pods -A | grep -v "Completed" | grep -v "Running" || echo "✅ Todos pods Running!"

# Ver Load Balancer DNS
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo
```

### Checklist

- [ ] AWS Load Balancer Controller: Synced/Healthy?
- [ ] Ingress NGINX: Healthy?
- [ ] Load Balancer DNS apareceu?

---

## 3️⃣ Sincronizar Applications OutOfSync (via ArgoCD UI)

No ArgoCD UI (https://localhost:8080):

1. Para cada Application **OutOfSync**:
   - Clique na Application
   - Clique em **SYNC** (botão azul no topo)
   - Marque **PRUNE** e **DRY RUN** (desmarque depois)
   - Clique em **SYNCHRONIZE**
   - Aguarde status **Synced**

2. Applications para sincronizar:
   - [ ] keycloak-in-cluster
   - [ ] backstage-in-cluster
   - [ ] argo-workflows-in-cluster
   - [ ] argocd-in-cluster (sync do próprio ArgoCD)

---

## 4️⃣ Validar Keycloak

Após sync completo:

```bash
# Aguardar pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# Port-forward
kubectl port-forward svc/keycloak -n keycloak 8090:80
```

Acessar: http://localhost:8090

- Username: `cnoe-admin`
- Password: `cnoe-admin`

### Checklist
- [ ] Página de login carrega?
- [ ] Consegue fazer login?
- [ ] Vê Admin Console?

---

## 5️⃣ Validar Backstage

```bash
# Aguardar pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=300s

# Port-forward
kubectl port-forward svc/backstage -n backstage 7007:7007
```

Acessar: http://localhost:7007

### Checklist
- [ ] Página inicial carrega?
- [ ] Vê catálogo?
- [ ] Templates disponíveis?

---

## 6️⃣ Validar Argo Workflows

```bash
# Aguardar pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argo-workflows-server -n argo --timeout=300s

# Port-forward
kubectl port-forward svc/argo-workflows-server -n argo 2746:2746
```

Acessar: https://localhost:2746

### Checklist
- [ ] Página carrega?
- [ ] Vê lista de workflows?

---

## 7️⃣ Testar Criação de Recurso (Exemplo Simples)

### Criar um teste nginx via ArgoCD

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-nginx
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 15.4.4
  destination:
    server: https://kubernetes.default.svc
    namespace: test
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

### Validar

```bash
# Ver application
kubectl get application test-nginx -n argocd

# Aguardar sync
sleep 30

# Ver pods do teste
kubectl get pods -n test

# Ver service
kubectl get svc -n test
```

### Limpar Teste

```bash
kubectl delete application test-nginx -n argocd
kubectl delete namespace test
```

### Checklist
- [ ] Application criada?
- [ ] Pod nginx rodando?
- [ ] Service criado?

---

## 8️⃣ Validar DNS e Load Balancer

### Obter DNS do Load Balancer

```bash
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Load Balancer DNS: $LB_DNS"
```

### Testar Conectividade

```bash
# Teste HTTP (deve responder "404 Not Found" do nginx)
curl -I http://$LB_DNS

# Deve retornar algo como:
# HTTP/1.1 404 Not Found
# Server: nginx
```

### Checklist
- [ ] Load Balancer responde?
- [ ] Retorna resposta do NGINX?

---

## 9️⃣ Configurar DNS no Route53 (Opcional)

### Via AWS Console

1. Acesse Route53 → Hosted Zones → `timedevops.click`
2. Criar CNAME records:
   ```
   argocd.timedevops.click     → [LB_DNS]
   backstage.timedevops.click  → [LB_DNS]
   keycloak.timedevops.click   → [LB_DNS]
   ```

### Via CLI

```bash
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
HOSTED_ZONE_ID="Z09212782MXWNY5EYNICO"

# Criar CNAMEs
for subdomain in argocd backstage keycloak; do
  aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch '{
      "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "'$subdomain'.timedevops.click",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [{"Value": "'$LB_DNS'"}]
        }
      }]
    }' --profile darede
done
```

### Testar DNS (após 5-10 minutos)

```bash
nslookup argocd.timedevops.click
curl -I http://argocd.timedevops.click
```

---

## 🔟 Validar Ingresses

```bash
# Ver todos ingresses
kubectl get ingress -A

# Ver detalhes do ingress do ArgoCD (se existir)
kubectl describe ingress -n argocd
```

### Checklist
- [ ] Ingresses criados para ArgoCD, Backstage, Keycloak?
- [ ] Hosts configurados corretamente?

---

## ✅ Checklist Final de Validação

### Core Components
- [ ] ArgoCD acessível e funcionando
- [ ] AWS Load Balancer Controller instalado
- [ ] Ingress NGINX com Load Balancer provisionado
- [ ] Cert Manager instalado
- [ ] Crossplane instalado
- [ ] External Secrets funcionando (IRSA)
- [ ] External DNS instalado

### Applications
- [ ] Keycloak instalado e acessível
- [ ] Backstage instalado e acessível
- [ ] Argo Workflows instalado e acessível

### Network
- [ ] Load Balancer DNS resolvendo
- [ ] Ingresses criados
- [ ] DNS configurado no Route53 (opcional)

### Testes
- [ ] Conseguiu criar Application de teste
- [ ] Pod de teste rodando
- [ ] Cleanup funcionou

---

## 📊 Comando de Status Completo

```bash
#!/bin/bash
echo "=== CLUSTER ==="
kubectl get nodes -o wide

echo -e "\n=== APPLICATIONS ==="
kubectl get applications -n argocd

echo -e "\n=== PODS PROBLEMÁTICOS ==="
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAMESPACE"

echo -e "\n=== LOAD BALANCER ==="
kubectl get svc -n ingress-nginx ingress-nginx-controller

echo -e "\n=== INGRESSES ==="
kubectl get ingress -A

echo -e "\n=== RESUMO ==="
echo "Applications Synced: $(kubectl get applications -n argocd -o json | jq '[.items[] | select(.status.sync.status=="Synced")] | length')"
echo "Applications Total: $(kubectl get applications -n argocd -o json | jq '.items | length')"
echo "Pods Running: $(kubectl get pods -A --no-headers | grep Running | wc -l | xargs)"
echo "Pods Total: $(kubectl get pods -A --no-headers | wc -l | xargs)"
```

---

## 🆘 Troubleshooting Rápido

### Application OutOfSync?
```bash
# Forçar sync via CLI
kubectl -n argocd patch application <name> --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
```

### Pod CrashLoopBackOff?
```bash
kubectl logs -n <namespace> <pod-name> --tail=50
kubectl describe pod -n <namespace> <pod-name>
```

### Load Balancer não provisiona?
```bash
# Ver logs do AWS Load Balancer Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
```

### Ingress sem endereço?
```bash
# Ver eventos do ingress
kubectl describe ingress -n <namespace> <ingress-name>
```

---

**Tempo estimado:** 10-15 minutos
**Próximo passo:** Se tudo validar, executar 2 ciclos destroy/apply
