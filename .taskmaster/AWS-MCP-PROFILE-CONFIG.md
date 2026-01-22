# AWS MCP Servers - Configuração de Profile e Region

## 🔧 Como Funciona

Os MCP servers AWS **usam o profile e region padrão** do seu sistema, seguindo a ordem de precedência do AWS CLI:

### Ordem de Precedência

1. **Variáveis de ambiente** (mais alta prioridade)
   - `AWS_PROFILE`
   - `AWS_REGION`
   - `AWS_DEFAULT_REGION`

2. **Profile default** no `~/.aws/config`

3. **Credenciais default** no `~/.aws/credentials`

Isso permite trabalhar com **múltiplos projetos** sem precisar reconfigurar o Cursor!

---

## 🎯 Cenários de Uso

### Cenário 1: Projeto Darede (Profile `darede`)

```bash
# Opção A: Setar profile para a sessão
export AWS_PROFILE=darede
export AWS_REGION=us-east-1

# Fazer login SSO
aws sso login --profile darede

# Usar Cursor normalmente
# MCPs usarão profile darede automaticamente
```

**Ou** usar profile específico temporariamente:
```bash
# No terminal do Cursor
AWS_PROFILE=darede cursor
```

### Cenário 2: Outro Projeto (Profile diferente)

```bash
# Mudar para outro profile
export AWS_PROFILE=cliente-xpto
export AWS_REGION=sa-east-1

# Login
aws sso login --profile cliente-xpto

# MCPs usarão cliente-xpto automaticamente
```

### Cenário 3: Profile Default

```bash
# Sem variáveis de ambiente
# MCPs usam o profile [default] do ~/.aws/config

# Se não tiver profile default, configurar:
aws configure
```

---

## 🔄 Mudança de Contexto (Multi-Projeto)

### Opção 1: Variáveis de Ambiente por Terminal

```bash
# Terminal 1 - Projeto Darede
export AWS_PROFILE=darede
export AWS_REGION=us-east-1
cursor  # Abre Cursor com profile darede

# Terminal 2 - Projeto Cliente
export AWS_PROFILE=cliente-xpto
export AWS_REGION=sa-east-1
cursor  # Abre Cursor com profile cliente-xpto
```

### Opção 2: Usar .envrc (com direnv)

Instalar direnv:
```bash
brew install direnv
```

Configurar por projeto:
```bash
# No diretório do projeto Darede
cd ~/darede/reference-implementation-aws
echo 'export AWS_PROFILE=darede' > .envrc
echo 'export AWS_REGION=us-east-1' >> .envrc
direnv allow

# No diretório do projeto Cliente
cd ~/cliente-xpto/projeto
echo 'export AWS_PROFILE=cliente-xpto' > .envrc
echo 'export AWS_REGION=sa-east-1' >> .envrc
direnv allow
```

Agora ao entrar no diretório, o profile muda automaticamente!

### Opção 3: Script de Troca Rápida

Criar alias no `~/.zshrc`:

```bash
# Adicionar ao ~/.zshrc
alias aws-darede='export AWS_PROFILE=darede && export AWS_REGION=us-east-1 && echo "✅ AWS Profile: darede (us-east-1)"'
alias aws-cliente='export AWS_PROFILE=cliente-xpto && export AWS_REGION=sa-east-1 && echo "✅ AWS Profile: cliente-xpto (sa-east-1)"'
alias aws-default='unset AWS_PROFILE && unset AWS_REGION && echo "✅ AWS Profile: default"'
alias aws-current='echo "Profile: ${AWS_PROFILE:-default}" && echo "Region: ${AWS_REGION:-$(aws configure get region)}"'
```

Usar:
```bash
# Mudar para Darede
aws-darede

# Mudar para Cliente
aws-cliente

# Voltar para default
aws-default

# Ver profile atual
aws-current
```

---

## 🧪 Testar Configuração

### Verificar Profile Atual

```bash
# Ver profile ativo
echo $AWS_PROFILE
# Se vazio, está usando [default]

# Ver region ativa
echo $AWS_REGION
# Se vazio, está usando region do ~/.aws/config

# Ver identidade AWS atual
aws sts get-caller-identity

# Ver configuração completa
aws configure list
```

### Testar MCPs no Cursor

Após configurar o profile:

```
> What's my current AWS account?
> Show me my EKS clusters
> What's my spending this month?
```

MCPs usarão o profile/region configurados automaticamente.

