# AWS MCP Servers - Configuração Completa

## 📦 Servers Instalados

### 1. **AWS Documentation** ✅
**Comando**: `uvx awslabs.aws-documentation-mcp-server@latest`

**Descrição**: Acesso à documentação oficial da AWS
**Uso**: Consultar docs, APIs, best practices, limites de serviços
**Exemplo**:
```
> Search AWS documentation for EKS best practices
> What are the limits for EKS clusters?
```

---

### 2. **AWS EKS** 🆕
**Comando**: `uvx awslabs.eks-mcp-server@latest`

**Descrição**: Gerenciamento de clusters EKS
**Capacidades**:
- Listar clusters EKS
- Descrever configurações de clusters
- Verificar node groups e Fargate profiles
- Consultar add-ons instalados
- Verificar status de pods e workloads

**Uso**:
```
> List all EKS clusters in my account
> Describe cluster idp-poc-darede-cluster
> What node groups exist in my cluster?
> Show me the EKS add-ons installed
```

---

### 3. **AWS ECS** 🆕
**Comando**: `uvx awslabs.ecs-mcp-server@latest`

**Descrição**: Gerenciamento de containers ECS/Fargate
**Capacidades**:
- Listar clusters ECS
- Descrever services e tasks
- Verificar task definitions
- Monitorar container instances
- Consultar logs de containers

**Uso**:
```
> List all ECS clusters
> Show me running tasks in cluster X
> Describe service Y in ECS
> What task definitions are available?
```

---

### 4. **AWS IAM** 🆕
**Comando**: `uvx awslabs.iam-mcp-server@latest`

**Descrição**: Gerenciamento de identidades e permissões
**Capacidades**:
- Listar users, roles, policies
- Verificar permissões de roles
- Analisar políticas IAM
- Verificar OIDC providers
- Consultar service accounts (IRSA)
- Validar least privilege

**Uso**:
```
> List all IAM roles with EKS in the name
> What policies are attached to role crossplane-irsa?
> Show me OIDC providers
> Validate IAM policy for least privilege
> What permissions does role X have?
```

---

### 5. **AWS Pricing** 🆕
**Comando**: `uvx awslabs.aws-pricing-mcp-server@latest`

**Descrição**: Consulta de preços de serviços AWS
**Capacidades**:
- Consultar preços de instâncias EC2
- Comparar custos de RDS
- Verificar preços de EKS/ECS
- Calcular custos de storage (S3, EBS)
- Comparar spot vs on-demand

**Uso**:
```
> What's the price of t3a.medium in us-east-1?
> Compare costs: t3.medium vs t3a.medium spot instances
> Show me RDS pricing for db.t4g.micro
> What's cheaper: EKS with Fargate or EC2 nodes?
```

---

### 6. **AWS Billing & Cost Management** 🆕
**Comando**: `uvx awslabs.billing-cost-management-mcp-server@latest`

**Descrição**: Análise de custos e billing
**Capacidades**:
- Consultar custos atuais
- Analisar breakdown por serviço
- Verificar forecasts
- Consultar budgets e alertas
- Comparar períodos (MoM, YoY)
- Analisar tags de custo (cloud_economics)

**Uso**:
```
> What's my current AWS spending this month?
> Show me cost breakdown by service
> What are the top 5 most expensive resources?
> Show me costs for tag cloud_economics=Darede-IDP::devops
> Compare costs: this month vs last month
```

---

## 🎯 Uso Geral dos MCP Servers

### Comandos Integrados no Chat do Cursor

Os MCP servers são **automaticamente usados** pelo Cursor quando você faz perguntas relevantes:

**Exemplos automáticos**:
```
# Cursor usa AWS EKS MCP automaticamente:
> Show me the status of my EKS cluster

# Cursor usa AWS IAM MCP automaticamente:
> What roles have access to my EKS cluster?

# Cursor usa AWS Billing MCP automaticamente:
> How much am I spending on EKS this month?

# Cursor usa AWS Pricing MCP automaticamente:
> What's cheaper: Fargate or EC2 for my workload?

# Cursor usa AWS Documentation MCP automaticamente:
> What are the best practices for EKS networking?
```

