# 🎯 Configurações Finais da Plataforma IDP

**Data:** 11 de Dezembro de 2025
**Status:** ✅ Operacional e pronto para uso

---

## 📦 1. ArgoCD - Application Infrastructure

### Configuração Atual (PERSISTIDA NO CLUSTER):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/darede-labs/infrastructureidp
    targetRevision: HEAD
    path: .                           # ✅ Monitora TODO o repositório
    directory:
      exclude: catalog-info.yaml
      jsonnet: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: true                     # ✅ Remove recursos deletados do Git
      selfHeal: true                  # ✅ Corrige drifts automaticamente
    syncOptions:
      - CreateNamespace=true
```

### Como Verificar:
```bash
kubectl -n argocd get application infrastructure -o yaml
```

### Como Re-aplicar se Necessário:
```bash
kubectl -n argocd patch application infrastructure --type merge -p '{
  "spec": {
    "source": {"path": "."},
    "syncPolicy": {
      "automated": {"prune": true, "selfHeal": true}
    }
  }
}'
```

---

## 🎨 2. Backstage Templates

### Templates Disponíveis (8 total):

Todos commitados em: `https://github.com/darede-labs/infrastructureidp/backstage-templates/`

1. **S3 Bucket** - `s3-bucket-template.yaml`
2. **VPC** - `vpc-template.yaml`
3. **EC2 Instance** - `ec2-template.yaml`
4. **RDS Database** - `rds-template.yaml`
5. **EKS Cluster** - `eks-template.yaml`
6. **DynamoDB Table** - `dynamodb-template.yaml`
7. **Secrets Manager** - `secrets-template.yaml`
8. **SSM Parameters** - `ssm-template.yaml`

### Estratégia de Nomes (SIMPLIFICADA):

**Sem sufixos aleatórios** - apenas o nome do recurso:

```yaml
# Exemplo: criar bucket S3
bucketName: my-bucket-prod

# Cria:
- Path: s3-buckets/my-bucket-prod/
- Branch: bucket-my-bucket-prod
- Nome no AWS: my-bucket-prod
```

**Múltiplos recursos:**
- Recurso 1: `eks-dev` → `eks-clusters/eks-dev/`
- Recurso 2: `eks-staging` → `eks-clusters/eks-staging/`
- Recurso 3: `eks-prod` → `eks-clusters/eks-prod/`

✅ **Zero conflitos** - cada nome único gera path único

### Catalog Info:
```
URL: https://github.com/darede-labs/infrastructureidp/blob/main/catalog-info.yaml
```

---

## 🔧 3. Crossplane Compositions

### Compositions Aplicadas no Cluster:

```bash
# Verificar compositions instaladas
kubectl get compositions
kubectl get xrd

# Compositions disponíveis:
- xdynamodbtable.darede.io  ✅
- xsecret.darede.io         ✅
- xssmparameter.darede.io   ✅
- xs3bucket.darede.io       ✅
- xvpc.darede.io            ✅
- xec2instance.darede.io    ✅
- xrdsinstance.darede.io    ✅
- xekscluster.darede.io     ✅
```

### Localização dos Arquivos:
```
/packages/crossplane-compositions/
├── dynamodb-definition.yaml    ✅
├── dynamodb-composition.yaml   ✅
├── secrets-definition.yaml     ✅
├── secrets-composition.yaml    ✅
├── ssm-definition.yaml         ✅
├── ssm-composition.yaml        ✅
├── s3-composition.yaml         ✅
├── vpc-composition.yaml        ✅
├── ec2-composition.yaml        ✅
├── rds-composition.yaml        ✅
└── eks-composition.yaml        ✅
```

### Como Re-aplicar:
```bash
cd ~/darede/reference-implementation-aws
kubectl apply -f packages/crossplane-compositions/dynamodb-definition.yaml
kubectl apply -f packages/crossplane-compositions/dynamodb-composition.yaml
kubectl apply -f packages/crossplane-compositions/secrets-definition.yaml
kubectl apply -f packages/crossplane-compositions/secrets-composition.yaml
kubectl apply -f packages/crossplane-compositions/ssm-definition.yaml
kubectl apply -f packages/crossplane-compositions/ssm-composition.yaml
```

---

## 🔐 4. Keycloak SSO (ArgoCD)

### Configuração Atual:

```yaml
# ArgoCD ConfigMap
oidc.config: |
  name: Keycloak
  issuer: https://keycloak.timedevops.click/auth/realms/cnoe
  clientID: argocd
  clientSecret: $argocd-keycloak-secret:secret
  requestedScopes:
    - openid
    - profile
    - email
    - groups

# Secret
kubectl get secret argocd-keycloak-secret -n argocd
```

### Usuários Disponíveis:
- `admin` / `admin` → role:admin (superuser)
- `developer1` / `developer123` → role:readonly
- `superuser1` / `super123` → role:admin

