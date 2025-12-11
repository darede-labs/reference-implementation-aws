# 📚 Documentação Completa: Internal Developer Platform AWS

> **Repositório**: https://github.com/darede-labs/reference-implementation-aws
> **Versão**: 1.0 - POC Low-Cost
> **Última atualização**: Dezembro 2024

---

## 🎯 SOBRE ESTA DOCUMENTAÇÃO

Esta documentação foi criada para **empacotar e entregar** uma implementação completa de Internal Developer Platform (IDP) na AWS. O material está organizado para atender **3 públicos distintos**:

1. **Gestores/Liderança** → Documento Executivo
2. **Técnicos Iniciantes** → Guia Prático Passo-a-Passo
3. **Arquitetos/SREs** → Análise Técnica Avançada

---

## 📖 DOCUMENTOS DISPONÍVEIS

### 📋 [01 - DOCUMENTO EXECUTIVO](./01-DOCUMENTO-EXECUTIVO.md)
**Para quem**: CTOs, VPs Engineering, Gerentes, Tomadores de Decisão
**Tempo de leitura**: 30-40 minutos

**O que contém**:
- ✅ Sumário executivo (o que é, problema, benefício)
- ✅ Contexto e motivação (por que fazer)
- ✅ ROI e benefícios mensuráveis (636% ROI ao ano)
- ✅ Análise de investimento ($50k inicial, payback 3-4 meses)
- ✅ Comparação com alternativas (vs PaaS, K8s puro, status quo)
- ✅ Riscos e mitigações
- ✅ Roadmap completo (POC → Produção)
- ✅ KPIs e indicadores de sucesso

**Use quando**: Precisa aprovar budget, justificar investimento, apresentar para C-level

---

### 🛠️ [02 - GUIA RÁPIDO POC](./02-GUIA-RAPIDO-POC.md)
**Para quem**: Desenvolvedores, DevOps, Técnicos iniciantes/júnior
**Tempo de execução**: 4-6 horas (primeira vez)

**O que contém**:
- ✅ Checklist completo de pré-requisitos
- ✅ Setup passo-a-passo (copia e cola)
- ✅ Comandos exatos validados
- ✅ Configuração de Spot instances (economia 70%)
- ✅ Deploy da plataforma completa
- ✅ Testes e validação
- ✅ **Troubleshooting** de erros comuns
- ✅ **Como destruir tudo** (evitar custos)

**Use quando**: Vai executar a POC pela primeira vez, precisa de instruções práticas

**Custo esperado**: $5-10 para POC de 2 semanas (usando 8h/dia útil)

---

### 📊 [03 - ANÁLISE TÉCNICA DETALHADA](./03-ANALISE-TECNICA.md)
**Para quem**: Arquitetos de Soluções, SREs, Engenheiros Senior
**Tempo de leitura**: 1-2 horas

**O que contém**:
- ✅ Arquitetura detalhada com diagramas Mermaid
- ✅ Comparação com AWS Well-Architected Framework
- ✅ Análise de segurança (STRIDE, compliance LGPD/SOC2)
- ✅ Breakdown de custos por serviço
- ✅ Escalabilidade e performance tuning
- ✅ Plano de testes (unit, integration, chaos)
- ✅ Roadmap de melhorias priorizadas
- ✅ Gaps e como resolver para produção

**Use quando**: Quer entender profundamente a arquitetura, otimizar custos, preparar para produção

---

## 🚀 FLUXO DE USO RECOMENDADO

