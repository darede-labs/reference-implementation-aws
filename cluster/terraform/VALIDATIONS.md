# Input Validations

Este projeto implementa validações rigorosas de entrada para prevenir falhas em tempo de deploy causadas por limites de nomenclatura da AWS.

## 📋 Validações Implementadas

### 1. Validações Imediatas (locals.tf)

Estas validações são executadas **durante a fase de inicialização** do Terraform, antes mesmo do `plan`. Falham imediatamente se os valores estiverem incorretos.

#### Cluster Name
- **Limite**: 100 caracteres
- **Regex**: Deve começar com letra, apenas alfanuméricos e hífens
- **Arquivo**: `config.yaml` → `cluster_name`
- **Validação**: `locals._validate_cluster_name`

#### S3 Bucket Name (Terraform State)
- **Limites**: 3-63 caracteres
- **Regex**: Apenas lowercase, letras, números e hífens; começar/terminar com letra ou número
- **Arquivo**: `config.yaml` → `terraform_backend.bucket`
- **Validação**: `locals._validate_bucket_name`

#### Network Load Balancer
- **NLB Name**: Máximo 32 caracteres (`<cluster_name>-nlb`)
- **Target Groups**: Máximo 32 caracteres cada (`<cluster_name>-http`, `<cluster_name>-https`)
- **Validação**: `locals._validate_nlb_name`, `locals._validate_tg_names`

#### Cognito (quando habilitado)
- **User Pool**: Máximo 128 caracteres (`<cluster_name>-user-pool`)
- **Domain**: Máximo 63 caracteres (`<cluster_name>-idp`)
- **App Clients**: Máximo 128 caracteres cada
- **Validação**: `locals._validate_cognito_names`

#### Node Scaling
- **Regra**: `0 <= min_size <= desired_size <= max_size`
- **Disk Size**: 20-16384 GB
- **Validação**: `locals._validate_node_scaling`, `locals._validate_node_disk`

---

### 2. Validações em Preconditions (validations.tf)

Estas validações são executadas **durante o Terraform plan**, fornecendo mensagens de erro detalhadas com contexto completo.

#### EKS Cluster
```hcl
resource "null_resource" "validate_cluster_name"
```
- Máximo 100 caracteres
- Sem hífens consecutivos
- Padrão: `^[a-zA-Z][a-zA-Z0-9-]*$`

#### Load Balancer
```hcl
resource "null_resource" "validate_nlb_name"
resource "null_resource" "validate_target_group_names"
```
- NLB: 32 caracteres
- Target Groups: 32 caracteres

#### IAM Roles & Policies
```hcl
resource "null_resource" "validate_iam_role_names"
```
- IAM Role Names: 64 caracteres
- IAM Policy Names: 128 caracteres
- Valida todos os roles criados pelo módulo

#### VPC
```hcl
resource "null_resource" "validate_vpc_name"
```
- VPC Name (tag): 255 caracteres

#### Security Groups
```hcl
resource "null_resource" "validate_security_group_names"
```
- Security Group Names: 255 caracteres
- Name Prefix considerado

#### KMS
```hcl
resource "null_resource" "validate_kms_alias"
```
- KMS Alias: 256 caracteres (incluindo prefixo `alias/`)

#### Cognito
```hcl
resource "null_resource" "validate_cognito_names"
```
- User Pool: 128 caracteres
- Domain: 63 caracteres
- App Clients: 128 caracteres

#### Secrets Manager
```hcl
resource "null_resource" "validate_secrets_manager_names"
```
- Secret Names: 512 caracteres

#### S3 Buckets
```hcl
resource "null_resource" "validate_s3_bucket_name"
```
- Length: 3-63 caracteres
- Pattern: `^[a-z0-9][a-z0-9-]*[a-z0-9]$`
- Sem períodos/hífens consecutivos

#### Node Groups
```hcl
resource "null_resource" "validate_node_group_names"
resource "null_resource" "validate_karpenter_node_group_name"
```
- Node Group Names: 63 caracteres

#### Domain
```hcl
resource "null_resource" "validate_domain"
```
- Domain Name: 255 caracteres
- Pattern de domínio válido

---

## 🎯 Como Funciona

### Fase 1: Init/Refresh (locals.tf)
```
terraform init
terraform refresh
└─> Validações em locals executadas
    ├─ Falha imediata se inválido
    └─ Mensagem de erro clara com valor atual
```

### Fase 2: Plan (validations.tf)
```
terraform plan
└─> Preconditions executadas em null_resources
    ├─ Validação completa de todos os nomes derivados
    ├─ Mensagens de erro específicas por recurso
    └─ Output de sumário de validações
```

### Fase 3: Apply
```
terraform apply
└─> Apenas executado se todas as validações passarem
```

---

## 🔍 Verificando Validações

### Ver Sumário de Validações
```bash
terraform plan -out=tfplan
terraform show tfplan | grep validation_summary -A 20
```

Ou diretamente:
```bash
terraform output validation_summary
```

### Exemplo de Output
```json
{
  "cluster_name_length": 23,
  "cluster_name_limit": 100,
  "nlb_name_length": 27,
  "nlb_name_limit": 32,
  "terraform_bucket_length": 15,
  "terraform_bucket_limit": 63,
  "all_validations_passed": true,
  "recommendation": "Cluster name length is optimal."
}
```

