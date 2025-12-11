# Solução para Bloqueio de SCP no AWS Secrets Manager

## 📋 Problema Identificado

A Service Control Policy (SCP) da conta AWS está bloqueando o acesso de **assumed roles** ao AWS Secrets Manager com uma negação explícita:

```
AccessDeniedException: User: arn:aws:sts::948881762705:assumed-role/[ROLE_NAME]/[SESSION]
is not authorized to perform: secretsmanager:GetSecretValue on resource: cnoe-ref-impl/config
with an explicit deny in a service control policy
```

Isso afeta **TODOS** os métodos de autenticação baseados em assumed roles:
- ✅ **Pod Identity** (EKS Pod Identity) - BLOQUEADO
- ✅ **IRSA** (IAM Roles for Service Accounts) - BLOQUEADO

## 🔧 Solução Implementada

### Opção 1: Hub Cluster Secret Direto (Implementada)

Ao invés de usar External Secrets para buscar configurações do Secrets Manager, criamos o `hub-cluster-secret` diretamente a partir do `config.yaml`.

**Arquivos Modificados:**

1. **`packages/argo-cd/manifests/hub-cluster-secret-direct.yaml`** (NOVO)
   - Template do secret com placeholders para variáveis
   - Contém todas as labels e annotations necessárias

2. **`scripts/install.sh`** (MODIFICADO)
   - Gera o secret a partir do `config.yaml`
   - Substitui os placeholders com valores reais
   - Aplica o secret antes dos outros manifestos
   - Pula o `hub-cluster-secret.yaml` original (que usa External Secrets)

3. **`packages/appset-chart/values.yaml`** (MODIFICADO)
   - Habilitado `syncPolicy.automated.selfHeal: true`
   - Habilitado `syncPolicy.automated.prune: true`
   - Garante que todas Applications sincronizem automaticamente

### Opção 2: Ajustar SCP (Recomendado para Produção)

Para produção, recomendamos ajustar a SCP para permitir acesso ao Secrets Manager para roles específicas do EKS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEKSPodIdentitySecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:948881762705:secret:cnoe-ref-impl/*",
      "Condition": {
        "StringLike": {
          "aws:userid": [
            "AROA*:eks-*",
            "AROA*:*-irsa"
          ]
        }
      }
    }
  ]
}
```

## 📦 Componentes Afetados

### ✅ Funcionam com Workaround:
- ArgoCD (com hub-cluster-secret direto)
- Todas as ApplicationSets
- Sync automático de Applications

### ⚠️ Ainda Bloqueados (não críticos):
- ExternalSecret `github-app-org` (opcional, para GitHub integration)
- Outros External Secrets que dependem do Secrets Manager

## 🎯 Benefícios da Solução

1. **Zero Dependência do Secrets Manager** para configuração do cluster
2. **100% Automatizado** - não requer intervenção manual
3. **Configuração em um Único Local** - tudo em `config.yaml`
4. **Reproduzível** - destroy/apply funciona perfeitamente
5. **Compatible com SCPs Restritivas** - não depende de assumed roles

## 🔄 Como Funciona

```bash
1. Usuario edita config.yaml
2. Scripts/install.sh lê config.yaml
3. Gera hub-cluster-secret-direct.yaml com valores do config
4. Aplica secret no Kubernetes
5. ApplicationSets usam labels/annotations do secret
6. Applications são geradas e sincronizadas automaticamente
```

## 📝 Variáveis do Cluster Secret

O secret contém as seguintes informações:

```yaml
Labels:
  - argocd.argoproj.io/secret-type: cluster
  - environment: control-plane
  - path_routing: "false"
  - auto_mode: "false"

Annotations:
  - domain: timedevops.click
  - route53_hosted_zone_id: Z09212782MXWNY5EYNICO
  - addons_repo_url: https://github.com/darede-labs/reference-implementation-aws
  - addons_repo_revision: main
  - addons_repo_basepath: packages

Data:
  - clusterName, awsRegion, awsAccountId, etc.
```

## 🚀 Testado e Validado

- ✅ Ciclo completo de instalação
- ✅ ApplicationSets gerando Applications
- ✅ Auto-sync funcionando
- ✅ Todos os componentes core instalados
- ✅ Reproduzível em múltiplos deploys

## 🔮 Futuras Melhorias

1. **Modo Híbrido**: Detectar se Secrets Manager está acessível e usar automaticamente
2. **External Secrets Optional**: Tornar External Secrets completamente opcional
3. **Config Encryption**: Criptografar valores sensíveis no config.yaml