---

## 📋 Configuração Recomendada por Projeto

### Estrutura ~/.aws/config

```ini
[default]
region = us-east-1
output = json

[profile darede]
region = us-east-1
output = json
sso_start_url = https://darede.awsapps.com/start
sso_region = us-east-1
sso_account_id = 948881762705
sso_role_name = AdministratorAccess

[profile cliente-xpto]
region = sa-east-1
output = json
sso_start_url = https://cliente.awsapps.com/start
sso_region = sa-east-1
sso_account_id = 123456789012
sso_role_name = DeveloperAccess
```

### Estrutura ~/.aws/credentials (se não usar SSO)

```ini
[default]
aws_access_key_id = YOUR_KEY
aws_secret_access_key = YOUR_SECRET

[darede]
aws_access_key_id = DAREDE_KEY
aws_secret_access_key = DAREDE_SECRET

[cliente-xpto]
aws_access_key_id = CLIENTE_KEY
aws_secret_access_key = CLIENTE_SECRET
```

---

## 💡 Dicas

### 1. Mostrar Profile no Terminal

Adicionar ao `~/.zshrc` ou `~/.bashrc`:

```bash
# Mostrar AWS profile no prompt
export PS1='[AWS:${AWS_PROFILE:-default}] '$PS1
```

### 2. Validar Profile Antes de Executar

```bash
# Adicionar função de segurança
aws-check() {
  echo "Current AWS Profile: ${AWS_PROFILE:-default}"
  aws sts get-caller-identity
}

# Usar antes de comandos importantes
aws-check
```

### 3. Prevenir Acidentes

```bash
# Alias com confirmação para produção
alias aws-prod='echo "⚠️  Mudando para PRODUÇÃO. Confirma? (yes/no)" && read confirm && [ "$confirm" = "yes" ] && export AWS_PROFILE=prod'
```

---

## 🔐 Segurança

### Boas Práticas

1. **Nunca commitar** `.envrc` ou arquivos com credenciais
2. **Usar SSO** sempre que possível (em vez de access keys)
3. **Rotacionar** access keys regularmente
4. **Validar** profile antes de operações críticas
5. **Usar** IAM roles com least privilege

### Adicionar ao .gitignore

```bash
# Adicionar ao .gitignore do projeto
echo ".envrc" >> .gitignore
echo ".aws-profile" >> .gitignore
```

---

## 🚀 Quick Start

### Para Projeto Darede

```bash
# 1. Configurar profile (uma vez)
aws configure sso --profile darede

# 2. Login
aws sso login --profile darede

# 3. Setar para sessão atual
export AWS_PROFILE=darede
export AWS_REGION=us-east-1

# 4. Abrir Cursor
cursor

# 5. Testar MCPs
# No chat do Cursor:
> Show me my EKS clusters
```

### Para Outro Projeto

```bash
# 1. Configurar profile (uma vez)
aws configure sso --profile cliente-xpto

# 2. Login
aws sso login --profile cliente-xpto

# 3. Setar para sessão atual
export AWS_PROFILE=cliente-xpto
export AWS_REGION=sa-east-1

# 4. Abrir Cursor
cursor

# 5. Testar MCPs
# No chat do Cursor:
> What's my current AWS account?
```

---

## ❓ FAQ

**P: Como sei qual profile está ativo?**
```bash
echo $AWS_PROFILE
aws configure list
aws sts get-caller-identity
```

**P: MCPs não estão pegando o profile correto**

R: Verificar:
1. Profile está exportado: `echo $AWS_PROFILE`
2. Cursor foi aberto **após** exportar a variável
3. Recarregar Cursor: Cmd+Shift+P → "Reload Window"

**P: Posso ter profiles diferentes por workspace do Cursor?**

R: Sim! Usar `.envrc` com direnv em cada diretório de projeto.

**P: Como voltar para profile default?**
```bash
unset AWS_PROFILE
unset AWS_REGION
```

**P: MCPs não encontram credenciais**

R: Fazer login:
```bash
# SSO
aws sso login --profile $AWS_PROFILE

# Ou verificar credenciais
aws sts get-caller-identity
```

---

## 📚 Referências

- AWS CLI Configuration: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
- AWS SSO: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html
- direnv: https://direnv.net/
- AWS Labs MCP: https://github.com/awslabs/mcp

---

**Atualizado**: 2026-01-19
**Versão**: 2.0 (profile flexível)