```
┌─────────────────────────────────────────────────────────┐
│  FASE 1: DECISÃO (Gestores)                             │
├─────────────────────────────────────────────────────────┤
│  1. Ler: 01-DOCUMENTO-EXECUTIVO.md                      │
│  2. Avaliar ROI e investimento                          │
│  3. Decisão: Go/No-Go para POC                          │
│  4. Alocar: 1 pessoa técnica + $50-100 budget           │
│                                                         │
│  ⏱️ Tempo: 1 semana                                     │
└─────────────────────────────────────────────────────────┘
              ↓ [Se aprovado]
┌─────────────────────────────────────────────────────────┐
│  FASE 2: EXECUÇÃO POC (Técnico)                         │
├─────────────────────────────────────────────────────────┤
│  1. Seguir: 02-GUIA-RAPIDO-POC.md                       │
│  2. Criar cluster EKS com Spot instances                │
│  3. Instalar plataforma                                 │
│  4. Testar criando aplicação                            │
│  5. Documentar aprendizados                             │
│  6. Destruir tudo (cleanup)                             │
│                                                         │
│  ⏱️ Tempo: 2-3 semanas (4-6h hands-on)                  │
│  💰 Custo: $50-75                                       │
└─────────────────────────────────────────────────────────┘
              ↓ [Se POC bem-sucedida]
┌─────────────────────────────────────────────────────────┐
│  FASE 3: PRODUTIZAÇÃO (Arquiteto + SRE)                │
├─────────────────────────────────────────────────────────┤
│  1. Ler: 03-ANALISE-TECNICA.md                          │
│  2. Implementar melhorias obrigatórias:                 │
│     • Multi-AZ NAT Gateway                              │
│     • Mix On-Demand + Spot                              │
│     • Backups automáticos                               │
│     • Disaster Recovery                                 │
│     • Network Policies                                  │
│     • Monitoring avançado                               │
│  3. Security hardening                                  │
│  4. Load testing                                        │
│  5. Go-live produção                                    │
│                                                         │
│  ⏱️ Tempo: 4-6 semanas                                  │
│  💰 Investimento: $45k (pessoas) + $500/mês (AWS)       │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 RESUMO EXECUTIVO (TL;DR)

### O que é este projeto?

Uma **plataforma self-service** (IDP) que permite desenvolvedores criarem aplicações e infraestrutura **sem depender de DevOps** para tarefas repetitivas.

### Por que fazer?

- ⚡ **99% mais rápido**: 30 minutos vs 5 dias para provisionar recursos
- 💰 **ROI 636% ao ano**: $170k economia líquida (time 20 devs)
- 🚀 **Produtividade**: Devs focam em código, não em tickets
- 🏆 **Escala**: DevOps viram arquitetos, não executores

### Quanto custa?

| Ambiente | Custo/mês | Uso |
|----------|-----------|-----|
| **POC** | $50-150 | 2 semanas teste |
| **Dev** | $300-400 | Contínuo |
| **Prod** | $2000-3000 | Alta disponibilidade |

### Principais componentes

- **Backstage** (portal web) → Desenvolvedores criam apps aqui
- **ArgoCD** (GitOps) → Deploy automático do Git
- **Crossplane** (IaC) → Provisiona AWS resources
- **Keycloak** (SSO) → Login único
- **EKS** (Kubernetes) → Orquestração de containers

### Configuração para este repositório

```yaml
Organização GitHub: darede-labs
Repositório: reference-implementation-aws
Domínio: timedevops.click
Região AWS: us-east-1
Modo: Standard (Spot instances)
Custo POC: ~$75 para 2 semanas
```

---

## 🔧 ARQUIVOS DE CONFIGURAÇÃO

### Principais arquivos para editar:

```
reference-implementation-aws/
├── config.yaml                    # ← Configuração principal
│   ├─ domain: timedevops.click
│   ├─ cluster_name: idp-poc-cluster
│   └─ auto_mode: "false"
│
├── cluster/terraform/main.tf      # ← Modificar para Spot
│   └─ eks_managed_node_groups
│       └─ capacity_type: "SPOT"
│
└── private/
    ├── backstage-github.yaml     # ← Credenciais GitHub App
    └── argocd-github.yaml        # ← Credenciais GitHub App
