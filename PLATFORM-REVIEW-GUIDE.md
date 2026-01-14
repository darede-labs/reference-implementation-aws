# Guia de Revisão - Internal Developer Platform (IDP)

## 1. Overview Executivo

**Objetivo:** IDP self-service em AWS para desenvolvedores provisionarem infraestrutura via Backstage

**Stack Principal:**
- **Portal:** Backstage (CNOE-IO image) com autenticação Cognito
- **Orquestração:** EKS (Kubernetes auto-mode)
- **IaC:** Terraform via Backstage Scaffolder Actions
- **GitOps:** ArgoCD (disabled no momento, modo direto)
- **Crossplane:** Provisionamento declarativo (opcional)

**Status Atual:** ✅ Funcional - templates criando recursos AWS via Backstage

---

## 2. Arquitetura Implementada

### 2.1 Componentes Core

```
┌─────────────────────────────────────────────────────────────┐
│                        Usuários                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  Route53 + NLB (TLS/ACM) → backstage.timedevops.click       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  AWS Cognito (OIDC Provider)                                 │
│  - User Pool com email como username                        │
│  - Sincronização automática de users do GitHub catalog      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  EKS Cluster (Kubernetes auto-mode)                          │
│  ├─ Backstage (2 pods) + PostgreSQL                         │
│  ├─ ingress-nginx (com external-dns)                        │
│  ├─ AWS Load Balancer Controller                            │
│  └─ Backstage ServiceAccount → IRSA → IAM Role              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  Backstage Scaffolder Actions                                │
│  - terraform:apply (cria recursos)                           │
│  - terraform:destroy (remove recursos)                       │
│  - Estado: S3 bucket (poc-idp-tfstate)                      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  Recursos AWS Provisionados                                  │
│  - EC2 com SSM (sem SSH)                                     │
│  - S3 buckets                                                │
│  - VPCs                                                      │
│  - RDS databases                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Fluxo de Autenticação

1. User acessa Backstage → Redirect para Cognito Hosted UI
2. Cognito valida credenciais (email/password)
3. OIDC flow retorna token JWT
4. Backstage valida token e cria sessão
5. User identificado via `emailMatchingUserEntityProfileEmail`

### 2.3 Fluxo de Provisionamento (Terraform)

1. User preenche template no Backstage UI (`/create`)
2. Scaffolder action `terraform:apply` executa dentro do pod
3. Pod assume IAM role via IRSA (`backstage-terraform-irsa`)
4. Terraform provisiona recursos na AWS
5. State salvo em S3 bucket com chave única por recurso
6. Metadata registrado para posterior deleção

---

## 3. Decisões Arquiteturais e Trade-offs

### 3.1 ✅ Backstage como Frontend (vs portal custom)

**Por quê:**
- Ecossistema maduro com plugins prontos
- Software Catalog nativo (usuarios, componentes, APIs)
- Scaffolder Actions para Terraform já existem
- CNOE-IO mantém imagem curada

**Trade-off:**
- Menos flexibilidade de UI
- Curva de aprendizado inicial

---

### 3.2 ✅ Terraform via Scaffolder Actions (vs Crossplane)

**Por quê:**
- Desenvolvedores já conhecem Terraform
- Templates reutilizáveis (skeleton/)
- Controle total do código gerado
- State management explícito (S3)

**Trade-off:**
- Não é GitOps declarativo
- Terraform executa dentro do pod (não ideal para long-running)
- Precisa IRSA para credenciais AWS

---

### 3.3 ✅ IRSA para AWS Credentials (vs secret keys)

**Implementação:**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::948881762705:role/backstage-terraform-irsa
```

**IAM Role Policies:**
- PowerUserAccess (AWS managed)
- Custom policy para S3 tfstate (GetObject, PutObject, DeleteObject, ListBucket)

**Por quê:**
- Sem credentials estáticas
- Rotação automática de tokens (STS)
- Privilégio mínimo via IAM policies

