# 🐛 Troubleshooting Progressivo: Problemas Reais Encontrados

> **Propósito**: Documentar CADA erro/problema encontrado durante implementação com solução EXATA aplicada
> **NÃO é**: Lista genérica de "possíveis problemas"
> **É**: Registro cronológico de problemas REAIS que aconteceram

---

## 📋 FORMATO DE CADA ENTRADA

```markdown
## PROBLEMA #XXX: Título do Problema

**Data encontrado:** YYYY-MM-DD HH:MM
**Fase:** [SETUP / CONFIG / TERRAFORM / INSTALL / DEPLOY / CLEANUP]
**Severidade:** 🔴 Bloqueante / 🟡 Warning / 🟢 Leve

### Contexto
O que você estava tentando fazer quando o erro aconteceu.

### Sintoma / Erro
```
Mensagem de erro EXATA (copiar e colar)
```

### Comando que causou
```bash
comando exato que gerou o erro
```

### Causa Raiz
Análise técnica do QUE causou o problema (não como resolver ainda).

### Solução Aplicada
Passos EXATOS executados para resolver:

1. Primeiro comando
2. Segundo comando
3. Etc

### Validação
Como confirmar que foi resolvido:
```bash
comando de validação
# output esperado
```

### Prevenção Futura
Como evitar que aconteça novamente:
- Ajuste em config
- Validação pré-emptiva
- Documentação atualizada

### Tempo Perdido
X minutos

### Referências
- [Link 1]
- [Link 2]

---
```

---

## 🚨 PROBLEMAS DOCUMENTADOS

### 📊 ESTATÍSTICAS

**Total de problemas:** 0 (atualizar conforme encontrar)
**Bloqueantes resolvidos:** 0
**Warnings ignorados:** 0
**Tempo total perdido:** 0 minutos

**Por categoria:**
- Setup: 0
- Config: 0
- Terraform: 0
- Install: 0
- Deploy: 0
- Cleanup: 0

---

## [EXEMPLO] PROBLEMA #001: VPC Limit Exceeded

**Data encontrado:** 2024-12-09 14:32
**Fase:** TERRAFORM
**Severidade:** 🔴 Bloqueante

### Contexto

Estava executando `terraform apply` para criar o cluster EKS. Região us-east-1 já tinha VPCs de outros projetos.

### Sintoma / Erro

```
Error: Error creating VPC: VpcLimitExceeded: The maximum number of VPCs has been reached.
	status code: 400, request id: a1b2c3d4-e5f6-7890-abcd-ef1234567890

  on .terraform/modules/vpc/main.tf line 15, in resource "aws_vpc" "this":
  15: resource "aws_vpc" "this" {
```

### Comando que causou

```bash
terraform apply tfplan
```

### Causa Raiz

Conta AWS tem limite padrão de **5 VPCs por região**. A conta já tinha 5 VPCs de projetos antigos, impossibilitando criar mais.

**Verificação do limite:**
```bash
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[*].VpcId'
```

**Output:**
```json
[
  "vpc-0a1b2c3d4e5f67890",  // projeto-antigo-1
  "vpc-1a2b3c4d5e6f78901",  // projeto-antigo-2
  "vpc-2a3b4c5d6e7f89012",  // default
  "vpc-3a4b5c6d7e8f90123",  // teste-abandonado
  "vpc-4a5b6c7d8e9f01234"   // lab-dev
]
```

Total: 5/5 VPCs (limite atingido)

### Solução Aplicada

**Opção 1: Deletar VPCs não utilizadas (escolhida)**

```bash
# 1. Identificar VPC não utilizada
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-3a4b5c6d7e8f90123" \
  --query 'Reservations[].Instances[].InstanceId'
# Output: [] (sem instâncias)

# 2. Deletar recursos dependentes primeiro
# 2.1 Internet Gateway
aws ec2 detach-internet-gateway --region us-east-1 \
  --internet-gateway-id igw-0abc123 \
  --vpc-id vpc-3a4b5c6d7e8f90123

aws ec2 delete-internet-gateway --region us-east-1 \
  --internet-gateway-id igw-0abc123

# 2.2 Subnets
aws ec2 delete-subnet --region us-east-1 --subnet-id subnet-abc123
aws ec2 delete-subnet --region us-east-1 --subnet-id subnet-def456

# 2.3 Security Groups (exceto default)
aws ec2 delete-security-group --region us-east-1 --group-id sg-abc123

# 3. Deletar VPC
aws ec2 delete-vpc --region us-east-1 --vpc-id vpc-3a4b5c6d7e8f90123
```

