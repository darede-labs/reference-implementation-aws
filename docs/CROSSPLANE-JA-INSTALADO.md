# ✅ Crossplane JÁ está Instalado e Configurado

**Você NÃO precisa instalar nada manualmente!**

O Crossplane e todos os providers AWS necessários já vêm configurados e serão instalados automaticamente no primeiro deploy.

---

## 🚀 O que já está pronto

### 1. **Crossplane** instalado automaticamente
**Arquivo:** `packages/addons/values.yaml` (linhas 230-241)

```yaml
crossplane:
  enabled: true
  chartName: crossplane
  namespace: crossplane-system
  releaseName: crossplane
  defaultVersion: "1.20.0"
  chartRepository: "https://charts.crossplane.io/stable"
```

### 2. **Providers AWS** instalados automaticamente
**Arquivo:** `packages/addons/values.yaml` (linhas 243-254)

```yaml
crossplane-upbound-providers:
  enabled: true
  chartName: crossplane-aws-upbound
  namespace: crossplane-system
  releaseName: crossplane-upbound-providers
  defaultVersion: "3.0.0"
```

### 3. **TODOS os Providers AWS necessários**
**Arquivo:** `packages/crossplane-aws-upbound/values.yaml`

✅ **Networking:** ec2 (VPC, Subnets, Route Tables, IGW, NAT, Security Groups)
✅ **IAM:** iam (Roles, Policies para EKS e Node Groups)
✅ **EKS:** eks (Cluster, Node Groups, Addons, Fargate Profiles)
✅ **Storage:** s3, ebs, efs
✅ **Databases:** rds, dynamodb, elasticache
✅ **Compute:** autoscaling, elb, elbv2
✅ **Monitoring:** cloudwatch, cloudwatchlogs
✅ **Messaging:** sqs, sns
✅ **Serverless:** lambda
✅ **Secrets:** secretsmanager, kms

### 4. **Composições prontas**
**Arquivo:** `packages/crossplane-compositions/`

✅ **EKS Cluster completo:** VPC + Subnets + IAM + EKS + Node Groups
✅ **Template Backstage:** Pronto para criar EKS via UI

---

## 📋 Como Funciona

### Após `terraform apply` + `install.sh`:

1. ✅ **ArgoCD** detecta ApplicationSet
2. ✅ **Crossplane** é instalado automaticamente
3. ✅ **Providers AWS** são instalados (~2-3 minutos)
4. ✅ **ProviderConfig** é criado com IRSA (Pod Identity)
5. ✅ **Compositions** são aplicadas
6. ✅ **Tudo pronto para usar!**

---

## 🎯 Como Usar

### Opção 1: Via Backstage UI (Recomendado)

1. Acesse https://backstage.timedevops.click
2. Clique em **Create**
3. Selecione template **AWS EKS Cluster**
4. Preencha formulário:
   - Nome do cluster
   - Região
   - Versão Kubernetes
   - Tipo de instância
   - Número de nodes
5. Clique **Create**
6. ✨ Pull Request criado → Merge → EKS provisionado automaticamente

### Opção 2: Via kubectl (Avançado)

```bash
# Criar cluster EKS completo
cat <<EOF | kubectl apply -f -
apiVersion: platform.darede.io/v1alpha1
kind: EKSCluster
metadata:
  name: meu-cluster-dev
spec:
  clusterName: meu-cluster-dev
  region: us-east-1
  kubernetesVersion: "1.29"
  nodeGroupSize:
    min: 2
    max: 10
    desired: 3
  nodeInstanceType: t3.medium
EOF

# Verificar status
kubectl get ekscluster
kubectl describe ekscluster meu-cluster-dev

# Ver recursos criados
kubectl get managed
```

---

## 🔍 Verificar Instalação

### Verificar Crossplane

```bash
export AWS_PROFILE=darede

# Pods do Crossplane
kubectl get pods -n crossplane-system

# Providers instalados
kubectl get providers

# Deve mostrar TODOS esses providers como HEALTHY:
# - provider-aws-ec2
# - provider-aws-iam
# - provider-aws-eks
# - provider-aws-s3
# - provider-aws-rds
# - provider-aws-dynamodb
# ... etc
```

### Verificar ProviderConfig

```bash
kubectl get providerconfig
```

### Verificar Compositions

```bash
kubectl get composition
kubectl get xrd
```

---

## 📚 Templates Disponíveis

### Criados automaticamente:

1. **EKS Cluster Completo** (`packages/crossplane-compositions/eks-cluster-template-backstage.yaml`)
   - VPC completa
   - 2 Public Subnets
   - 2 Private Subnets
   - Internet Gateway
   - IAM Roles
   - EKS Cluster
   - Node Group

2. **S3 Bucket** (documentado em `docs/BACKSTAGE-PLATAFORMA-AWS.md`)

3. **RDS PostgreSQL** (documentado em `docs/BACKSTAGE-PLATAFORMA-AWS.md`)

4. **DynamoDB Table** (documentado em `docs/BACKSTAGE-PLATAFORMA-AWS.md`)

---

## 🛠️ Recursos AWS que VOCÊ pode provisionar via Crossplane

| Categoria | Recursos | Provider |
|-----------|----------|----------|
| **Networking** | VPC, Subnet, RouteTable, InternetGateway, NATGateway, SecurityGroup, NetworkACL | ec2 |
| **Compute** | EC2, AutoScaling Groups, Launch Templates | ec2, autoscaling |
| **Kubernetes** | EKS Cluster, Node Groups, Fargate Profiles, EKS Addons | eks |
| **Storage** | S3 Buckets, EBS Volumes, EFS File Systems | s3, ebs, efs |
| **Database** | RDS (PostgreSQL, MySQL, etc), DynamoDB, ElastiCache | rds, dynamodb, elasticache |
| **Load Balancing** | ALB, NLB, Classic ELB, Target Groups | elb, elbv2 |
| **IAM** | Roles, Policies, Users, Groups, Instance Profiles | iam |
| **Monitoring** | CloudWatch Alarms, Log Groups, Dashboards | cloudwatch, cloudwatchlogs |
| **Messaging** | SQS Queues, SNS Topics | sqs, sns |
| **Serverless** | Lambda Functions | lambda |
| **Secrets** | Secrets Manager, KMS Keys | secretsmanager, kms |

---

## ⚡ Quick Start: Criar seu primeiro EKS

```bash
# 1. Verificar se Crossplane está rodando
kubectl get pods -n crossplane-system

# 2. Verificar se providers estão HEALTHY
kubectl get providers

# 3. Criar cluster EKS via Backstage
# https://backstage.timedevops.click → Create → AWS EKS Cluster

# 4. OU via kubectl
kubectl apply -f - <<EOF
apiVersion: platform.darede.io/v1alpha1
kind: EKSCluster
metadata:
  name: dev-cluster
spec:
  clusterName: dev-cluster
  region: us-east-1
  kubernetesVersion: "1.29"
  nodeGroupSize:
    min: 2
    max: 5
    desired: 2
  nodeInstanceType: t3.small
EOF

# 5. Acompanhar criação (~15-20 minutos)
kubectl get ekscluster dev-cluster -w

# 6. Ver recursos criados na AWS
aws eks list-clusters --region us-east-1 --profile darede
```

---

## 🐛 Troubleshooting

### Provider não está HEALTHY

```bash
# Ver detalhes do provider
kubectl describe provider provider-aws-eks

# Ver logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-eks --tail=50
```

### Recurso não é criado

```bash
# Ver status do recurso
kubectl describe cluster meu-cluster

# Ver events
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'
```

### Permissões AWS

O Crossplane usa **Pod Identity (IRSA)** para acessar AWS.

Verificar role IAM:
```bash
kubectl get deploymentruntime -n crossplane-system
kubectl describe deploymentruntime upbound-aws-runtime-config
```

---

## 📖 Documentação Adicional

- **Guia Completo de Uso:** `docs/BACKSTAGE-PLATAFORMA-AWS.md`
- **Templates Backstage:** `docs/BACKSTAGE-USO-TEMPLATES.md`
- **Credenciais:** `docs/CREDENCIAIS.md`

---

## ✅ Checklist de Validação

Após `terraform apply` + `install.sh`, verificar:

- [ ] Crossplane pod está Running
- [ ] RBAC manager pod está Running
- [ ] Todos os providers estão HEALTHY
- [ ] ProviderConfig existe
- [ ] Compositions estão criadas
- [ ] XRD (CompositeResourceDefinition) estão criadas
- [ ] Template EKS aparece no Backstage

---

**🎉 Tudo pronto! Você pode começar a provisionar recursos AWS via Backstage imediatamente após o primeiro deploy!**

**Última atualização:** 11 de Dezembro de 2025