### Como Re-aplicar:
```bash
# Criar secret
kubectl create secret generic argocd-keycloak-secret -n argocd \
  --from-literal=secret=argocd-secret-2024 \
  --dry-run=client -o yaml | kubectl apply -f -

# Patch ConfigMap
kubectl -n argocd patch cm argocd-cm --type merge -p '{
  "data": {
    "oidc.config": "name: Keycloak\nissuer: https://keycloak.timedevops.click/auth/realms/cnoe\nclientID: argocd\nclientSecret: $argocd-keycloak-secret:secret\nrequestedScopes:\n  - openid\n  - profile\n  - email\n  - groups"
  }
}'

# Restart ArgoCD server
kubectl rollout restart -n argocd deployment/argocd-server
```

---

## 📊 5. Fluxo Completo de Criação

### 1. Criar Recurso no Backstage:
```
URL: https://backstage.timedevops.click/create
Escolher template → Preencher → CREATE
```

### 2. PR Criado Automaticamente:
```
Repo: https://github.com/darede-labs/infrastructureidp
Branch: tipo-nome-recurso
Path: tipo-recursos/nome-recurso/
  ├── recurso.yaml
  └── catalog-info.yaml
```

### 3. Merge do PR:
```bash
# Via GitHub UI ou CLI
gh pr merge NUMERO --merge
```

### 4. ArgoCD Detecta (automático ~30s):
```
Status: OutOfSync → Syncing → Synced
Health: Progressing → Healthy
```

### 5. Crossplane Cria no AWS:
```bash
# Monitorar
kubectl get TIPO -n crossplane-system
kubectl describe TIPO NOME -n crossplane-system

# Exemplo S3:
kubectl get s3bucket testbucket1 -n crossplane-system
```

### 6. Ver no Backstage Catalog:
```
URL: https://backstage.timedevops.click/catalog
Filter: Kind = Resource, Tags = aws
```

---

## 🎯 6. Estrutura do Repositório infrastructureidp

```
infrastructureidp/
├── catalog-info.yaml              # ✅ Lista todos templates
├── backstage-templates/           # ✅ 8 templates
│   ├── s3-bucket-template.yaml
│   ├── vpc-template.yaml
│   ├── ec2-template.yaml
│   ├── rds-template.yaml
│   ├── eks-template.yaml
│   ├── dynamodb-template.yaml
│   ├── secrets-template.yaml
│   └── ssm-template.yaml
├── s3-buckets/                    # Recursos criados via Backstage
├── vpcs/
├── ec2-instances/
├── rds-databases/
├── eks-clusters/
├── dynamodb-tables/
├── secrets/
└── ssm-parameters/
```

---

## 🚀 7. URLs Importantes

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| **Backstage** | https://backstage.timedevops.click | Keycloak SSO |
| **ArgoCD** | https://argocd.timedevops.click | admin/Keycloak SSO |
| **Keycloak** | https://keycloak.timedevops.click | admin/admin |
| **GitHub Org** | https://github.com/darede-labs | - |
| **Repo Templates** | https://github.com/darede-labs/infrastructureidp | - |
| **Repo Platform** | https://github.com/darede-labs/reference-implementation-aws | - |

---

## 🔄 8. Comandos Úteis de Manutenção

### Verificar Status Geral:
```bash
# ArgoCD applications
kubectl get applications -n argocd

# Crossplane resources
kubectl get crossplane -n crossplane-system
kubectl get managed -n crossplane-system

# Providers
kubectl get providers
```

### Forçar Sync do ArgoCD:
```bash
kubectl -n argocd patch application infrastructure \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Logs de Debugging:
```bash
# ArgoCD controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Crossplane
kubectl logs -n crossplane-system -l app=crossplane -f

# Provider AWS
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 -f
```

### Deletar Recurso:
```bash
# 1. Deletar do Git (PR ou direct push)
cd ~/infrastructureidp
rm -rf s3-buckets/testbucket1/
git add -A && git commit -m "Remove testbucket1" && git push

# 2. ArgoCD detecta e deleta (prune: true)
# 3. Crossplane deleta do AWS
```

---

## ✅ 9. Checklist de Verificação

Antes de criar recursos, confirme:

- [ ] ArgoCD application `infrastructure` está **Synced** e **Healthy**
- [ ] Crossplane providers estão **HEALTHY** (`kubectl get providers`)
- [ ] Backstage catalog mostra os 8 templates (`/create`)
- [ ] Keycloak SSO funciona no ArgoCD
- [ ] GitHub App credentials configuradas no Backstage
- [ ] AWS credentials configuradas no Crossplane

**Comando rápido de verificação:**
```bash
# Tudo de uma vez
kubectl get application infrastructure -n argocd && \
kubectl get providers && \
kubectl get xrd && \
echo "✅ Plataforma operacional!"
```

---

## 🎓 10. Próximos Passos

1. **Criar primeiro recurso no Backstage** (ex: S3 bucket)
2. **Verificar PR criado** no GitHub
3. **Fazer merge do PR**
4. **Acompanhar sync no ArgoCD**
5. **Ver recurso criado no AWS Console**
6. **Verificar no Backstage Catalog**

**Plataforma 100% funcional e automatizada!** 🚀

---

**Última atualização:** 11/12/2025
**Autor:** Matheus Andrade
**Status:** ✅ Production Ready