### Forçar uso de MCP específico

Se quiser forçar o uso de um MCP específico:
```
@AWS-EKS list my clusters
@AWS-IAM show roles for EKS
@AWS-Billing what's my current spend?
```

---

## 🔐 Autenticação AWS

Os MCP servers AWS usam o **profile e region padrão** do seu sistema:

### Como Funciona

Segue a ordem de precedência do AWS CLI:
1. Variáveis de ambiente: `AWS_PROFILE`, `AWS_REGION`
2. Profile `[default]` no `~/.aws/config`
3. Credenciais `[default]` no `~/.aws/credentials`

### Uso com Profile Específico

```bash
# Para projeto Darede
export AWS_PROFILE=darede
export AWS_REGION=us-east-1
aws sso login --profile darede

# Para outro projeto
export AWS_PROFILE=cliente-xpto
export AWS_REGION=sa-east-1
aws sso login --profile cliente-xpto

# Verificar profile atual
aws sts get-caller-identity
```

**📖 Guia Completo**: Ver [`AWS-MCP-PROFILE-CONFIG.md`](AWS-MCP-PROFILE-CONFIG.md)

---

## 📋 Lista Completa de MCP Servers Configurados

| Server | Status | Descrição |
|--------|--------|-----------|
| AWS Documentation | ✅ | Docs oficiais AWS |
| AWS EKS | 🆕 | Gerenciamento EKS |
| AWS ECS | 🆕 | Gerenciamento ECS/Fargate |
| AWS IAM | 🆕 | Identidades e permissões |
| AWS Pricing | 🆕 | Consulta de preços |
| AWS Billing | 🆕 | Análise de custos |
| GitHub | ✅ | Integração GitHub |
| Terraform | ✅ | Terraform Registry + HCP |
| Kubernetes | ✅ | kubectl via MCP |
| Task Master AI | ✅ | Gerenciamento de tasks |

**Total**: 10 MCP servers ativos

---

## 🚀 Casos de Uso Práticos

### 1. Troubleshooting EKS

```
> @AWS-EKS describe cluster idp-poc-darede-cluster
> @AWS-EKS show node groups
> @kubernetes get pods -n argocd
> @AWS-IAM what roles are attached to node groups?
```

### 2. Análise de Custos

```
> @AWS-Billing show me costs for the last 7 days
> @AWS-Billing breakdown by service
> @AWS-Pricing compare t3.medium vs t3a.medium spot
> @AWS-Billing show costs tagged with cloud_economics=Darede-IDP
```

### 3. Validação de Segurança

```
> @AWS-IAM list all roles with admin access
> @AWS-IAM show policies attached to crossplane-role
> @AWS-IAM validate least privilege for role X
> @AWS-EKS show security groups for my cluster
```

### 4. Planejamento de Arquitetura

```
> @AWS-Documentation what are EKS best practices?
> @AWS-Pricing calculate monthly cost: 3 t3a.medium nodes + NLB + RDS
> @AWS-EKS what add-ons are available?
> @Terraform search for EKS module examples
```

### 5. Monitoramento e Observabilidade

```
> @AWS-EKS show cluster health
> @AWS-ECS list failed tasks
> @kubernetes get events -n kube-system
> @AWS-Billing alert me if costs exceed $200
```

---

## ⚙️ Configuração

### Arquivo de Configuração

**Localização**: `~/.cursor/mcp.json`

### Estrutura

```json
{
  "mcpServers": {
    "AWS EKS": {
      "command": "uvx awslabs.eks-mcp-server@latest",
      "env": {},
      "args": []
    },
    // ... outros servers
  }
}
```

**Nota**: `env` vazio = usa profile/region padrão do sistema (flexível)

### Como Configurar Profile/Region

**Opção 1**: Variáveis de ambiente (recomendado para multi-projeto)
```bash
export AWS_PROFILE=seu-profile
export AWS_REGION=sua-region
```

**Opção 2**: Profile default no `~/.aws/config`

**Opção 3**: direnv por diretório (`.envrc`)

**📖 Guia Completo**: Ver [`AWS-MCP-PROFILE-CONFIG.md`](AWS-MCP-PROFILE-CONFIG.md)

