# 🚀 Guia de Uso da Plataforma IDP

## 📋 Índice

1. [Acesso Inicial via Port-Forward](#1-acesso-inicial-via-port-forward)
2. [Sincronizando Applications](#2-sincronizando-applications)
3. [Configurando DNS](#3-configurando-dns)
4. [Acessos e Credenciais](#4-acessos-e-credenciais)
5. [Validando Componentes](#5-validando-componentes)
6. [Troubleshooting Comum](#6-troubleshooting-comum)
7. [Workflows de Desenvolvimento](#7-workflows-de-desenvolvimento)

---

## 1. Acesso Inicial via Port-Forward

### 🔑 Acessando ArgoCD (PRIMEIRA COISA A FAZER)

```bash
# 1. Obter senha do admin
export AWS_PROFILE=darede
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Copie a senha exibida

# 2. Criar port-forward (em um terminal separado, deixe rodando)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 3. Acessar no navegador
# URL: https://localhost:8080
# Username: admin
# Password: [senha do passo 1]
# IMPORTANTE: Aceite o certificado auto-assinado no navegador
```

### 📊 Acessando Backstage (temporário)

```bash
# Aguarde Backstage estar Running
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backstage -n backstage --timeout=300s

# Port-forward
kubectl port-forward svc/backstage -n backstage 7007:7007

# Acessar: http://localhost:7007
```

### 🔐 Acessando Keycloak (temporário)

```bash
# Aguarde Keycloak estar Running
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# Port-forward
kubectl port-forward svc/keycloak-http -n keycloak 8090:80

# Acessar: http://localhost:8090/auth
# Username: admin
# Password: admin
```

**⚠️ Nota:** Keycloak está agora usando o chart codecentric com usuário padrão `admin`.

---

## 2. Sincronizando Applications

### 🎯 Via ArgoCD UI (RECOMENDADO)

1. Acesse ArgoCD: https://localhost:8080
2. Veja todas Applications
3. Para cada Application **OutOfSync**:
   - Clique na Application
   - Clique em **SYNC**
   - Clique em **SYNCHRONIZE**
4. Aguarde status **Synced** e **Healthy**

### ⚡ Via CLI (Rápido)

```bash
export AWS_PROFILE=darede

# Sync TODAS applications de uma vez
kubectl -n argocd get applications -o name | while read app; do
  kubectl -n argocd patch $app --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
done

# Ou sync individual
argocd app sync ingress-nginx-in-cluster
argocd app sync keycloak-in-cluster
argocd app sync backstage-in-cluster
argocd app sync argo-workflows-in-cluster
```

### 📊 Monitorar Status

```bash
# Ver todas applications
watch -n 5 'kubectl get applications -n argocd'

# Ver pods de todas namespaces
watch -n 5 'kubectl get pods -A'

# Ver apenas pods com problemas
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## 3. Configurando DNS

### 🌐 Opção 1: Load Balancer (Produção)

```bash
# 1. Aguardar Load Balancer ficar pronto
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
# Espere até EXTERNAL-IP aparecer (não <pending>)

# 2. Copiar o DNS do Load Balancer
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Load Balancer DNS: $LB_DNS"

# 3. Configurar no Route53 (via AWS Console ou CLI)
# Criar CNAME records:
# argocd.timedevops.click     -> $LB_DNS
# backstage.timedevops.click  -> $LB_DNS
# keycloak.timedevops.click   -> $LB_DNS
```

### ⚡ Opção 2: /etc/hosts (Desenvolvimento Local)

```bash
# 1. Obter IP de um dos nodes
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# 2. Adicionar ao /etc/hosts
echo "$NODE_IP argocd.timedevops.click" | sudo tee -a /etc/hosts
echo "$NODE_IP backstage.timedevops.click" | sudo tee -a /etc/hosts
echo "$NODE_IP keycloak.timedevops.click" | sudo tee -a /etc/hosts

# 3. Acessar via NodePort
NODE_PORT_HTTP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
NODE_PORT_HTTPS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

# Acessar: http://argocd.timedevops.click:$NODE_PORT_HTTP
```

---

## 4. Acessos e Credenciais

### 🔐 Credenciais Padrão

| Serviço | URL (Port-Forward) | URL (DNS) | Usuário | Senha |
|---------|-------------------|-----------|---------|-------|
| **ArgoCD** | https://localhost:8080 | https://argocd.timedevops.click | `admin` | Ver comando abaixo ¹ |
| **Backstage** | http://localhost:7007 | https://backstage.timedevops.click | Login via Keycloak | - |
| **Keycloak** | http://localhost:8090/auth | https://keycloak.timedevops.click/auth | `admin` | `admin` |
| **Argo Workflows** | https://localhost:2746 | https://argo-workflows.timedevops.click | Via SSO | Via SSO |

¹ **Obter senha ArgoCD:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 🔄 Resetar Senhas

```bash
# ArgoCD - Alterar senha do admin
argocd account update-password

# Keycloak - Via UI ou Secret
kubectl -n keycloak get secret keycloak -o jsonpath="{.data.admin-password}" | base64 -d

# Obter Client Secret do Backstage (gerado pelo Job)
kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client Secret:" | awk '{print $NF}'
```

---

## 4.1. Autenticação Backstage com Keycloak

### 🔐 Login no Backstage via Keycloak OIDC

O Backstage está configurado para autenticação via Keycloak. Para fazer login:

1. **Acesse o Backstage:**
   - DNS: https://backstage.timedevops.click
   - Port-forward: http://localhost:7007

2. **Clique em "Sign In"**

3. **Selecione "Keycloak"** como provedor

4. **Você será redirecionado para o Keycloak:**
   - URL: https://keycloak.timedevops.click/auth
   - Username: `admin`
   - Password: `admin`

5. **Após login bem-sucedido, você será redirecionado de volta para o Backstage**

### ✅ Verificar Configuração

```bash
# 1. Verificar se o client 'backstage' existe no Keycloak
kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client ID:"

# 2. Verificar o secret do Backstage
kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.BACKSTAGE_CLIENT_SECRET}' | base64 -d && echo

# 3. Verificar se o pod do Backstage está rodando
kubectl get pods -n backstage

# 4. Verificar logs do Backstage
kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=50
```

### 🔧 Troubleshooting Login

**Problema: "Invalid redirect_uri"**
- Verificar se o redirect URI está configurado corretamente no cliente Keycloak
- Deve ser: `https://backstage.timedevops.click/*`

**Problema: "Invalid client or Invalid client credentials"**
- Verificar se o client secret no Backstage está correto
- Obter o secret real: `kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client Secret:"`
- Atualizar o secret se necessário

**Problema: "Connection refused" ao Keycloak**
- Verificar se o Ingress do Keycloak está criado: `kubectl get ingress -n keycloak`
- Verificar se o certificado TLS está válido: `kubectl get certificates -n keycloak`

---

## 5. Validando Componentes

### ✅ Script de Validação Completa

```bash
#!/bin/bash
export AWS_PROFILE=darede

echo "=== Validação da Plataforma IDP ==="

# 1. Cluster
echo -e "\n1. ✓ Verificando Cluster..."
kubectl cluster-info
kubectl get nodes -o wide

# 2. Namespaces
echo -e "\n2. ✓ Verificando Namespaces..."
kubectl get namespaces

# 3. Applications ArgoCD
echo -e "\n3. ✓ Verificando Applications..."
kubectl get applications -n argocd

# 4. Pods por Namespace
echo -e "\n4. ✓ Verificando Pods..."
for ns in argocd backstage keycloak argo ingress-nginx cert-manager crossplane-system external-secrets external-dns; do
  echo "  Namespace: $ns"
  kubectl get pods -n $ns 2>/dev/null | grep -E "NAME|Running|Pending|Error" | head -5
done

# 5. Ingress
echo -e "\n5. ✓ Verificando Ingresses..."
kubectl get ingress -A

# 6. Load Balancer
echo -e "\n6. ✓ Verificando Load Balancer..."
kubectl get svc -n ingress-nginx ingress-nginx-controller

# 7. Secrets Importantes
echo -e "\n7. ✓ Verificando Secrets..."
kubectl get secret -n argocd hub-cluster-secret -o jsonpath='{.metadata.labels}' | jq .
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo

echo -e "\n=== Validação Completa! ===\n"
```

Salve como `validate-platform.sh` e execute:
```bash
chmod +x validate-platform.sh
./validate-platform.sh
```

---

## 6. Troubleshooting Comum

### ❌ Applications OutOfSync

**Causa:** Auto-sync não habilitado ou erro de sincronização.

**Solução:**
```bash
# Forçar sync de uma application específica
kubectl -n argocd patch application <app-name> --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# Ou via ArgoCD UI: SYNC → SYNCHRONIZE
```

### ❌ Load Balancer em <pending>

**Causa:** AWS Load Balancer Controller não instalado ou sem permissões.

**Solução 1 - Via UI:**
1. Acesse ArgoCD
2. Vá em Applications
3. Procure `aws-load-balancer-controller`
4. Se não existir, vá em ApplicationSets
5. Force refresh do ApplicationSet `aws-load-balancer-controller`

**Solução 2 - Via CLI:**
```bash
# Verificar se ApplicationSet existe
kubectl get applicationset -n argocd | grep load-balancer

# Verificar logs do ApplicationSet controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50

# Recriar hub-cluster-secret (pode estar faltando labels)
kubectl get secret hub-cluster-secret -n argocd -o yaml | grep -A 10 labels
```

### ❌ Pods em CrashLoopBackOff

**Causa:** Configuração incorreta ou dependências faltando.

**Solução:**
```bash
# Ver logs do pod
kubectl logs -n <namespace> <pod-name> --tail=50

# Ver eventos
kubectl describe pod -n <namespace> <pod-name>

# Ver configuração
kubectl get pod -n <namespace> <pod-name> -o yaml
```

### ❌ External Secrets com Erro

**Causa:** SCP bloqueando acesso ao Secrets Manager.

**Solução:** Ver `docs/SCP-WORKAROUND.md` - já implementado!

---

## 7. Workflows de Desenvolvimento

### 🎨 Criar Nova Aplicação no Backstage

1. Acesse Backstage: https://backstage.timedevops.click
2. Clique em **Create**
3. Escolha um template
4. Preencha informações
5. Application é criada automaticamente:
   - Repositório Git
   - Pipeline CI/CD
   - Manifests Kubernetes
   - Application ArgoCD

### 🚀 Deploy de Aplicação

1. **Via Git (GitOps - Recomendado):**
   ```bash
   # 1. Commit mudanças no repo
   git add .
   git commit -m "Update app version"
   git push

   # 2. ArgoCD sincroniza automaticamente
   # 3. Ver status no ArgoCD UI
   ```

2. **Via ArgoCD UI:**
   - Vá em Applications
   - Clique em **+ NEW APP**
   - Configure:
     - Application Name
     - Project: default
     - Sync Policy: Automated
     - Repository URL
     - Path
     - Cluster: in-cluster
     - Namespace
   - Clique em **CREATE**

3. **Via kubectl (temporário):**
   ```bash
   kubectl apply -f manifests/ -n <namespace>
   ```

### 🔄 Atualizar Aplicação

```bash
# 1. GitOps (produção)
git commit -m "Update image to v2.0"
git push
# ArgoCD detecta e sincroniza

# 2. Manual (desenvolvimento)
kubectl set image deployment/<name> <container>=<new-image> -n <namespace>
```

### 📊 Monitorar Deploy

```bash
# Via ArgoCD UI (melhor visualização)
# https://localhost:8080

# Via CLI
kubectl rollout status deployment/<name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### 🎯 Criar Pipeline CI/CD

1. **Argo Workflows:**
   ```bash
   # Acessar: https://localhost:2746 (port-forward)
   kubectl port-forward svc/argo-workflows-server -n argo 2746:2746

   # Submeter workflow
   argo submit workflow.yaml -n argo
   ```

2. **Integração GitHub Actions → ArgoCD:**
   ```yaml
   # .github/workflows/deploy.yml
   name: Deploy
   on:
     push:
       branches: [main]
   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - name: Update image tag
           run: |
             sed -i "s|image:.*|image: myapp:${{ github.sha }}|" k8s/deployment.yaml
             git config user.name github-actions
             git config user.email github-actions@github.com
             git commit -am "Update image to ${{ github.sha }}"
             git push
   ```

---

## 📚 Próximos Passos

### 🔒 Segurança

1. **Mudar senhas padrão:**
   ```bash
   # ArgoCD
   argocd account update-password

   # Keycloak
   # Via UI: Admin Console → Users → cnoe-admin → Credentials
   ```

2. **Configurar SSO (Keycloak):**
   - ArgoCD → Keycloak OIDC
   - Backstage → Keycloak OAuth
   - Argo Workflows → Keycloak SSO

3. **TLS/HTTPS:**
   ```bash
   # Cert-manager já instalado!
   # Criar ClusterIssuer para Let's Encrypt
   kubectl apply -f docs/examples/cluster-issuer.yaml
   ```

### 📈 Observabilidade (Opcional)

```bash
# Instalar Prometheus + Grafana
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Ou via ArgoCD Application
# Ver: packages/monitoring/
```

### 🎓 Aprender Mais

- **ArgoCD:** https://argo-cd.readthedocs.io/
- **Backstage:** https://backstage.io/docs/
- **Keycloak:** https://www.keycloak.org/docs/
- **Crossplane:** https://docs.crossplane.io/

---

## 🆘 Suporte

### Logs Importantes

```bash
# ArgoCD ApplicationSet Controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100

# External Secrets
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100

# Ingress NGINX
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
```

### Comandos Úteis

```bash
# Reiniciar um pod
kubectl rollout restart deployment/<name> -n <namespace>

# Ver configuração de uma application
kubectl get application <name> -n argocd -o yaml

# Forçar refresh de ApplicationSet
kubectl annotate applicationset <name> -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite

# Ver secret decodificado
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | jq 'map_values(@base64d)'
```

---

**Mantido por:** Darede Labs
**Versão:** 1.0.0
**Última atualização:** 2025-12-10
