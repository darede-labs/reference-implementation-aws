# Catálogo de Templates - Infraestrutura como Código

Catálogo completo de **Crossplane Compositions** disponíveis na plataforma IDP, equivalente a **módulos Terraform**.

---

## 📦 Templates Disponíveis

### 1. **S3 Bucket** ✅
**Composition:** `xs3bucket.darede.io`
**API:** `darede.io/v1alpha1/S3Bucket`

**Recursos criados:**
- ✅ S3 Bucket
- ✅ Bucket Versioning
- ✅ Server-Side Encryption (AES256)
- ✅ Public Access Block

**Parâmetros:**
```yaml
spec:
  bucketName: string (required)
  region: string (default: us-east-1)
  enableVersioning: bool (default: true)
  tags: map[string]string
```

**Status retornado:**
```yaml
status:
  bucketArn: string
  bucketId: string
```

**Exemplo:**
```yaml
apiVersion: darede.io/v1alpha1
kind: S3Bucket
metadata:
  name: my-app-storage
  namespace: crossplane-system
spec:
  bucketName: my-app-storage-bucket
  region: us-east-1
  enableVersioning: true
  tags:
    owner: platform-team
    app: my-app
```

---

### 2. **VPC Completa** ✅
**Composition:** `xvpc.darede.io`
**API:** `darede.io/v1alpha1/VPC`

**Recursos criados:**
- ✅ VPC
- ✅ Internet Gateway
- ✅ 2 Public Subnets (Multi-AZ)
- ✅ 2 Private Subnets (Multi-AZ)
- ✅ Route Tables
- ✅ Routes

**Parâmetros:**
```yaml
spec:
  vpcName: string (required)
  cidrBlock: string (default: 10.0.0.0/16)
  region: string (default: us-east-1)
  tags: map[string]string
```

**Subnets criadas automaticamente:**
- `10.0.1.0/24` - Public Subnet AZ-a
- `10.0.2.0/24` - Public Subnet AZ-b
- `10.0.10.0/24` - Private Subnet AZ-a
- `10.0.11.0/24` - Private Subnet AZ-b

**Status retornado:**
```yaml
status:
  vpcId: string
```

**Exemplo:**
```yaml
apiVersion: darede.io/v1alpha1
kind: VPC
metadata:
  name: my-app-vpc
  namespace: crossplane-system
spec:
  vpcName: my-app-vpc
  cidrBlock: 10.0.0.0/16
  region: us-east-1
  tags:
    environment: production
```

---

### 3. **Security Group** ✅
**Composition:** `xsecuritygroup.darede.io`
**API:** `darede.io/v1alpha1/SecurityGroup`

**Recursos criados:**
- ✅ Security Group
- ✅ Ingress: SSH (22)
- ✅ Ingress: HTTP (80)
- ✅ Ingress: HTTPS (443)
- ✅ Egress: ALL

**Parâmetros:**
```yaml
spec:
  groupName: string (required)
  description: string
  vpcId: string (required)
  region: string (default: us-east-1)
  tags: map[string]string
```

**Status retornado:**
```yaml
status:
  securityGroupId: string
```

**Exemplo:**
```yaml
apiVersion: darede.io/v1alpha1
kind: SecurityGroup
metadata:
  name: my-app-sg
  namespace: crossplane-system
spec:
  groupName: my-app-sg
  description: Security group for my app
  vpcId: vpc-0123456789
  region: us-east-1
  tags:
    app: my-app
```

---

### 4. **EC2 Instance** ✅
**Composition:** `xec2instance.darede.io`
**API:** `darede.io/v1alpha1/EC2Instance`

**Recursos criados:**
- ✅ EC2 Instance
- ✅ Root Volume (EBS GP3)

**Parâmetros:**
```yaml
spec:
  instanceName: string (required)
  instanceType: string (default: t3.micro)
    # Opções: t3.micro, t3.small, t3.medium, t3.large, t3.xlarge
  ami: string (default: Amazon Linux 2023)
  region: string (default: us-east-1)
  subnetId: string (required)
  securityGroupIds: []string
  keyName: string (SSH key pair)
  userData: string (base64 encoded)
  volumeSize: int (default: 20 GB)
  tags: map[string]string
```

**Status retornado:**
```yaml
status:
  instanceId: string
  publicIp: string
  privateIp: string
```

