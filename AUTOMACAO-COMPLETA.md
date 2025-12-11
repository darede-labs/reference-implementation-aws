# ✅ Automação Completa - Keycloak + Backstage

## 🎯 Status da Automação

**TODAS** as etapas manuais foram automatizadas e refletidas no código! 🎉

### ✅ O que foi automatizado:

1. **Keycloak:**
   - ✅ Chart codecentric instalado com Postgres bitnamilegacy 17.6.0
   - ✅ Ingress com TLS (cert-manager) criado automaticamente
   - ✅ Client OIDC `backstage` criado automaticamente via Kubernetes Job
   - ✅ Client secret gerado e configurado automaticamente

2. **Backstage:**
   - ✅ Ingress com TLS (cert-manager) criado automaticamente
   - ✅ Secret `backstage-env-vars` criado com client secret do Keycloak
   - ✅ Pod reiniciado automaticamente para carregar novos secrets
   - ✅ Autenticação OIDC configurada automaticamente

3. **install.sh:**
   - ✅ Criação automática de secrets
   - ✅ Aplicação automática de Ingresses
   - ✅ Execução automática do Job de bootstrap do Keycloak
   - ✅ Extração e configuração automática do client secret
   - ✅ Restart automático do Backstage

## 🚀 Como usar

### Instalação Completa (Zero Manual Intervention)

```bash
cd /Users/matheusandrade/darede/reference-implementation-aws
export AWS_PROFILE=darede
./scripts/install.sh
```

**Isso é tudo!** O script irá:
1. Criar o cluster EKS
2. Instalar todos os componentes (ArgoCD, Keycloak, Backstage, etc.)
3. Configurar Keycloak automaticamente
4. Integrar Backstage com Keycloak
5. Criar todos os Ingresses com TLS

## 🌐 URLs de Acesso

| Serviço | URL | TLS |
|---------|-----|-----|
| **Keycloak** | https://keycloak.timedevops.click/auth | ✅ |
| **Backstage** | https://backstage.timedevops.click | ✅ |
| **ArgoCD** | https://argocd.timedevops.click | ✅ |

## 🔐 Credenciais

### Keycloak Admin
```
URL: https://keycloak.timedevops.click/auth
Username: admin
Password: admin
```

### Backstage (Login via Keycloak)
```
URL: https://backstage.timedevops.click
- Clique em "Sign In"
- Selecione "Keycloak"
- Use as credenciais do Keycloak acima
```

### ArgoCD
```
URL: https://argocd.timedevops.click
Username: admin
Password: (obter via comando abaixo)
```

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## 📋 Verificações

### 1. Verificar Keycloak

```bash
# Pods
kubectl get pods -n keycloak
# Todos devem estar Running

# Ingress
kubectl get ingress -n keycloak
# Deve ter ADDRESS configurado

# Certificate
kubectl get certificate -n keycloak
# keycloak-tls deve estar READY=True

# Client configurado
kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client ID:"
# Deve mostrar: Client ID: backstage
```

### 2. Verificar Backstage

```bash
# Pods
kubectl get pods -n backstage
# backstage deve estar Running

# Ingress
kubectl get ingress -n backstage
# Deve ter ADDRESS configurado

# Certificate
kubectl get certificate -n backstage
# backstage-tls deve estar READY=True

# Secret com client secret
kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.BACKSTAGE_CLIENT_SECRET}' | base64 -d && echo
# Deve mostrar o client secret do Keycloak
```

### 3. Verificar Integração

```bash
# Obter client secret do Job
CLIENT_SECRET=$(kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client Secret:" | awk '{print $NF}')
echo "Client Secret do Keycloak: $CLIENT_SECRET"

# Verificar se o secret no Backstage está correto
BACKSTAGE_SECRET=$(kubectl get secret backstage-env-vars -n backstage -o jsonpath='{.data.BACKSTAGE_CLIENT_SECRET}' | base64 -d)
echo "Client Secret no Backstage: $BACKSTAGE_SECRET"

# Devem ser iguais!
if [ "$CLIENT_SECRET" == "$BACKSTAGE_SECRET" ]; then
  echo "✅ Secrets estão sincronizados!"
else
  echo "❌ Secrets estão diferentes!"
fi
```

## 🧪 Testar Login

1. **Abra o navegador em:** https://backstage.timedevops.click

2. **Clique em "Sign In"**

