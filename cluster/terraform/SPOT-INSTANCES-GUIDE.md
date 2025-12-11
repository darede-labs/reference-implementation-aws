# 💰 Guia: Configurar Spot Instances no EKS (Economia 70%)

> **Objetivo**: Reduzir custos de compute de $280/mês para $18/mês usando Spot instances
> **Trade-off**: Instâncias podem ser interrompidas com 2 min de aviso
> **Recomendado**: POC e Dev environments (não Prod crítico)

---

## 📊 COMPARAÇÃO DE CUSTOS

```
┌────────────────────────────────────────────────────┐
│  On-Demand vs Spot (2 nós t3.medium)               │
├────────────────────────────────────────────────────┤
│                                                    │
│  On-Demand (padrão):                               │
│    2 × $0.0416/h × 730h = $60.74/mês              │
│                                                    │
│  Spot (otimizado):                                 │
│    2 × $0.0125/h × 730h = $18.25/mês              │
│                                                    │
│  💰 ECONOMIA: $42.49/mês (70%)                     │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## 🔧 MODIFICAÇÕES NECESSÁRIAS

### Passo 1: Backup do main.tf Original

```bash
cd cluster/terraform
cp main.tf main.tf.backup
```

### Passo 2: Editar main.tf

Abra o arquivo:

```bash
nano main.tf
# ou
code main.tf
# ou
vim main.tf
```

**Encontre a seção `eks_managed_node_groups` (aproximadamente linha 68):**

```hcl
  # ANTES (On-Demand):
  eks_managed_node_groups = var.auto_mode ? {} : {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 3
      max_size     = 6
      desired_size = 4

      disk_size = 100

      labels = {
        pool = "system"
      }
    }
  }
```

**SUBSTITUA por (Spot):**

```hcl
  # DEPOIS (Spot):
  eks_managed_node_groups = var.auto_mode ? {} : {
    spot_nodes = {
      name = "spot-node-group"

      # Múltiplos tipos para maior disponibilidade
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]

      # Capacidade SPOT (chave da economia!)
      capacity_type  = "SPOT"

      # Reduzir quantidade para POC
      min_size     = 2
      max_size     = 4
      desired_size = 2

      # Reduzir disco para economizar storage
      disk_size = 50  # Reduzido de 100GB

      # Labels para identificação
      labels = {
        pool = "spot"
        workload = "general"
        cost-optimization = "enabled"
      }

      # Tags para Cluster Autoscaler (futuro)
      tags = {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.name}" = "owned"
      }
    }
  }
```

### Passo 3: (Opcional) Otimizar NAT Gateway

**Encontre a seção do módulo VPC (aproximadamente linha 104):**

```hcl
# ANTES (Multi-AZ HA):
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = false  # ← 3 NAT Gateways = $96/mês
  enable_dns_hostnames = true

  # ...
}
```

**SUBSTITUA por (Single NAT):**

```hcl
# DEPOIS (Single AZ - economia):
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway     = true
  single_nat_gateway     = true   # ← 1 NAT Gateway = $32/mês
  one_nat_gateway_per_az = false  # ← Economia de $64/mês!
  enable_dns_hostnames   = true

  # ...
}
```

**💡 Economia adicional: $64/mês (67% redução em NAT)**

---

## 🚀 APLICAR MUDANÇAS

### Validar Sintaxe

```bash
cd cluster/terraform
terraform fmt      # Formata código
terraform validate # Valida sintaxe
```

### Preview das Mudanças

```bash
export TF_VAR_cluster_name="idp-poc-cluster"
export TF_VAR_region="us-east-1"
export TF_VAR_auto_mode="false"

terraform plan -out=tfplan

# Você verá output similar:
# Plan: 48 to add, 0 to change, 0 to destroy.
#
# Changes:
#   + aws_eks_node_group.spot_nodes (new resource)
#     - capacity_type = "SPOT"
#     - instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
```

### Aplicar

```bash
terraform apply tfplan

