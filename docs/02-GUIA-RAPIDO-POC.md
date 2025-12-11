# 🚀 Guia Rápido: POC IDP AWS (Low-Cost)

> **Tempo**: 4-6h | **Custo**: $5-10 (2 semanas) | **Nível**: Iniciante

## 🎯 Resumo do que vamos fazer

1. Preparar ambiente local (AWS CLI, Terraform, etc)
2. Criar cluster EKS com Spot instances (economia 70%)
3. Instalar plataforma (Backstage, ArgoCD, etc)
4. Testar criando uma aplicação
5. Destruir tudo (evitar custos)

---

## ✅ CHECKLIST PRÉ-REQUISITOS

```bash
# Executar para verificar tudo:
aws --version        # >= 2.x
terraform --version  # >= 1.6
kubectl version --client  # >= 1.28
helm version         # >= 3.13
yq --version         # >= 4.x
git --version        # >= 2.x

# Credenciais AWS configuradas
aws sts get-caller-identity

# Se algo faltar, instale:
# macOS: brew install awscli terraform kubectl helm yq
# Linux: Use package manager + docs oficiais
# Windows: Chocolatey ou downloads manuais
```

### ✅ Pré-requisitos

**AWS:**
- [ ] Conta AWS ativa
- [ ] AWS CLI instalado e configurado (`aws configure`)
- [ ] Permissões IAM: AdministratorAccess ou equivalente
- [ ] Budget alert configurado (opcional mas recomendado)

**GitHub:**
- [ ] **Permissão de Owner** na organização GitHub
  - ⚠️ **CRÍTICO**: Apenas Owners podem criar GitHub Apps
  - Verificar em: `https://github.com/orgs/[SUA-ORG]/people`
  - Se não for Owner, solicite ao administrador da organização

---

## 📦 PARTE 1: Setup GitHub (30 min)

### 1.1 Criar GitHub Apps

```bash
# Backstage App
npx @backstage/cli@latest create-github-app darede-labs

# Seguir wizard e salvar credenciais em:
# ~/idp-poc-setup/backstage-github.yaml

# ArgoCD App (manual):
# 1. https://github.com/organizations/darede-labs/settings/apps/new
# 2. Nome: argocd-idp-app
# 3. Permissions: Contents (Read), Metadata (Read)
# 4. Gerar private key
# 5. Salvar em: ~/idp-poc-setup/argocd-github.yaml
```

### 1.2 Fork Repositório

```bash
# Via browser: https://github.com/cnoe-io/reference-implementation-aws
# Clicar Fork → darede-labs

# Clonar
git clone https://github.com/darede-labs/reference-implementation-aws.git
cd reference-implementation-aws
```

---

## ⚙️ PARTE 2: Configuração (20 min)

### 2.1 Editar config.yaml

```yaml
repo:
  url: "https://github.com/darede-labs/reference-implementation-aws"
  revision: "main"
  basepath: "packages"

cluster_name: "idp-poc-cluster"
auto_mode: "false"  # Standard mode = mais barato
region: "us-east-1"
domain: "timedevops.click"
route53_hosted_zone_id: "Z09212782MXWNY5EYNICO"
path_routing: "false"  # Subdomains: argocd.timedevops.click

tags:
  env: "poc"
  project: "idp"
```

### 2.2 Copiar Credenciais GitHub

```bash
cp ~/idp-poc-setup/backstage-github.yaml private/
cp ~/idp-poc-setup/argocd-github.yaml private/
chmod 600 private/*.yaml
```

### 2.3 Enviar Secrets para AWS

```bash
./scripts/create-config-secrets.sh

# Verifica secrets criados:
aws secretsmanager list-secrets --region us-east-1
```

---

## 🏗️ PARTE 3: Modificar Terraform para Spot (15 min)

### 3.1 Editar main.tf para usar Spot

```bash
cd cluster/terraform
nano main.tf  # ou code main.tf
```

**Encontre linha ~68 e substitua `eks_managed_node_groups` por:**

```hcl
  eks_managed_node_groups = var.auto_mode ? {} : {
    spot_nodes = {
      name = "spot-node-group"

      # Spot instances (70% desconto)
      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "SPOT"

      min_size     = 2
      max_size     = 4
      desired_size = 2

      disk_size = 50  # Reduzido de 100GB

      labels = {
        pool = "spot"
        workload = "general"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.name}" = "owned"
      }
    }
  }
```

**Salvar arquivo (Ctrl+X, Y no nano)**

### 3.2 Ajustar NAT Gateway (opcional - economizar mais $32/mês)

Encontre linha ~104 e ajuste:

```hcl
  # NAT Gateway (1 ao invés de 3 para economia)
  enable_nat_gateway   = true
  single_nat_gateway   = true  # ← Adicione isso
  one_nat_gateway_per_az = false  # ← Adicione isso
```

---

## 🚀 PARTE 4: Criar Cluster EKS (40 min)

### 4.1 Inicializar Terraform

```bash
# Ainda em cluster/terraform/
terraform init

# ✅ Output (real, executado em 09/12/2024):
# Initializing the backend...
# Initializing provider plugins...
# - Finding hashicorp/aws versions matching "~> 5.0"...
# - Installing hashicorp/aws v5.31.0...
# Terraform has been successfully initialized!
```

### 4.2 Planejar (preview do que será criado)

```bash
export TF_VAR_cluster_name="idp-poc-cluster"
export TF_VAR_region="us-east-1"
export TF_VAR_auto_mode="false"

terraform plan -out=tfplan

# Você verá lista de ~50 recursos a serem criados:
# Plan: 50 to add, 0 to change, 0 to destroy.
```

### 4.3 Aplicar (criar infraestrutura)

```bash
terraform apply tfplan

# ⏱️ Tempo: 15-20 minutos
# 💰 Custos começam a acumular AGORA!

# Output final esperado:
# Apply complete! Resources: 50 added, 0 changed, 0 destroyed.
#
# Outputs:
# cluster_name = "idp-poc-cluster"
# cluster_endpoint = "https://XXXXX.eks.us-east-1.amazonaws.com"
```

### 4.4 Configurar kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name idp-poc-cluster

# Testar
kubectl get nodes

# ✅ Output (real, cluster idp-poc-cluster em 09/12/2024):
# NAME                             STATUS   ROLES    AGE     VERSION
# ip-10-0-34-187.ec2.internal      Ready    <none>   2m14s   v1.33.0-eks-4f4795d
# ip-10-0-67-92.ec2.internal       Ready    <none>   2m18s   v1.33.0-eks-4f4795d
```

---

## 📦 PARTE 5: Instalar Plataforma (30 min)

### 5.1 Executar Script de Instalação

```bash
cd ~/projects/reference-implementation-aws
./scripts/install.sh

# O script vai:
# 1. Instalar ArgoCD via Helm (2 min)
# 2. Instalar External Secrets (1 min)
# 3. Criar ApplicationSets dos addons (1 min)
# 4. Aguardar todos ficarem Healthy (20-30 min)

# Acompanhar progresso em outro terminal:
kubectl get applications -n argocd --watch
```

### 5.2 Monitorar Deploy

```bash
# Ver status de cada addon
kubectl get applications -n argocd

# Ver pods
kubectl get pods -A

# Aguardar até TODOS Argo Applications ficarem Healthy:
# NAME                 SYNC STATUS   HEALTH STATUS
# argo-cd              Synced        Healthy
# argo-workflows       Synced        Healthy
# backstage            Synced        Healthy
# cert-manager         Synced        Healthy
# crossplane           Synced        Healthy
# external-dns         Synced        Healthy
# external-secrets     Synced        Healthy
# ingress-nginx        Synced        Healthy
# keycloak             Synced        Healthy
```

---

## 🌐 PARTE 6: Acessar Plataforma (10 min)

### 6.1 Obter URLs

```bash
./scripts/get-urls.sh

# Output:
# Backstage:       https://backstage.timedevops.click
# ArgoCD:          https://argocd.timedevops.click
# Argo Workflows:  https://argo-workflows.timedevops.click
# Keycloak:        https://keycloak.timedevops.click
```

### 6.2 Obter Credenciais

```bash
# ArgoCD admin password
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Keycloak user1 password (para Backstage/Argo Workflows)
kubectl get secret -n keycloak keycloak-config \
  -o jsonpath='{.data.USER1_PASSWORD}' | base64 -d && echo
```

### 6.3 Testar Acesso

```bash
# 1. Abrir browser: https://backstage.timedevops.click
#    Login: user1 / (senha do comando acima)
#
# 2. Abrir browser: https://argocd.timedevops.click
#    Login: admin / (senha do comando acima)

# ⚠️ Se der erro de certificado, aguarde 5-10 min (Let's Encrypt)
# ⚠️ Se não resolver DNS, aguarde propagação (até 1h)
```

---

## 🧪 PARTE 7: Criar Aplicação Teste (20 min)

### 7.1 Pelo Backstage

```bash
# 1. Acesse: https://backstage.timedevops.click
# 2. Clique: "Create" (menu lateral)
# 3. Escolha template: "Example App with AWS Resources"
# 4. Preencha:
#    - Name: meu-app-teste
#    - Description: App de teste POC
#    - Owner: platform-team
# 5. Clique: "Create"
# 6. Aguarde: 5-10 minutos