**Exemplo:**
```yaml
apiVersion: darede.io/v1alpha1
kind: EC2Instance
metadata:
  name: my-app-server
  namespace: crossplane-system
spec:
  instanceName: my-app-server
  instanceType: t3.small
  subnetId: subnet-0123456789
  securityGroupIds:
    - sg-0123456789
  keyName: my-keypair
  volumeSize: 30
  tags:
    environment: production
    app: my-app
```

---

### 5. **RDS Instance** ✅
**Composition:** `xrdsinstance.darede.io`
**API:** `darede.io/v1alpha1/RDSInstance`

**Recursos criados:**
- ✅ RDS Subnet Group
- ✅ RDS Instance (Postgres/MySQL/MariaDB)
- ✅ Storage encrypted
- ✅ Automated backups

**Parâmetros:**
```yaml
spec:
  instanceName: string (required)
  engine: string (default: postgres)
    # Opções: postgres, mysql, mariadb
  engineVersion: string (default: 15.4)
  instanceClass: string (default: db.t3.micro)
    # Opções: db.t3.micro, db.t3.small, db.t3.medium, db.t3.large
  allocatedStorage: int (default: 20, min: 20, max: 1000)
  dbName: string (required)
  masterUsername: string (default: admin)
  masterPasswordSecretName: string (required)
  region: string (default: us-east-1)
  subnetIds: []string (required, min 2 AZs)
  securityGroupIds: []string
  publiclyAccessible: bool (default: false)
  backupRetentionPeriod: int (default: 7 days)
  multiAz: bool (default: false)
  tags: map[string]string
```

**Status retornado:**
```yaml
status:
  instanceId: string
  endpoint: string
  port: int
```

**Exemplo:**
```yaml
apiVersion: darede.io/v1alpha1
kind: RDSInstance
metadata:
  name: my-app-db
  namespace: crossplane-system
spec:
  instanceName: my-app-db
  engine: postgres
  engineVersion: "15.4"
  instanceClass: db.t3.small
  allocatedStorage: 100
  dbName: myappdb
  masterUsername: dbadmin
  masterPasswordSecretName: my-app-db-password
  subnetIds:
    - subnet-0123456789  # AZ-a
    - subnet-9876543210  # AZ-b
  securityGroupIds:
    - sg-0123456789
  backupRetentionPeriod: 14
  multiAz: true
  tags:
    environment: production
    app: my-app
```

**⚠️ Criar secret com senha antes:**
```bash
kubectl create secret generic my-app-db-password \
  -n crossplane-system \
  --from-literal=password='SuaSenhaSegura123!'
```

---

## 🔗 Dependências Entre Recursos

### Ordem de criação recomendada:

```
1. VPC
   └─ Cria VPC + Subnets + Internet Gateway + Route Tables

2. Security Groups
   └─ Requer: vpcId da VPC criada

3. EC2 / RDS
   └─ Requer: subnetId(s) + securityGroupIds
```

### Exemplo de Stack Completa:

```yaml
# 1. VPC
apiVersion: darede.io/v1alpha1
kind: VPC
metadata:
  name: myapp-vpc
  namespace: crossplane-system
spec:
  vpcName: myapp-vpc
  cidrBlock: 10.0.0.0/16

---
# 2. Security Group (após VPC criada)
apiVersion: darede.io/v1alpha1
kind: SecurityGroup
metadata:
  name: myapp-sg
  namespace: crossplane-system
spec:
  groupName: myapp-sg
  vpcId: vpc-xxx  # Output do VPC acima

---
# 3. EC2 Instance (após VPC + SG criados)
apiVersion: darede.io/v1alpha1
kind: EC2Instance
metadata:
  name: myapp-server
  namespace: crossplane-system
spec:
  instanceName: myapp-server
  instanceType: t3.small
  subnetId: subnet-xxx  # Subnet da VPC
  securityGroupIds:
    - sg-xxx  # SG criado acima
```

---

## 📊 Comparação: Terraform Modules vs Crossplane Compositions

| Feature | Terraform Module | Crossplane Composition |
|---------|-----------------|------------------------|
| Definição | `.tf` files | XRD + Composition YAML |
| Provisionamento | `terraform apply` | GitOps + ArgoCD + Crossplane |
| State | terraform.tfstate | Kubernetes resources |
| Parâmetros | `variables.tf` | XRD spec schema |
| Outputs | `outputs.tf` | XRD status schema |
| Versionamento | Git tags | Composition labels |
| Reusabilidade | `module {}` block | Composite Resource |
| Deleção | `terraform destroy` | `kubectl delete` ou remove YAML |
| Drift detection | `terraform plan` | Crossplane reconciliation |