```

### Comandos mais importantes:

```bash
# Criar secrets AWS
./scripts/create-config-secrets.sh

# Provisionar cluster EKS
cd cluster/terraform
terraform init
terraform apply

# Instalar plataforma
./scripts/install.sh

# Destruir tudo
terraform destroy
./scripts/uninstall.sh
```

---

## 🐛 TROUBLESHOOTING RÁPIDO

### Problema: Pods não iniciam

```bash
kubectl describe pod -n <namespace> <pod-name>
# Ver eventos no final do output
```

### Problema: DNS não resolve

```bash
# Verificar External DNS
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verificar Route53
aws route53 list-resource-record-sets --hosted-zone-id Z09212782MXWNY5EYNICO
```

### Problema: Custo muito alto

```bash
# Ver breakdown de custos
aws ce get-cost-and-usage \
  --time-period Start=2024-12-01,End=2024-12-10 \
  --granularity DAILY \
  --metrics "UnblendedCost"

# Destruir IMEDIATAMENTE
cd cluster/terraform
terraform destroy -auto-approve
```

### Problema: ArgoCD apps unhealthy

```bash
# Ver status
kubectl get applications -n argocd

# Ver detalhes do erro
kubectl describe application <app-name> -n argocd

# Logs do ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

---

## 📚 REFERÊNCIAS EXTERNAS

### Documentação Oficial

- [AWS Prescriptive Guidance - IDP](https://docs.aws.amazon.com/prescriptive-guidance/latest/internal-developer-platform/)
- [CNOE Reference Implementation](https://cnoe.io/)
- [Backstage Documentation](https://backstage.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terraform EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)

### Tutoriais e Guias

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Spot Instances Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [GitOps with ArgoCD](https://www.gitops.tech/)
- [Platform Engineering Guide](https://platformengineering.org/)

### Ferramentas de Custo

- [AWS Pricing Calculator](https://calculator.aws/)
- [EKS Cost Estimator](https://learnk8s.io/kubernetes-instance-calculator)
- [Kubecost](https://www.kubecost.com/)

---

## 🤝 CONTRIBUINDO

Este é um projeto **empacotável** para clientes. Se encontrar problemas ou melhorias:

1. Abra issue: https://github.com/darede-labs/reference-implementation-aws/issues
2. Documente o problema claramente
3. Se tiver solução, crie PR com explicação

---

## 📞 SUPORTE

### Para dúvidas técnicas:
- Issues GitHub: https://github.com/darede-labs/reference-implementation-aws/issues
- CNOE Community: https://cnoe.io/community

### Para dúvidas de negócio:
- Revisar documento executivo: `01-DOCUMENTO-EXECUTIVO.md`
- FAQ executivo na seção final

---

## ✅ CHECKLIST FINAL ANTES DE ENTREGAR AO CLIENTE

```
□ Todos os 3 documentos revisados
□ Credenciais de exemplo removidas
□ config.yaml configurado corretamente
□ Terraform testado (apply + destroy)
□ Scripts de instalação validados
□ Custos verificados e documentados
□ Guia de troubleshooting atualizado
□ README.md do repositório atualizado
□ Licença definida (MIT, Apache, etc)
□ Contato de suporte fornecido
```

---

## 📄 LICENÇA

Este projeto está sob a licença Apache 2.0. Ver arquivo [LICENSE](../LICENSE) para detalhes.

---

## 🎓 PRÓXIMOS PASSOS

1. **Se nunca executou antes**: Comece por `02-GUIA-RAPIDO-POC.md`
2. **Se quer apresentar para gestores**: Use `01-DOCUMENTO-EXECUTIVO.md`
3. **Se vai produtizar**: Estude `03-ANALISE-TECNICA.md`

---

**Boa sorte com sua implementação! 🚀**

---

**Criado por**: Darede Labs
**Mantido por**: Platform Engineering Team
**Última atualização**: Dezembro 2024
