# Task Master AI - IDP Platform Development

Este diretório contém a configuração e documentação para gerenciamento de tarefas do projeto IDP usando Task Master AI.

## 📁 Estrutura

```
.taskmaster/
├── config.json          # Configuração do projeto e status das fases
├── tasks.json           # Database de tarefas (gerado automaticamente)
├── docs/
│   └── prd.txt         # Product Requirements Document completo
├── prompts/
│   ├── base-prompt.txt      # Prompt base para todas as fases
│   ├── validation-prompt.txt # Prompt de validação pós-fase
│   ├── debug-prompt.txt     # Prompt de troubleshooting
│   ├── golden-rule.txt      # Regras de ouro
│   └── phase-prompts.txt    # Prompts específicos das 7 fases
└── README.md           # Este arquivo
```

## 🚀 Configuração Inicial

### 1. Instalar Task Master MCP no Cursor

**Opção A: Via UI do Cursor (Recomendado)**

1. Abrir Cursor Settings (⌘+,)
2. Navegar para **Settings** > **MCP** (Model Context Protocol)
3. Clicar em **Add MCP Server**
4. Preencher:
   - **Name**: `task-master-ai`
   - **Command**: `npx`
   - **Args**: `-y task-master-ai@latest`
   - **Environment Variables**:
     ```
     TASK_MASTER_TOOLS=all
     ```
5. Salvar e recarregar o Cursor

**Opção B: Via Arquivo de Configuração**

Adicionar ao arquivo `~/.cursor/config.json` ou equivalente:

```json
{
  "mcpServers": {
    "task-master-ai": {
      "command": "npx",
      "args": ["-y", "task-master-ai@latest"],
      "env": {
        "TASK_MASTER_TOOLS": "all"
      },
      "type": "stdio"
    }
  }
}
```

### 2. Inicializar Task Master (Primeira Vez)

No chat do Cursor:

```
Initialize taskmaster-ai in my project
```

### 3. Parsear o PRD e Gerar Tasks

```
Parse my PRD at .taskmaster/docs/prd.txt
```

Task Master irá:
- Ler o PRD completo
- Gerar ~50-70 tasks organizadas por fase
- Criar dependências entre tasks
- Salvar em `.taskmaster/tasks.json`

## 📋 Uso Diário

### Comandos Comuns (via Chat do Cursor)

**Ver próxima task**:
```
What's the next task I should work on?
```

**Ver tasks específicas**:
```
Show me tasks 1, 3, and 5
```

**Ver todas as tasks de uma fase**:
```
Show me all tasks for Phase 3
```

**Implementar uma task**:
```
Can you help me implement task 15?
```

**Expandir uma task complexa**:
```
Can you expand task 10 into subtasks?
```

**Pesquisar informações atualizadas**:
```
Research the latest Crossplane AWS Provider best practices for IRSA
```

**Mover tasks entre fases**:
```
Move task 5 from backlog to in-progress
```

### Workflow Padrão por Fase

#### 1. Iniciar Fase

Copiar e colar no chat:

```
[Conteúdo de .taskmaster/prompts/base-prompt.txt]

[Conteúdo específico da fase de .taskmaster/prompts/phase-prompts.txt]

Can you help me implement Phase X?
```

#### 2. Implementar Tasks

Trabalhar incrementalmente:
- Uma task por vez
- Validar antes de avançar
- Commitar mudanças frequentemente

#### 3. Validar Fase

Copiar e colar:

```
[Conteúdo de .taskmaster/prompts/validation-prompt.txt]
```

Executar comandos de validação e confirmar Definition of Done.

#### 4. Debug (se necessário)

Se algo quebrar:

```
[Conteúdo de .taskmaster/prompts/debug-prompt.txt]

<Colar logs/erros aqui>
```

Task Master irá:
- Identificar root cause
- Sugerir hipóteses ordenadas por probabilidade
- Fornecer comandos de diagnóstico
- Propor fix mínimo

## 🎯 Fases do Projeto

| Fase | Status | Descrição |
|------|--------|-----------|
| Phase 0 | ✅ Completa | Repo skeleton + contracts |
| Phase 1 | ✅ Completa | EKS bootstrap (Terraform) |
| Phase 2 | ⏳ Em progresso | ArgoCD + Keycloak OIDC |
| Phase 3 | ❌ Pendente | Crossplane + AWS Provider + IRSA |
| Phase 4 | ❌ Pendente | Hello Node App + ECR + GitOps |
| Phase 5 | ❌ Pendente | Crossplane EC2 Self-Service (XRD + P/M/G) |
| Phase 6 | ❌ Pendente | Backstage Template EC2 |
| Phase 7 | ❌ Pendente | Expandir recursos (RDS/S3/Lambda/etc) |

## 📚 Documentação

- **PRD Completo**: [`docs/prd.txt`](docs/prd.txt)
- **Prompts**: [`prompts/`](prompts/)
- **Config**: [`config.json`](config.json)

## 🔍 Troubleshooting

### Task Master não responde

1. Verificar se MCP está habilitado no Cursor
2. Recarregar o Cursor
3. Verificar logs: Cursor > Help > Show Logs

### Tasks não foram geradas

```
Parse my PRD at .taskmaster/docs/prd.txt
```

Se ainda assim não funcionar, verificar se o arquivo PRD existe:

```bash
cat .taskmaster/docs/prd.txt | head -20
```

### Comandos não funcionam

Usar formato alternativo via CLI (fora do Cursor):

```bash
# Instalar globalmente
npm install -g task-master-ai

# Listar tasks
task-master list

# Próxima task
task-master next

# Mostrar task específica
task-master show 5
```

## 🛠️ Customização

### Ajustar Modo de Tools

Editar `.taskmaster/config.json` ou variável de ambiente MCP:

- `all`: 36 tools (~21k tokens) - Completo
- `standard`: 15 tools (~10k tokens) - Balanceado
- `core`: 7 tools (~5k tokens) - Essencial

Para projetos complexos como este IDP, recomenda-se `all`.

### Modificar Fases

Editar `docs/prd.txt` e re-parsear:

```
Parse my PRD at .taskmaster/docs/prd.txt
```

## 💡 Dicas

1. **Incremental é melhor**: Trabalhe uma task por vez
2. **Valide sempre**: Use validation-prompt após cada fase
3. **Commite frequentemente**: Pequenos commits facilitam rollback
4. **Use prompts estruturados**: Copy-paste dos arquivos em `prompts/`
5. **Documente desvios**: Se precisar modificar o plano, atualize o PRD

## 📞 Suporte

- **Documentação Task Master**: https://github.com/eyaltoledano/claude-task-master
- **Issues do Projeto**: (adicionar link do repositório)

---

**Built with ❤️ by the Platform Team**