3. **Selecione "Keycloak"** como provedor de autenticação

4. **Você será redirecionado para:** https://keycloak.timedevops.click/auth
   - Digite: `admin` / `admin`
   - Clique em "Sign In"

5. **Você será redirecionado de volta para o Backstage logado!** ✅

## 📝 Arquivos Criados/Modificados

### Criados:
- `/packages/keycloak/codecentric-values.yaml` - Values para chart codecentric
- `/packages/keycloak/keycloak-ingress.yaml` - Ingress com TLS
- `/packages/keycloak/keycloak-bootstrap-job.yaml` - Job para configurar client
- `/packages/backstage/backstage-ingress.yaml` - Ingress com TLS

### Modificados:
- `/scripts/install.sh` - Automação completa adicionada
- `/packages/backstage/values.yaml` - Configuração OIDC Keycloak
- `/docs/GUIA-USO-PLATAFORMA.md` - Guia atualizado

## 🎓 Próximos Passos

### Criar Recursos via Backstage

1. Acesse o Backstage (já logado via Keycloak)
2. Vá em **"Create"** no menu lateral
3. Escolha um template (ex: "Create a new component")
4. Preencha as informações
5. O Backstage irá:
   - Criar o repositório Git
   - Criar os manifestos Kubernetes
   - Criar a Application no ArgoCD
   - Deploy automático!

### Verificar no ArgoCD

1. Acesse: https://argocd.timedevops.click
2. Faça login com as credenciais do ArgoCD
3. Veja todas as applications sincronizadas
4. Clique em uma application para ver detalhes

### Verificar no AWS

```bash
# Ver EKS cluster
aws eks list-clusters --profile darede

# Ver nodes
kubectl get nodes -o wide

# Ver Load Balancer (Ingress)
aws elbv2 describe-load-balancers --profile darede | grep DNSName
```

## 🆘 Troubleshooting

### Problema: "Invalid redirect_uri" no Backstage

**Solução:**
```bash
# Verificar redirect URIs configurados no Keycloak
kubectl exec -n keycloak keycloak-0 -- /opt/jboss/keycloak/bin/kcadm.sh \
  get clients -r master -q clientId=backstage \
  --config /tmp/kcadm.config

# Deve incluir: "https://backstage.timedevops.click/*"
```

### Problema: Client secret não está correto

**Solução:**
```bash
# 1. Obter o secret real do Keycloak
CLIENT_SECRET=$(kubectl logs -n keycloak job/keycloak-bootstrap | grep "Client Secret:" | awk '{print $NF}')

# 2. Atualizar no Backstage
kubectl -n backstage patch secret backstage-env-vars \
  -p "{\"data\":{\"BACKSTAGE_CLIENT_SECRET\":\"$(echo -n $CLIENT_SECRET | base64)\"}}"

# 3. Reiniciar Backstage
kubectl rollout restart deployment backstage -n backstage
kubectl rollout status deployment backstage -n backstage
```

### Problema: Certificate não está READY

**Solução:**
```bash
# Verificar cert-manager
kubectl get pods -n cert-manager

# Verificar logs do cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Verificar CertificateRequest
kubectl get certificaterequest -n keycloak
kubectl get certificaterequest -n backstage

# Verificar Issuer
kubectl get clusterissuer
```

## ✅ Checklist Final

- [x] Keycloak rodando com Postgres bitnamilegacy
- [x] Keycloak Ingress criado com TLS
- [x] Client `backstage` criado automaticamente no Keycloak
- [x] Backstage Ingress criado com TLS
- [x] Backstage configurado com OIDC Keycloak
- [x] Backstage secret atualizado com client secret correto
- [x] Login no Backstage funcionando via Keycloak
- [x] Todas mudanças refletidas no código
- [x] install.sh totalmente automatizado
- [x] Documentação atualizada

## 🎉 Conclusão

**A plataforma está 100% funcional e automatizada!**

Basta executar `./scripts/install.sh` e tudo será configurado automaticamente, incluindo:
- Keycloak com autenticação admin
- Backstage integrado com Keycloak via OIDC
- Ingresses com TLS automático
- Certificados gerenciados pelo cert-manager

**Nenhuma intervenção manual é necessária!** 🚀

---

**Data:** 2025-12-10
**Versão:** 1.0.0
**Status:** ✅ COMPLETO