**Problema Resolvido:**
- ❌ Inicial: Terraform falhava com 403 no S3 (ServiceAccount sem annotation)
- ✅ Fix: Annotation IRSA adicionada ao install.sh

---

### 3.4 ✅ Cognito User Sync (vs gestão manual)

**Implementação:**
- Catalog `users-catalog.yaml` no GitHub
- Script `manage-users.sh` lê YAML e cria users no Cognito
- Senhas geradas automaticamente e exibidas

**Por quê:**
- Single source of truth (GitHub)
- Automação via install.sh
- Consistência entre Backstage catalog e autenticação

---

### 3.5 ⚠️ EC2 com Public IP (vs VPC Endpoints)

**Implementação Atual:**
```hcl
variable "associate_public_ip" {
  default = true  # Para SSM funcionar
}
```

**Por quê:**
- SSM precisa de conectividade para endpoints AWS
- Sem VPC endpoints (ssm, ssmmessages, ec2messages), precisa internet
- Public IP é mais simples para POC

**Trade-off:**
- ❌ Instâncias expostas na internet (security group controla acesso)
- ❌ Não é best practice para produção
- ✅ Alternativa correta: VPC Endpoints (custo adicional)

**Pergunta para o Expert:** Como você resolveria SSM em private subnets sem VPC endpoints? Interface endpoints vs Gateway endpoints?

---

### 3.6 ✅ NLB gerenciado via Terraform (vs Kubernetes Service LoadBalancer)

**Problema Original:**
- ingress-nginx criava NLB via Service type=LoadBalancer
- `terraform destroy` não removia NLB (recurso órfão)

**Solução:**
- `cluster/terraform/nlb.tf` cria NLB explicitamente
- Target groups apontam para worker nodes
- Lifecycle gerenciado pelo Terraform

**Status:** ⚠️ Implementado mas não integrado com install.sh ainda

**Pergunta para o Expert:** Vale a pena gerenciar NLB via Terraform ou deixar Kubernetes gerenciar? Trade-offs?

---

### 3.7 ⚠️ Modo Direto vs GitOps (ArgoCD disabled)

**Decisão Atual:**
- ArgoCD não instalado (timeout issues)
- Backstage instalado via Helm direto (`install.sh`)

**Por quê:**
- Foco no Backstage/templates funcionando primeiro
- ArgoCD adiciona complexidade (sync loops, health checks)

**Trade-off:**
- ❌ Sem drift detection
- ❌ Sem rollback automático
- ✅ Deploy mais simples e rápido

**Pergunta para o Expert:** Em produção, ArgoCD é mandatório para IDP ou Helm direto é aceitável?

---

## 4. Desafios Técnicos Resolvidos

### 4.1 ❌→✅ Login Failure (Cognito)

**Problema:** Backstage rejeitando login apesar de credenciais corretas

**Root Cause:**
- Cognito configurado com `username_attributes = ["email"]`
- Backstage tentava login com UUID gerado ao invés de email
- Password policy complexa causava confusão

**Fix:**
1. Verificar `UserStatus` no Cognito (FORCE_CHANGE_PASSWORD vs CONFIRMED)
2. Usar `admin-set-user-password --permanent` para confirmar users
3. Credentials corretos: `matheus.andrade@darede.com.br` / `Admin@123456`

---

### 4.2 ❌→✅ Templates Missing (Catalog vazio)

**Problema:** Templates não apareciam no Backstage UI

**Root Cause:**
- ConfigMap `backstage-app-config` apontava para templates removidos/vazios
- `terraform-destroy/template.yaml` estava vazio (0 bytes)
- Template correto (`resource-manager`) não estava no catalog

**Fix:**
1. Corrigir `install.sh` com URLs corretos:
   - `terraform-s3`, `terraform-ec2-ssm`, `terraform-vpc`, `terraform-rds`, `resource-manager`
2. Remover referências a templates inexistentes
3. Reinstalar Backstage via Helm (clean state)

---