# ⏱️ Tempo: 15-20 minutos
# 💰 Custos começam: ~$0.025/hora (2 nós Spot)
```

---

## ✅ VALIDAR SPOT INSTANCES

### Verificar Nós Criados

```bash
# Configurar kubectl
aws eks update-kubeconfig \
  --region us-east-1 \
  --name idp-poc-cluster

# Ver nós
kubectl get nodes -o wide

# Output esperado:
# NAME                         STATUS   ROLES    AGE   VERSION   CAPACITY-TYPE
# ip-10-0-xx-xx.ec2.internal   Ready    <none>   5m    v1.33.x   SPOT
# ip-10-0-xx-xx.ec2.internal   Ready    <none>   5m    v1.33.x   SPOT
```

### Verificar Labels Spot

```bash
kubectl get nodes --show-labels | grep spot

# Output deve conter:
# pool=spot,workload=general,eks.amazonaws.com/capacityType=SPOT
```

### Verificar Custo no AWS Console

```bash
# Via CLI
aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=active" \
  --query 'SpotInstanceRequests[*].[SpotPrice,InstanceType,State]' \
  --output table

# Output esperado:
# |  0.0125  |  t3.medium  |  active  |
# |  0.0125  |  t3.medium  |  active  |

# Via Console:
# https://console.aws.amazon.com/ec2/home?region=us-east-1#Instances:
# Filtrar por tag: kubernetes.io/cluster/idp-poc-cluster
# Ver coluna "Lifecycle": Spot
```

---

## ⚠️ IMPORTANTE: Spot Interruptions

### O que acontece quando Spot é interrompido?

```
1. AWS envia aviso: 2 minutos antes da interrupção
   ↓
2. Node Termination Handler (não incluído neste POC):
   - Drena pods gracefully
   - Marca nó como unschedulable
   ↓
3. Kubernetes agenda pods em outros nós
   ↓
4. Cluster Autoscaler (não incluído) provisiona novo nó
   ↓
5. Tempo de recuperação: 2-5 minutos
```

### Mitigações Implementadas

✅ **Múltiplos instance types**: Se t3.medium indisponível, usa t3a ou t2
✅ **Spread across AZs**: Reduz chance de interrupção simultânea
⚠️ **Não implementado neste POC**:
   - AWS Node Termination Handler
   - Cluster Autoscaler com fallback On-Demand
   - PodDisruptionBudgets

### Para Produção (adicionar depois):

```yaml
# 1. AWS Node Termination Handler
helm install aws-node-termination-handler \
  eks/aws-node-termination-handler \
  --namespace kube-system \
  --set enableSpotInterruptionDraining=true

# 2. Mixed capacity (50% On-Demand + 50% Spot)
eks_managed_node_groups = {
  on_demand = {
    capacity_type = "ON_DEMAND"
    desired_size = 2
  }
  spot = {
    capacity_type = "SPOT"
    desired_size = 2
  }
}
```

---

## 📊 MONITORAR SPOT SAVINGS

### Via AWS Cost Explorer

```bash
# Custo últimos 7 dias
aws ce get-cost-and-usage \
  --time-period Start=2024-12-03,End=2024-12-10 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --filter file://spot-filter.json

# Criar spot-filter.json:
cat > spot-filter.json << 'EOF'
{
  "Tags": {
    "Key": "eks.amazonaws.com/capacityType",
    "Values": ["SPOT"]
  }
}
EOF
```

### Dashboard Recomendado (Kubecost - futuro)

```bash
# Instalar Kubecost (opcional)
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace

# Acesso: kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
# Browser: http://localhost:9090
```

---

## 🐛 TROUBLESHOOTING

### Problema: Spot requests não fulfilled

```bash
# Ver status
aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=open,active"

# Se "price-too-low":
# Solução: Aumentar max spot price no terraform (default é on-demand price)