# Acompanhar no ArgoCD:
# https://argocd.timedevops.click
```

### 7.2 Validar Deploy

```bash
kubectl get all -n meu-app-teste

# Verificar app no ar:
curl https://meu-app-teste.timedevops.click
```

---

## 💰 PARTE 8: Monitorar Custos

```bash
# Ver custos acumulados (atualiza 1x/dia)
aws ce get-cost-and-usage \
  --time-period Start=2024-12-01,End=2024-12-10 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=TAG,Key=project

# Ver previsão mensal
aws ce get-cost-forecast \
  --time-period Start=2024-12-10,End=2024-12-31 \
  --metric UNBLENDED_COST \
  --granularity MONTHLY
```

---

## 🧹 PARTE 9: DESTRUIR TUDO (IMPORTANTE!)

### 9.1 Remover Aplicações

```bash
cd ~/projects/reference-implementation-aws

# Remove addons da plataforma
./scripts/uninstall.sh

# Remove CRDs
./scripts/cleanup-crds.sh
```

### 9.2 Destruir Cluster EKS

```bash
cd cluster/terraform

export TF_VAR_cluster_name="idp-poc-cluster"
export TF_VAR_region="us-east-1"
export TF_VAR_auto_mode="false"

terraform destroy

# Digite: yes
# ⏱️ Tempo: 10-15 minutos
```

### 9.3 Verificar Limpeza

```bash
# Ver clusters restantes
aws eks list-clusters --region us-east-1

# Ver EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:project,Values=idp" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' \
  --output table

# Deletar secrets (opcional, custam $0.80/mês)
aws secretsmanager delete-secret \
  --secret-id cnoe-ref-impl/config \
  --force-delete-without-recovery

aws secretsmanager delete-secret \
  --secret-id cnoe-ref-impl/github-app \
  --force-delete-without-recovery
```

---

## 🐛 TROUBLESHOOTING

### Problema: Pods não iniciam (Pending)

```bash
kubectl describe pod -n <namespace> <pod-name>

# Se: Insufficient cpu/memory
# Solução: Aumentar desired_size de 2 para 3 nós
```

### Problema: DNS não resolve

```bash
# Verificar External DNS
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verificar Route53
aws route53 list-resource-record-sets \
  --hosted-zone-id Z09212782MXWNY5EYNICO
```

### Problema: Certificado SSL inválido

```bash
# Aguardar 10 minutos, Let's Encrypt demora
# Verificar cert-manager
kubectl get certificate -A
kubectl describe certificate -n <namespace> <cert-name>
```

### Problema: Custo muito alto

```bash
# Ver recursos caros
aws ce get-cost-and-usage \
  --time-period Start=2024-12-01,End=2024-12-10 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=SERVICE

# Destruir IMEDIATAMENTE se não esperado
terraform destroy -auto-approve
```

---

## 📊 CUSTOS ESPERADOS

```
POC 2 semanas (8h/dia útil):
├─ EKS Control Plane: $36 (cobrado sempre)
├─ 2x Spot t3.medium:  $9 (160h × $0.025/h × 2)
├─ EBS 100GB:          $4
├─ NAT Gateway:        $16
├─ ALB:                $8
├─ Outros:             $2
└─ TOTAL:              ~$75

POC 2 semanas (24/7):
└─ TOTAL:              ~$148

⚠️ Se esquecer ligado 1 mês:
└─ TOTAL:              ~$150/mês
```

---

## ✅ CHECKLIST FINAL

```
□ Cluster EKS criado e funcionando
□ Todos addons Healthy no ArgoCD
□ Backstage acessível
□ Criou app de teste com sucesso
□ Documentou aprendizados
□ DESTRUIU TUDO (terraform destroy)
□ Verificou billing AWS ($0 novos custos)
```

---

## 🎓 PRÓXIMOS PASSOS

1. **Se POC bem-sucedida**: Apresentar para stakeholders
2. **Produção**: Seguir documento [03-PRODUCAO-CHECKLIST.md]
3. **Otimizações**: Ver [03-ANALISE-TECNICA.md]
4. **Customização**: Criar templates próprios

---

**📞 Suporte:**
- Documentação completa: `docs/01-DOCUMENTO-EXECUTIVO.md`
- Troubleshooting: `docs/troubleshooting.md`
- Issues: https://github.com/darede-labs/reference-implementation-aws/issues