---

## 🚀 Como Usar os Templates

### 1. Via GitOps (Recomendado - Produção)

```bash
# 1. Criar arquivo YAML no repo
cd ~/infrastructureidp
mkdir -p vpc-resources

cat > vpc-resources/myapp-vpc.yaml <<EOF
apiVersion: darede.io/v1alpha1
kind: VPC
metadata:
  name: myapp-vpc
  namespace: crossplane-system
spec:
  vpcName: myapp-vpc
  cidrBlock: 10.0.0.0/16
  tags:
    environment: production
EOF

# 2. Commit e push
git add .
git commit -m "Add VPC for myapp"
git push origin main

# 3. ArgoCD sync automaticamente (< 3 min)
# 4. Crossplane provisiona na AWS (< 5 min)
```

### 2. Via kubectl (Dev/Teste)

```bash
kubectl apply -f myapp-vpc.yaml
kubectl get vpc myapp-vpc -n crossplane-system -w
```

### 3. Via Backstage Template (Futuro)

Templates Backstage serão criados para cada recurso, permitindo provisionamento via UI.

---

## 🔍 Monitoramento

### Ver todos os recursos provisionados:

```bash
export AWS_PROFILE=darede

# Ver todos os Composite Resources
kubectl get vpc,s3bucket,securitygroup,ec2instance,rdsinstance -n crossplane-system

# Ver recursos AWS individuais
kubectl get vpcinstance,subnet,internetgateway,routetable -A
kubectl get bucket -A
kubectl get instance -A  # EC2
kubectl get rdsinstance -A

# Ver status detalhado
kubectl describe vpc myapp-vpc -n crossplane-system
```

### Ver no ArgoCD UI:

- Application "infrastructure" → Tree View
- Ver hierarquia de recursos
- Status: Synced/OutOfSync, Healthy/Degraded

---

## 🗑️ Deleção de Recursos

### Deletar VPC completa (deleta subnets, IGW, routes automaticamente):

```bash
kubectl delete vpc myapp-vpc -n crossplane-system
```

### Deletar EC2:

```bash
kubectl delete ec2instance myapp-server -n crossplane-system
```

### Deletar RDS (⚠️ cria snapshot final por padrão):

```bash
kubectl delete rdsinstance myapp-db -n crossplane-system
```

**Crossplane garante:**
- ✅ Deleção de recursos filhos automaticamente
- ✅ Limpeza completa na AWS
- ✅ Sem recursos órfãos

---

## 📝 Validar Compositions Instaladas

```bash
export AWS_PROFILE=darede

# Ver todas as Compositions disponíveis
kubectl get composition

# Output esperado:
# NAME                       XR-KIND          XR-APIVERSION
# xs3bucket.darede.io        S3Bucket         darede.io/v1alpha1
# xvpc.darede.io             VPC              darede.io/v1alpha1
# xsecuritygroup.darede.io   SecurityGroup    darede.io/v1alpha1
# xec2instance.darede.io     EC2Instance      darede.io/v1alpha1
# xrdsinstance.darede.io     RDSInstance      darede.io/v1alpha1

# Ver XRDs (schemas)
kubectl get xrd

# Output esperado:
# NAME                        ESTABLISHED   OFFERED   AGE
# xs3buckets.darede.io        True          True      1h
# xvpcs.darede.io             True          True      1h
# xsecuritygroups.darede.io   True          True      1h
# xec2instances.darede.io     True          True      1h
# xrdsinstances.darede.io     True          True      1h
```

---

## 🎯 Próximos Templates (Roadmap)

- [ ] **EKS Cluster** (Cluster + Node Groups + OIDC)
- [ ] **Lambda Function** (Function + IAM Role + Trigger)
- [ ] **DynamoDB Table** (Table + GSI + Backup)
- [ ] **ALB** (Load Balancer + Target Groups + Listeners)
- [ ] **CloudFront** (Distribution + S3 Origin)
- [ ] **Route53** (Hosted Zone + Records)
- [ ] **IAM Role** (Role + Policies + Assume Role)

---

**Última atualização:** 11 de Dezembro de 2025