### 4.3 ❌→✅ Terraform 403 Forbidden (S3 Access)

**Problema:** Terraform falhava ao acessar S3 tfstate bucket

**Root Cause:**
- Backstage ServiceAccount sem annotation IRSA
- Pods não assumiam IAM role `backstage-terraform-irsa`

**Fix:**
```yaml
# install.sh - Helm values
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/backstage-terraform-irsa
```

**Verificação:**
```bash
kubectl exec -n backstage <pod> -- env | grep AWS
# AWS_ROLE_ARN=arn:aws:iam::948881762705:role/backstage-terraform-irsa
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

---

### 4.4 ❌→✅ SSM Connection Failed (EC2)

**Problema:** `aws ssm start-session` falhava mesmo com IAM role correto

**Root Cause:**
- Instância sem IP público
- VPC sem endpoints SSM (ssm, ssmmessages, ec2messages)
- SSM agent não conseguia se registrar

**Fix Temporário:**
- Associar Elastic IP à instância
- Alterar template default `associate_public_ip = true`

**Fix Produção (recomendado):**
- Criar VPC endpoints para SSM
- Manter instâncias em private subnets

---

## 5. Perguntas para o Especialista

### 5.1 Arquitetura & Design Patterns

**Q1:** Para um IDP em produção, você recomendaria Backstage ou uma solução custom (ex: portal React + API)?
- Quais os limites do Backstage que você já enfrentou?

**Q2:** Terraform via Scaffolder Actions é adequado para long-running resources ou deveria usar Crossplane/Operator pattern?
- Quando usar Terraform vs quando usar Crossplane?

**Q3:** Como você estruturaria multi-tenancy no Backstage?
- RBAC por equipe? Namespaces isolados? AWS accounts separadas?

**Q4:** State management do Terraform: S3 com locking (DynamoDB) é suficiente ou você usaria Terraform Cloud/Spacelift?

---

### 5.2 Segurança & Compliance

**Q5:** IRSA com PowerUserAccess é muito permissivo?
- Como você refinaria as policies por tipo de recurso (EC2, S3, RDS)?
- Deveria ter roles diferentes por template?

**Q6:** Backstage executando Terraform dentro do pod é um risco de segurança?
- Alternativa: Terraform executa em Lambda/Fargate/separate workers?

**Q7:** Cognito User Pool é adequado ou deveria integrar com IdP corporativo (Okta, Azure AD)?

**Q8:** Como garantir que developers não criem recursos fora do padrão?
- Policy-as-code (OPA, Sentinel)?
- Cost controls (AWS Budgets, Infracost)?

---

### 5.3 Operação & Reliability

**Q9:** Monitoramento e observabilidade - quais métricas são críticas em um IDP?
- Latência de provisionamento?
- Taxa de falha de templates?
- Custo por recurso criado?

**Q10:** Disaster recovery do Backstage:
- Catalog backup (GitHub é suficiente)?
- PostgreSQL backup strategy?
- Como recuperar state do Terraform se S3 bucket for perdido?

**Q11:** Escalabilidade:
- Quantos developers/templates um único cluster Backstage aguenta?
- Quando separar em múltiplos clusters?

**Q12:** Como você implementaria "resource tagging" obrigatório?
- Owner, CostCenter, Environment, etc.

---

### 5.4 Developer Experience

**Q13:** Self-service deletion - como garantir que developers deletem recursos criados?
- Alertas automáticos? TTL nos recursos?
- Dashboard de "my resources"?

**Q14:** Aprovação de recursos críticos (ex: RDS production):
- Workflow de approval no Backstage?
- Integração com Slack/Teams para notificações?

**Q15:** Como você lidaria com "template versioning"?
- Developers podem usar versões antigas?
- Deprecation strategy?

---

### 5.5 GitOps & CI/CD

**Q16:** ArgoCD vale a pena para gerenciar Backstage ou Helm direto é suficiente?

**Q17:** Templates Terraform devem ter seus próprios pipelines CI (tflint, tfsec, terraform plan)?

**Q18:** Como integrar com GitHub PR workflow?
- Template cria recurso + abre PR com código?
- Merge automático ou review obrigatório?

---

### 5.6 Networking & Conectividade

**Q19:** VPC Endpoints para SSM - custo x benefício:
- 3 endpoints (ssm, ssmmessages, ec2messages) = ~$21/mês
- Vale a pena vs public IPs com SG restritivo?

**Q20:** Private EKS cluster - Backstage deveria estar em private subnet?
- Como developers acessariam (VPN, bastion, AWS Client VPN)?

---

### 5.7 Trade-offs Específicos do Projeto

**Q21:** NLB gerenciado via Terraform vs Kubernetes Service:
- Você usaria external-dns + AWS Load Balancer Controller ou Terraform puro?

**Q22:** Backstage catalog: GitHub como source vs API dinâmica?
- Performance com muitos users/componentes?

**Q23:** Terraform state por recurso (S3 key única) vs workspace?
- Qual estratégia você prefere?

---

## 6. Roadmap & Melhorias Futuras

### 6.1 Curto Prazo (MVP+)
- [ ] Template de deleção (`resource-manager`) melhorado com listagem
- [ ] VPC Endpoints para SSM (eliminar public IPs)
- [ ] RBAC no Backstage (permissions por grupo)
- [ ] Cost tracking básico (tags obrigatórias)

### 6.2 Médio Prazo (Produção)
- [ ] Integração com ArgoCD (GitOps)
- [ ] Crossplane para recursos declarativos
- [ ] Multi-account AWS (dev/staging/prod)
- [ ] Policy-as-code (OPA para validação)
- [ ] Observabilidade (métricas de uso, dashboards)

### 6.3 Longo Prazo (Escala)
- [ ] Service catalog completo (APIs, databases, queues)
- [ ] Auto-remediation (recursos órfãos, drift detection)
- [ ] FinOps integration (cost allocation, budgets)
- [ ] Developer metrics (velocity, DORA metrics)

---

## 7. Métricas de Sucesso (Como Medir?)

**Adoção:**
- % de developers usando o portal vs console AWS direto
- Número de recursos provisionados via Backstage

**Eficiência:**
- Tempo médio de provisionamento (template → recurso ativo)
- Redução de tickets para infra team

**Qualidade:**
- Taxa de sucesso dos templates (apply success rate)
- Incidentes causados por recursos mal configurados

**Custo:**
- Custo médio por recurso provisionado
- ROI do IDP (tempo economizado vs custo de operação)

---

## 8. Referências Técnicas

**Repositórios:**
- Main: `darede-labs/reference-implementation-aws`
- Templates: `templates/backstage/*`

**Documentação Criada:**
- `docs/NLB-TERRAFORM-INTEGRATION.md` - NLB via Terraform
- `STATE.md` - Histórico de troubleshooting e fixes

**Stack Versions:**
- EKS: 1.31 (Kubernetes auto-mode)
- Backstage: CNOE-IO image (latest)
- Terraform: >= 1.0
- AWS Provider: >= 5.0

---

## 9. Como Usar Este Guia

**Durante a Conversa:**
1. Comece pelo Overview (seção 1) - contexto rápido
2. Mostre Arquitetura (seção 2) - diagrama e fluxos
3. Discuta Decisões (seção 3) - trade-offs tomados
4. Compartilhe Desafios (seção 4) - learning moments
5. **Faça as Perguntas (seção 5)** - objetivo principal!

**Foco nas Perguntas:**
- Priorize seções 5.1 (Arquitetura) e 5.2 (Segurança)
- Adapte conforme experiência do especialista (AWS, Kubernetes, IDP)
- Peça exemplos práticos de como ele resolveu problemas similares

**Após a Conversa:**
- Documente respostas e recomendações
- Atualize roadmap (seção 6) com insights
- Implemente quick wins identificados

---

**Boa sorte na conversa! 🚀**
