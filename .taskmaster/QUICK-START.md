# Task Master - Quick Start Guide

## ⚡ Configuração Rápida (5 minutos)

### Passo 1: Configurar MCP no Cursor

1. Abrir Cursor
2. Pressionar `⌘+,` (Cmd+Comma) para abrir Settings
3. Clicar na aba **MCP** no menu lateral esquerdo
4. Clicar em **Add Server** ou botão similar
5. Preencher os campos:

```
Name: task-master-ai
Command: npx
Args: -y task-master-ai@latest
```

6. Adicionar variável de ambiente:

```
Key: TASK_MASTER_TOOLS
Value: all
```

7. Salvar e fechar Settings
8. **Recarregar o Cursor** (Cmd+Shift+P → "Reload Window")

### Passo 2: Inicializar Task Master

No chat do Cursor (Cmd+L), digite:

```
Initialize taskmaster-ai in my project
```

Aguardar confirmação de sucesso.

### Passo 3: Parsear o PRD

No chat do Cursor:

```
Parse my PRD at .taskmaster/docs/prd.txt
```

Task Master irá gerar automaticamente todas as tasks das 7 fases.

### Passo 4: Ver Próxima Task

```
What's the next task I should work on?
```

## 🎯 Comandos Essenciais

| Comando | Descrição |
|---------|-----------|
| `What's the next task?` | Mostra próxima task a trabalhar |
| `Show me tasks 1, 3, 5` | Mostra tasks específicas |
| `Can you help me implement task 10?` | Implementa task com assistência |
| `Show me all Phase 3 tasks` | Lista tasks de uma fase |
| `Expand task 5 into subtasks` | Quebra task complexa |

## 🔄 Workflow Diário

### 1. Consultar PRD e Prompts

Antes de começar uma fase:

```bash
# Ver PRD
cat .taskmaster/docs/prd.txt | grep "PHASE 3" -A 50

# Ver prompt da fase
cat .taskmaster/prompts/phase-prompts.txt | grep "PHASE 3" -A 50
```

### 2. Colar Base Prompt + Phase Prompt

No chat do Cursor:

```
[Copiar/colar conteúdo de .taskmaster/prompts/base-prompt.txt]

[Copiar/colar seção específica da fase de .taskmaster/prompts/phase-prompts.txt]

Can you help me implement Phase X tasks?
```

### 3. Implementar Incrementalmente

- Uma task por vez
- Validar após cada mudança
- Commitar frequentemente

### 4. Validar Fase

Ao completar todas as tasks da fase:

```
[Copiar/colar .taskmaster/prompts/validation-prompt.txt]
```

Executar comandos de validação sugeridos.

### 5. Debug (se necessário)

Se algo quebrar:

```
[Copiar/colar .taskmaster/prompts/debug-prompt.txt]

<Colar logs/erros aqui>
```

## 🚨 Troubleshooting

### MCP não aparece nas opções

**Solução**: Atualizar Cursor para versão mais recente

```bash
# Verificar versão
# Help > About

# Se < 0.40.x, atualizar para última versão
```

### Task Master não responde

**Soluções**:

1. Verificar se servidor está habilitado:
   - Settings > MCP > Verificar toggle "Enabled"

2. Recarregar Cursor:
   - Cmd+Shift+P → "Reload Window"

3. Verificar logs:
   - Help > Toggle Developer Tools > Console
   - Procurar por erros relacionados a "mcp" ou "task-master"

### Tasks não foram geradas

**Solução**: Re-parsear o PRD

```
Parse my PRD at .taskmaster/docs/prd.txt and generate all tasks
```

### Erro "npx command not found"

**Solução**: Instalar Node.js

```bash
# Verificar Node instalado
node --version

# Se não instalado, usar Homebrew:
brew install node

# Ou baixar de https://nodejs.org
```

## 📖 Recursos Adicionais

- **README Completo**: [`.taskmaster/README.md`](.taskmaster/README.md)
- **PRD**: [`.taskmaster/docs/prd.txt`](.taskmaster/docs/prd.txt)
- **Prompts**: [`.taskmaster/prompts/`](.taskmaster/prompts/)
- **Task Master Docs**: https://github.com/eyaltoledano/claude-task-master

## ✅ Checklist de Configuração

- [ ] Cursor atualizado para versão recente
- [ ] MCP server `task-master-ai` adicionado nas Settings
- [ ] Variável `TASK_MASTER_TOOLS=all` configurada
- [ ] Cursor recarregado (Reload Window)
- [ ] Task Master inicializado com sucesso
- [ ] PRD parseado e tasks geradas
- [ ] Primeira task visualizada com `What's the next task?`

---

**Pronto para começar!** 🚀

Use `What's the next task I should work on?` para iniciar.