# Se "capacity-not-available":
# Solução: Adicionar mais instance types ao array
```

### Problema: Pods evicted frequentemente

```bash
# Ver eventos de eviction
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  --sort-by='.lastTimestamp'

# Causa: Spot interruptions frequentes
# Solução:
# 1. Adicionar mais diversidade de instance types
# 2. Usar PodDisruptionBudgets
# 3. Mix com On-Demand
```

### Problema: Node não drena antes de terminar

```bash
# Spot termina sem grace period
# Solução: Instalar AWS Node Termination Handler
# Ver seção "Para Produção" acima
```

---

## 📈 ECONOMIA TOTAL APLICANDO TUDO

```
┌────────────────────────────────────────────────────────┐
│  RESUMO DE ECONOMIA (vs configuração padrão)          │
├────────────────────────────────────────────────────────┤
│                                                        │
│  1. Spot instances (vs On-Demand)                     │
│     De: $280/mês → Para: $18/mês                       │
│     💰 Economiza: $262/mês (94%)                       │
│                                                        │
│  2. Reduzir nós (4→2)                                  │
│     Já contabilizado acima                             │
│                                                        │
│  3. Single NAT Gateway (vs 3 Multi-AZ)                 │
│     De: $96/mês → Para: $32/mês                        │
│     💰 Economiza: $64/mês (67%)                        │
│                                                        │
│  4. Reduzir EBS (100GB→50GB por nó)                    │
│     De: $40/mês → Para: $8/mês                         │
│     💰 Economiza: $32/mês (80%)                        │
│                                                        │
│  ══════════════════════════════════════════════════    │
│  ECONOMIA TOTAL: $358/mês                              │
│                                                        │
│  Custo Original:  $505/mês                             │
│  Custo Otimizado: $147/mês                             │
│  Redução: 71%                                          │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## 🎯 RECOMENDAÇÕES POR AMBIENTE

### POC (2 semanas)
✅ **100% Spot** - Economia máxima
✅ **Single NAT** - Custo mínimo
✅ **2 nós mínimo** - Suficiente para testes

### Development
✅ **100% Spot** - Economia alta, tolerante a interrupções
⚠️ **Considerar 2 NAT** - Se critical dev workloads
✅ **Auto-scaling 2-6 nós** - Flexibilidade

### Staging
⚠️ **Mix 50/50** (2 On-Demand + 2 Spot) - Balance cost/reliability
✅ **Multi-AZ NAT** - Testar produção
✅ **Auto-scaling 4-10 nós** - Load tests

### Production
❌ **Sem 100% Spot** - Muito arriscado
✅ **Mix 30/70** (3 On-Demand + 7 Spot) - Economia com segurança
✅ **Multi-AZ tudo** - Alta disponibilidade
✅ **Node Termination Handler** - Obrigatório
✅ **Cluster Autoscaler** - Resposta a demand

---

## 📚 REFERÊNCIAS

- [AWS Spot Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [EKS Managed Node Groups - Spot](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [Spot Instance Interruptions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html)
- [Node Termination Handler](https://github.com/aws/aws-node-termination-handler)

---

## ✅ CHECKLIST FINAL

```
□ Backup do main.tf original criado
□ eks_managed_node_groups modificado para Spot
□ Múltiplos instance types configurados
□ capacity_type = "SPOT" definido
□ desired_size reduzido para 2 nós
□ disk_size reduzido para 50GB
□ (Opcional) Single NAT Gateway configurado
□ terraform validate executado sem erros
□ terraform plan revisado
□ terraform apply bem-sucedido
□ kubectl get nodes mostra SPOT
□ Custos validados no AWS Console
```

---

**Economia esperada: $358/mês (71% redução) 💰**

**Próximo passo**: Continuar com instalação da plataforma seguindo `docs/02-GUIA-RAPIDO-POC.md`