### Variáveis de Ambiente (Opcionais)

| Variável | Descrição |
|----------|-----------|
| `AWS_PROFILE` | Profile a usar (se não setar, usa default) |
| `AWS_REGION` | Região (se não setar, usa região do profile) |
| `FASTMCP_LOG_LEVEL` | Nível de log: ERROR, INFO, DEBUG |

---

## 🔄 Atualização

Os MCP servers são atualizados automaticamente quando usa `@latest`:

```bash
# Forçar atualização (se necessário)
uvx --reinstall awslabs.eks-mcp-server@latest
uvx --reinstall awslabs.ecs-mcp-server@latest
uvx --reinstall awslabs.iam-mcp-server@latest
```

---

## 🧪 Testar Instalação

Após recarregar o Cursor (`Cmd+Shift+P` → "Reload Window"):

```
> List available MCP servers
```

Deve mostrar:
```
✅ AWS Documentation
✅ AWS EKS
✅ AWS ECS
✅ AWS IAM
✅ AWS Pricing
✅ AWS Billing
✅ GitHub
✅ Terraform
✅ Kubernetes
✅ Task Master AI
```

**Teste funcional**:
```
> @AWS-EKS list clusters
> @AWS-IAM list roles
> @AWS-Billing show current month costs
```

---

## 📚 Documentação Oficial

- **AWS Labs MCP**: https://github.com/awslabs/mcp
- **EKS MCP Server**: https://github.com/awslabs/mcp/tree/main/src/eks-mcp-server
- **ECS MCP Server**: https://github.com/awslabs/mcp/tree/main/src/ecs-mcp-server
- **IAM MCP Server**: https://github.com/awslabs/mcp/tree/main/src/iam-mcp-server
- **Pricing MCP Server**: https://github.com/awslabs/mcp/tree/main/src/aws-pricing-mcp-server
- **Billing MCP Server**: https://github.com/awslabs/mcp/tree/main/src/billing-cost-management-mcp-server

---

## 🆘 Troubleshooting

### MCP server não responde

1. **Verificar AWS credentials**:
```bash
# Ver profile atual
echo $AWS_PROFILE

# Ver identidade
aws sts get-caller-identity
```

2. **Login SSO** (se necessário):
```bash
# Com profile específico
aws sso login --profile seu-profile

# Ou com profile atual
aws sso login
```

3. **Verificar se profile está exportado**:
```bash
# Setar profile
export AWS_PROFILE=seu-profile
export AWS_REGION=sua-region

# Reabrir Cursor com profile setado
```

4. **Recarregar Cursor**:
```
Cmd+Shift+P → "Reload Window"
```

### Erro de permissões

Verificar se o profile `darede` tem permissões para:
- EKS: `eks:DescribeCluster`, `eks:ListClusters`
- ECS: `ecs:DescribeClusters`, `ecs:ListTasks`
- IAM: `iam:ListRoles`, `iam:GetRole`
- Pricing: `pricing:GetProducts`
- Billing: `ce:GetCostAndUsage`

### Server específico não funciona

```bash
# Testar manualmente
uvx awslabs.eks-mcp-server@latest

# Verificar logs
# Help > Toggle Developer Tools > Console
```

---

## 💡 Dicas de Uso

1. **Use linguagem natural**: Os MCP servers entendem perguntas em português ou inglês
2. **Combine servers**: Cursor pode usar múltiplos MCPs para responder uma pergunta
3. **Context-aware**: MCPs têm acesso ao código e arquivos do projeto
4. **Automatizado**: Não precisa especificar o MCP, Cursor escolhe automaticamente
5. **Seguro**: Nunca expõe credenciais nos chats

---

## ✅ Próximos Passos

1. ✅ **Recarregar Cursor**: `Cmd+Shift+P` → "Reload Window"
2. ✅ **Testar MCPs**: `List available MCP servers`
3. ✅ **Explorar**: Fazer perguntas sobre EKS, custos, IAM, etc
4. ✅ **Integrar**: Usar MCPs no desenvolvimento do IDP

---

**Criado em**: 2026-01-19
**Versão**: 1.0
**Status**: ✅ Configuração completa