**Output:**
```
(sem output = sucesso)
```

**Opção 2: Aumentar limite via Support (não usado)**
- Abrir ticket no AWS Support
- Solicitar aumento para 10 VPCs
- Esperar 1-2 dias úteis

### Validação

```bash
# Verificar VPCs agora
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[*].VpcId' | jq 'length'
# Output: 4

# Tentar terraform apply novamente
terraform apply
```

**Resultado:** ✅ Sucesso - VPC criada com sucesso

### Prevenção Futura

1. **Antes de cada deploy:**
   ```bash
   # Verificar limites
   aws ec2 describe-account-attributes --region us-east-1 \
     --attribute-names vpc-max-number

   # Contar VPCs existentes
   aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs | length'
   ```

2. **Documentar no pré-requisitos:**
   - Adicionar checklist: "Verificar disponibilidade de VPC quota"
   - Script de validação pré-apply

3. **Limpeza periódica:**
   - Agendar revisão trimestral de VPCs não utilizadas
   - Tag todas VPCs com data de criação e projeto

### Tempo Perdido

**15 minutos** (diagnóstico 5 min + cleanup 8 min + re-apply 2 min)

### Referências

- [AWS VPC Limits](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html)
- [How to delete VPC](https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html)
- [Request limit increase](https://docs.aws.amazon.com/servicequotas/latest/userguide/request-quota-increase.html)

---

## [EXEMPLO] PROBLEMA #002: Spot Instance Insufficient Capacity

**Data encontrado:** 2024-12-09 14:47
**Fase:** TERRAFORM
**Severidade:** 🟡 Warning (resolveu automaticamente)

### Contexto

Terraform estava criando node group Spot. Região us-east-1a não tinha capacidade t3.medium Spot disponível temporariamente.

### Sintoma / Erro

**Não foi erro fatal**, apenas observado no CloudWatch Events:

```json
{
  "version": "0",
  "id": "abc123-def456",
  "detail-type": "EC2 Spot Instance Interruption Warning",
  "source": "aws.ec2",
  "account": "123456789012",
  "time": "2024-12-09T14:47:32Z",
  "region": "us-east-1",
  "resources": [],
  "detail": {
    "instance-id": "",
    "instance-action": "terminate",
    "reason": "InsufficientInstanceCapacity"
  }
}
```

### Comando que causou

```bash
terraform apply tfplan
```

Durante criação do `aws_eks_node_group.this["spot_nodes"]`

### Causa Raiz

**Spot capacity é dinâmica.** Temporariamente, AZ us-east-1a não tinha t3.medium Spot disponível.

**Por que não falhou:**
- Node group configurado com **múltiplos instance types**: `["t3.medium", "t3a.medium", "t2.medium"]`
- Node group configurado para **múltiplas AZs**: `[us-east-1a, us-east-1b, us-east-1c]`
- AWS automaticamente tentou próxima combinação

### Solução Aplicada

**Nenhuma ação necessária.** Terraform retentou automaticamente:

```
module.eks.aws_eks_node_group.this["spot_nodes"]: Still creating... [2m10s elapsed]
module.eks.aws_eks_node_group.this["spot_nodes"]: Still creating... [2m20s elapsed]
```

Nós foram criados em us-east-1b e us-east-1c ao invés de us-east-1a.

### Validação

```bash
kubectl get nodes -o wide
```

**Output:**
```
NAME                             STATUS   INTERNAL-IP    EXTERNAL-IP   AZ
ip-10-0-67-92.ec2.internal       Ready    10.0.67.92     3.x.x.x       us-east-1b
ip-10-0-98-143.ec2.internal      Ready    10.0.98.143    3.x.x.x       us-east-1c
```

✅ Nós criados em AZs alternativas, tudo funcionando.

### Prevenção Futura

**Já está implementado:**
- ✅ Múltiplos instance types no array
- ✅ Distribuição em 3 AZs
- ✅ AWS Node Termination Handler (para prod, monitorar interrupções)

**Para produção, adicionar:**

```hcl
# Aumentar diversidade de instance types
instance_types = [
  "t3.medium",
  "t3a.medium",
  "t2.medium",
  "t3.small",   # Fallback menor
  "m5.large"    # Fallback diferente family
]
```

### Tempo Perdido

**0 minutos** (resolveu automaticamente durante terraform apply)

### Referências

- [Spot Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [EKS Node Group Spot](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html#managed-node-group-capacity-types)
- [Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/)

---

## [EXEMPLO] PROBLEMA #003: Let's Encrypt Rate Limit

**Data encontrado:** 2024-12-09 15:22
**Fase:** INSTALL
**Severidade:** 🟡 Warning

### Contexto

Cert-manager estava tentando emitir certificados SSL para todos ingresses. Domínio `timedevops.click` já havia solicitado 4 certificados no dia (testes anteriores).

### Sintoma / Erro

```bash
kubectl describe certificate -n backstage backstage-tls
```

**Output:**
```
Events:
  Type     Reason        Age   From          Message
  ----     ------        ----  ----          -------
  Warning  FailedCreate  2m    cert-manager  Failed to create Order: 429 Too Many Requests: Error creating new order :: too many certificates already issued for exact set of domains: timedevops.click: see https://letsencrypt.org/docs/rate-limits/
```

### Comando que causou

```bash
./scripts/install.sh
```

Especificamente durante criação de Certificate resources pelo cert-manager.

### Causa Raiz

**Let's Encrypt Production tem rate limits:**
- **50 certificados/domínio/semana**
- **5 certificados/exato conjunto de domínios/semana**

Domínio `timedevops.click` já tinha solicitado:
1. backstage.timedevops.click (teste 1)
2. argocd.timedevops.click (teste 1)
3. backstage.timedevops.click (teste 2 - refazer)
4. argocd.timedevops.click (teste 2 - refazer)
5. **backstage.timedevops.click (ATUAL - NEGADO)** ← Limite atingido

### Solução Aplicada

**Opção 1: Aguardar 1 semana (não escolhida)**

**Opção 2: Usar staging Let's Encrypt temporariamente (escolhida)**

```bash
# 1. Editar ClusterIssuer para usar staging
kubectl edit clusterissuer letsencrypt-prod -n cert-manager
```

**Alterar:**
```yaml
# DE:
server: https://acme-v02.api.letsencrypt.org/directory

# PARA:
server: https://acme-staging-v02.api.letsencrypt.org/directory
```

```bash
# 2. Deletar certificates existentes para forçar reemissão
kubectl delete certificate --all -n backstage
kubectl delete certificate --all -n argocd

# 3. Aguardar recreate automático (cert-manager detecta)
kubectl get certificate -A --watch
```

**Resultado após 3 minutos:**
```
NAMESPACE   NAME            READY   AGE
backstage   backstage-tls   True    2m
argocd      argocd-tls      True    2m
```

**⚠️ Aviso:** Certificados staging geram warning no browser (não confiável), mas funcionam para testes.

**Opção 3: Usar subdomínios diferentes (alternativa)**
```yaml
# Trocar backstage.timedevops.click → backstage-v2.timedevops.click
# Evita rate limit do "exact set of domains"
```

### Validação

```bash
# Verificar certificado emitido
kubectl get certificate backstage-tls -n backstage -o yaml | grep issuer

# Output:
# issuer: (STAGING) Artificial Apricot R3
```

```bash
# Testar acesso (vai dar warning de certificado)
curl -k https://backstage.timedevops.click
```

**Browser:** Mostra "Not Secure" mas página carrega ✅

### Prevenção Futura

1. **Usar staging durante desenvolvimento:**
   - Padrão em ClusterIssuer deve ser staging
   - Mudar para production apenas em deploy final

2. **Documentar no guia:**
   ```markdown
   ⚠️ IMPORTANTE: Let's Encrypt produção tem limite de 5 certs/semana
   Para testes, use staging:
   clusterIssuer: letsencrypt-staging
   ```

3. **Monitorar rate limits:**
   ```bash
   # Verificar quantos certs foram solicitados
   curl "https://crt.sh/?q=%.timedevops.click&output=json" | jq 'length'
   ```

4. **Para produção:**
   - Planejar certificado wildcard: `*.timedevops.click`
   - Requer validação DNS (mais complexo mas evita rate limit)

### Tempo Perdido

**8 minutos** (diagnóstico 3 min + trocar para staging 2 min + aguardar 3 min)

### Referências

- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Cert-Manager Staging](https://cert-manager.io/docs/configuration/acme/#creating-a-basic-acme-issuer)
- [Check certificate log](https://crt.sh/)

---

## PROBLEMA #004: Sem permissão para criar GitHub App

**Data encontrado:** 2024-12-09 13:30
**Fase:** GITHUB
**Severidade:** 🔴 Bloqueante

### Contexto

Tentando criar GitHub App usando Backstage CLI ou interface web do GitHub na organização `darede-labs`.

### Sintoma / Erro

**Na interface GitHub:**
```
Error: You need to be an organization owner to create GitHub Apps
```

**Via Backstage CLI:**
```bash
npx @backstage/cli@latest create-github-app darede-labs

# Error: Forbidden - requires organization owner permissions
```

### Comando que causou

```bash
npx @backstage/cli@latest create-github-app darede-labs
```

### Causa Raiz

**GitHub requer permissão de Owner para criar Apps.** Membros com role "Member" não podem criar GitHub Apps, mesmo com permissões de admin em repositórios.

**Verificar sua role:**
```bash
# Via CLI
gh api /orgs/darede-labs/members/[SEU-USERNAME] | jq .role

# Via web
# https://github.com/orgs/darede-labs/people
# Procurar seu nome e ver a role
```

Roles do GitHub:
- ✅ **Owner**: Pode criar Apps
- ❌ **Member**: Não pode criar Apps
- ❌ **Billing manager**: Não pode criar Apps

### Solução Aplicada

**Opção 1: Solicitar upgrade para Owner (escolhida)**

1. Contactar Owner atual da organização
2. Solicitar upgrade temporário para Owner
3. Criar os GitHub Apps
4. (Opcional) Retornar para Member após criar

**Opção 2: Owner criar os Apps e compartilhar credenciais**

1. Owner acessa: `https://github.com/organizations/darede-labs/settings/apps/new`
2. Cria o App seguindo guia
3. Gera private key
4. Compartilha arquivo de credenciais de forma segura (1Password, etc)

**Opção 3: Usar GitHub App global (não recomendado para prod)**

Criar App na conta pessoal ao invés da org (menos seguro).

### Validação

```bash
# Verificar que você é Owner
gh api /orgs/darede-labs/memberships/[USERNAME]

# Output esperado:
# "role": "admin"  # ou "owner" dependendo da API
```

Depois criar o App novamente:
```bash
npx @backstage/cli@latest create-github-app darede-labs
# ✅ Deve funcionar agora
```

### Prevenção Futura

1. **Documentar no README**:
   ```markdown
   ### Pré-requisitos GitHub
   - ⚠️ Permissão de **Owner** na organização
   - Verificar antes de iniciar implementação
   ```

2. **Checklist pré-implementação**:
   - [ ] Verificar permissões GitHub
   - [ ] Verificar permissões AWS
   - [ ] Verificar ferramentas instaladas

3. **Para implementações em cliente**:
   - Solicitar permissão Owner antes de agendar
   - Ou pedir que Owner participe da criação dos Apps
   - Documentar quem tem permissão Owner

### Tempo Perdido

**15 minutos** (descoberta 5 min + solicitar permissão 10 min)

### Referências

- [GitHub Org Roles](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization)
- [Creating GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/apps/creating-github-apps/creating-github-apps/choosing-permissions-for-a-github-app)

---

## PROBLEMA #005: Service Control Policy bloqueando Secrets Manager

**Data encontrado:** 2024-12-09 14:26
**Fase:** INSTALL
**Severidade:** 🔴 CRÍTICA - Bloqueio total da instalação

### Contexto
Após criar o cluster EKS com sucesso (86 recursos) e instalar ArgoCD e External Secrets Operator, a sincronização de secrets do AWS Secrets Manager para o Kubernetes falhou. Os ExternalSecrets ficaram em estado `SecretSyncedError`.

### Sintoma / Erro
```bash
kubectl describe externalsecret hub-cluster-secret -n argocd

Events:
  Warning  UpdateFailed  AccessDeniedException:
  User: arn:aws:sts::948881762705:assumed-role/external-secrets-20251209164024175400000002/eks-idp-poc-cl-external-s-XXX
  is not authorized to perform: secretsmanager:GetSecretValue
  on resource: cnoe-ref-impl/config
  with an explicit deny in a service control policy
  status code: 400
```

### Comando que causou
```bash
# Script de instalação que aplica ExternalSecrets
echo "yes" | ./scripts/install.sh
```

### Causa Raiz
A conta AWS `948881762705` está em uma **AWS Organization** com **Service Control Policies (SCPs)** que negam explicitamente acesso ao AWS Secrets Manager.

**Hierarquia AWS:**
```
SCP (Organization) ← DENY explícito aqui
  ↓
IAM Policy (Role) ← ALLOW (mas não funciona)
  ↓
Pod Identity ← Bloqueado
```

**SCPs têm precedência absoluta sobre IAM policies.** Mesmo a role tendo permissões corretas, a SCP da organização sobrescreve e nega.

### Solução Aplicada
**Decisão:** Destruir infraestrutura e aguardar liberação da SCP

```bash
cd cluster/terraform
terraform destroy -auto-approve
```

**Motivo:** Evitar custos desnecessários (~$0.17/hora) enquanto aguarda resolução organizacional.

### Investigação Realizada

1. ✅ **Verificar se secret existe:**
   ```bash
   aws secretsmanager describe-secret --secret-id "cnoe-ref-impl/config"
   # ✅ Secret existe e ARN correto
   ```

2. ❌ **Problema encontrado na IAM policy:** Região errada
   ```json
   // ANTES: us-west-2 (errado)
   "Resource": ["arn:aws:secretsmanager:us-west-2:948881762705:secret:cnoe-ref-impl/*"]

   // DEPOIS: wildcard (corrigido)
   "Resource": ["arn:aws:secretsmanager:*:948881762705:secret:cnoe-ref-impl/*"]
   ```

3. ✅ **Atualizar política via Terraform:**
   ```bash
   terraform apply -target=module.external_secrets_pod_identity
   ```

4. ✅ **Reiniciar pods:**
   ```bash
   kubectl rollout restart deployment -n external-secrets
   ```

5. ❌ **Erro persiste:** Confirmado que é SCP, não IAM policy

### Alternativas Consideradas (não implementadas)

**Opção 1:** Ajustar SCP (requer Admin Organization)
```bash
# Adicionar exceção na SCP para:
"Resource": "arn:aws:secretsmanager:*:*:secret:cnoe-ref-impl/*"
```

**Opção 2:** Bypass com Kubernetes Secrets nativos
```bash
kubectl create secret generic hub-cluster -n argocd \
  --from-literal=name=idp-poc-cluster \
  --from-literal=server=https://kubernetes.default.svc
kubectl label secret hub-cluster -n argocd \
  argocd.argoproj.io/secret-type=cluster \
  environment=control-plane \
  path_routing=false
```

**Opção 3:** Usar SSM Parameter Store ao invés de Secrets Manager

### Validação
- [x] Secret existe no Secrets Manager
- [x] IAM policy corrigida (região wildcard)
- [x] Erro explicitamente menciona "SCP"
- [x] External Secrets Operator rodando (3/3 pods)
- [x] ArgoCD instalado (6/6 pods)
- [x] Não é problema de permissão IAM

### Prevenção Futura

1. **Checklist pré-implementação:**
   - [ ] Verificar SCPs da AWS Organization
   - [ ] Testar acesso aos serviços necessários via assume role
   - [ ] Confirmar que Secrets Manager não está bloqueado

2. **No guia de instalação:**
   ```markdown
   ### ⚠️ Requisito: Service Control Policies

   Se sua conta está em AWS Organization, verifique que as SCPs permitem:
   - `secretsmanager:GetSecretValue`
   - `secretsmanager:DescribeSecret`
   - Na região onde o cluster será criado

   Comando para testar:
   aws secretsmanager list-secrets --region us-east-1
   ```

3. **Teste de Pod Identity antes de provisionar:**
   ```bash
   # Criar role temporária e testar assume
   aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/test-pod-identity
   aws secretsmanager get-secret-value --secret-id cnoe-ref-impl/config
   ```

### Próximos Passos

1. **Solicitar ao Admin da Organization:**
   - Ajustar SCP para permitir Secrets Manager
   - Ou: Exceção para secrets `cnoe-ref-impl/*`
   - Região: us-east-1

2. **Após liberação:**
   ```bash
   # Reprovisionar cluster
   terraform apply

   # Validar acesso
   kubectl describe externalsecret hub-cluster-secret -n argocd
   # Deve mostrar: Status: SecretSynced
   ```

### Tempo Perdido
- Instalação ArgoCD/External Secrets: 10 min
- Investigação erro: 10 min
- Correção IAM policy + testes: 10 min
- **Total: 30 minutos**

### Custo Gerado
- Cluster rodou ~45 min antes do destroy
- EKS Control Plane: $0.10/h × 0.75h = $0.075
- 2× Spot t3.medium: $0.025/h × 0.75h = $0.019
- NAT Gateway: $0.045/h × 0.75h = $0.034
- **Total aproximado: $0.13**

### Referências
- [AWS SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [IAM Policy Evaluation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [External Secrets AWS Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)

---

## 📝 TEMPLATE PARA NOVOS PROBLEMAS

### PROBLEMA #XXX: Título Descritivo

**Data encontrado:** YYYY-MM-DD HH:MM
**Fase:** [SETUP / CONFIG / TERRAFORM / INSTALL / DEPLOY / CLEANUP]
**Severidade:** 🔴 / 🟡 / 🟢

### Contexto
[O que você estava fazendo]

### Sintoma / Erro
```
[Copiar erro EXATO]
```

### Comando que causou
```bash
comando
```

### Causa Raiz
[Análise técnica]

### Solução Aplicada
1. Passo 1
2. Passo 2

### Validação
```bash
comando de validação
```

### Prevenção Futura
- Item 1
- Item 2

### Tempo Perdido
X minutos

### Referências
- [Link]

---

## 🎯 DIRETRIZES DE USO

### Quando adicionar aqui?

✅ **SIM - Adicione:**
- Qualquer erro que impediu progresso
- Warnings que causaram confusão
- Problemas que levaram >5 min para resolver
- Erros não documentados em troubleshooting.md original

❌ **NÃO - Não adicione:**
- Erros por typo óbvio (esqueceu vírgula, etc)
- Problemas já documentados no troubleshooting.md
- Issues de infraestrutura externa (GitHub down, AWS outage)

### Como usar este documento?

**Durante implementação:**
1. Encontrou problema → Documente IMEDIATAMENTE
2. Não espere resolver para documentar
3. Use template acima
4. Seja ESPECÍFICO (comandos exatos, erros completos)

**Antes de nova implementação:**
1. Leia todos problemas desta categoria
2. Execute validações preventivas sugeridas
3. Evite repetir erros já solucionados

**Para melhorar documentação principal:**
- Problemas recorrentes → Adicionar ao guia principal
- Problemas com solução rápida → Adicionar ao troubleshooting.md
- Problemas de design → Considerar ajuste na arquitetura

---

## 🔍 ÍNDICE DE PROBLEMAS (Atualizar conforme adicionar)

### Por Severidade
- 🔴 Bloqueantes: 0
- 🟡 Warnings: 0
- 🟢 Leves: 0

### Por Fase
- **Setup**: 0
- **Config**: 0
- **Terraform**: 0
- **Install**: 0
- **Deploy**: 0
- **Cleanup**: 0

### Por Tipo
- **Limites AWS**: 0
- **Networking**: 0
- **Permissões IAM**: 0
- **Kubernetes**: 0
- **DNS/Certificados**: 0
- **GitHub**: 0
- **Custo**: 0
- **Performance**: 0

---

**Última atualização:** 2024-12-09
**Total problemas documentados:** 0 (3 exemplos template)
**Implementações bem-sucedidas:** 0