---

## ❌ Exemplos de Erros

### Cluster Name Muito Longo
```
VALIDATION ERROR: cluster_name must be between 1 and 100 characters. Current: 105 characters.
```

### NLB Name Muito Longo
```
VALIDATION ERROR: NLB name 'my-extremely-long-cluster-name-nlb' is 35 characters (limit: 32). 
Shorten cluster_name in config.yaml.
```

### Bucket Name Inválido
```
VALIDATION ERROR: terraform_backend.bucket must be 3-63 characters, lowercase, 
start/end with letter or number. Current: 'My-Bucket-Name'
```

### Node Scaling Inválido
```
VALIDATION ERROR: Invalid node scaling config. Must satisfy: 0 <= min_size <= desired_size <= max_size. 
Current: min=5, desired=3, max=10
```

---

## 📏 Tabela de Limites AWS

| Recurso | Limite (chars) | Padrão | Validado Em |
|---------|----------------|--------|-------------|
| EKS Cluster | 100 | `^[a-zA-Z][a-zA-Z0-9-]*$` | locals + validations |
| Load Balancer | 32 | alfanumérico + hífen | locals + validations |
| Target Group | 32 | alfanumérico + hífen | locals + validations |
| IAM Role | 64 | alfanumérico + `+=,.@-` | validations |
| IAM Policy | 128 | alfanumérico + `+=,.@-` | validations |
| Security Group | 255 | qualquer | validations |
| KMS Alias | 256 | incluindo `alias/` | validations |
| Cognito User Pool | 128 | qualquer | locals + validations |
| Cognito Domain | 63 | lowercase + hífen | locals + validations |
| Secrets Manager | 512 | qualquer exceto `$` | validations |
| S3 Bucket | 3-63 | `^[a-z0-9][a-z0-9-]*[a-z0-9]$` | locals + validations |
| Node Group | 63 | alfanumérico + hífen | validations |
| Domain Name | 255 | padrão FQDN | validations |

---

## 🛠️ Adicionando Novas Validações

### 1. Validação Imediata (locals.tf)
Para valores que devem falhar rapidamente:

```hcl
locals {
  my_value = local.config_file.my_field
  
  _validate_my_value = (
    length(local.my_value) <= 50
  ) ? true : tobool("VALIDATION ERROR: my_field too long (limit: 50). Current: ${length(local.my_value)}")
}
```

### 2. Validação em Precondition (validations.tf)
Para validações complexas ou de múltiplos recursos:

```hcl
resource "null_resource" "validate_my_resource" {
  lifecycle {
    precondition {
      condition     = length(local.my_resource_name) <= 100
      error_message = "My resource name is too long. Limit: 100. Current: ${length(local.my_resource_name)}"
    }
  }
}
```

---

## 🎓 Boas Práticas

### ✅ Recomendações

1. **Cluster Name**: Use até 20 caracteres para evitar problemas com nomes derivados
   ```yaml
   cluster_name: "myapp-prod"  # ✅ 11 chars
   ```

2. **S3 Bucket**: Use prefixo organizacional consistente
   ```yaml
   terraform_backend:
     bucket: "myorg-tfstate"  # ✅ 14 chars
   ```

3. **Cognito Domain**: Mantenha curto (será público)
   ```yaml
   cluster_name: "myapp"  # → myapp-idp (9 chars) ✅
   ```

### ❌ Evite

1. **Nomes Muito Descritivos**
   ```yaml
   cluster_name: "my-organization-production-eks-cluster"  # ❌ 42 chars
   # Derivado: my-organization-production-eks-cluster-nlb = 45 chars (ERRO!)
   ```

2. **Caracteres Especiais**
   ```yaml
   cluster_name: "My_Cluster-2024!"  # ❌ Underscore e ! inválidos
   ```

3. **Uppercase em Buckets**
   ```yaml
   terraform_backend:
     bucket: "MyBucket"  # ❌ S3 requer lowercase
   ```

---

## 🔗 Referências

- [AWS Service Quotas - EKS](https://docs.aws.amazon.com/eks/latest/userguide/service-quotas.html)
- [AWS Service Quotas - ELB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-limits.html)
- [AWS S3 Bucket Naming Rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)
- [AWS IAM Naming Limits](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html)
- [Terraform Validation Functions](https://developer.hashicorp.com/terraform/language/expressions/custom-conditions)

---

## 📞 Troubleshooting

### Validação Falhou mas o Nome Parece OK?

1. Verifique **nomes derivados**: `<cluster_name>-nlb`, `<cluster_name>-http`, etc
2. Conte caracteres: `echo -n "my-cluster-name" | wc -c`
3. Verifique regex: `echo "My-Name" | grep -E '^[a-z0-9][a-z0-9-]*[a-z0-9]$'`

### Como Ver Todos os Nomes Que Serão Criados?

```bash
terraform plan | grep -E 'name\s*=' | sort | uniq
```

### Resetar Validações (se necessário)

```bash
terraform state rm 'null_resource.validate_*'
terraform plan  # Re-executará validações
```

---

**💡 Dica**: Execute `terraform validate && terraform plan` regularmente durante o desenvolvimento para capturar problemas de nomenclatura antes do deploy!
