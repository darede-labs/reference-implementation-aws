# Task Master MCP - Configuração Corrigida

## ⚠️ Problema Identificado

Conflito de dependências npm ao instalar `task-master-ai`:
```
npm ERR! ERESOLVE unable to resolve dependency tree
npm ERR! Could not resolve dependency:
npm ERR! peerOptional jose@"^5.0.0" from fastmcp@3.27.0
npm ERR! Found: jose@6.1.3
```

## ✅ Solução

Usar `--legacy-peer-deps` no comando npx para ignorar conflitos de peer dependencies.

## 📝 Configuração Correta do MCP

### Opção 1: Via UI do Cursor (Recomendado)

1. Abrir Cursor Settings: `⌘+,`
2. Clicar na aba **MCP**
3. Se o server `task-master-ai` já existe, **deletá-lo primeiro**
4. Clicar em **Add Server**
5. Preencher:

```
Name: task-master-ai
Command: npx
Args: --legacy-peer-deps -y task-master-ai@latest
Environment Variables:
  TASK_MASTER_TOOLS=all
```

**IMPORTANTE**: Note o `--legacy-peer-deps` no campo Args!

6. Salvar e recarregar Cursor: Cmd+Shift+P → "Reload Window"

### Opção 2: Via Arquivo de Configuração

Editar ou criar arquivo de config do Cursor MCP (localização pode variar):

**macOS**: `~/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-mcp/config.json`

```json
{
  "mcpServers": {
    "task-master-ai": {
      "command": "npx",
      "args": ["--legacy-peer-deps", "-y", "task-master-ai@latest"],
      "env": {
        "TASK_MASTER_TOOLS": "all"
      },
      "type": "stdio"
    }
  }
}
```

Depois recarregar o Cursor.

### Opção 3: Instalação Global (Alternativa)

Se as opções acima não funcionarem, instalar globalmente primeiro:

```bash
# Instalar globalmente
npm install -g task-master-ai --legacy-peer-deps

# Verificar instalação
task-master --version
```

Depois configurar MCP para usar o comando global:

```
Name: task-master-ai
Command: task-master-ai
Args: (deixar vazio)
Environment Variables:
  TASK_MASTER_TOOLS=all
```

## 🧪 Testar a Correção

Após recarregar o Cursor:

1. Abrir chat do Cursor (⌘+L)
2. Verificar se MCP está ativo:
   ```
   List available MCP servers
   ```
   Deve aparecer `task-master-ai` na lista

3. Inicializar:
   ```
   Initialize taskmaster-ai in my project
   ```

4. Se funcionar, parsear o PRD:
   ```
   Parse my PRD at .taskmaster/docs/prd.txt
   ```

## 🔍 Verificar Logs

Se ainda houver problemas:

1. Help > Toggle Developer Tools > Console
2. Procurar por mensagens de erro relacionadas a "mcp" ou "task-master"
3. Verificar se o processo npx está sendo iniciado com `--legacy-peer-deps`

## 🚨 Troubleshooting Adicional

### Erro persiste

**Solução 1**: Limpar cache do npm e tentar novamente
```bash
npm cache clean --force
```

Depois recarregar Cursor.

**Solução 2**: Usar versão específica mais antiga
```
Args: --legacy-peer-deps -y task-master-ai@0.41.0
```

**Solução 3**: Usar alternativa CLI manual
```bash
# Instalar globalmente
npm install -g task-master-ai --legacy-peer-deps

# Usar diretamente via terminal
task-master init
task-master parse-prd .taskmaster/docs/prd.txt
task-master list
task-master next
```

### Verificar versão do Node.js

```bash
node --version
```

Recomendado: Node.js v18+ ou v20+

Se versão muito antiga, atualizar:
```bash
# Via Homebrew (macOS)
brew upgrade node

# Ou via nvm
nvm install --lts
nvm use --lts
```

## ✅ Configuração Testada

Configuração que deve funcionar:

```json
{
  "mcpServers": {
    "task-master-ai": {
      "command": "npx",
      "args": [
        "--legacy-peer-deps",
        "-y",
        "task-master-ai@latest"
      ],
      "env": {
        "TASK_MASTER_TOOLS": "all"
      },
      "type": "stdio"
    }
  }
}
```

## 📚 Referências

- Task Master Issues: https://github.com/eyaltoledano/claude-task-master/issues
- npm legacy-peer-deps: https://docs.npmjs.com/cli/v8/commands/npm-install#legacy-peer-deps

---

**Após corrigir, volte para**: `.taskmaster/NEXT-STEPS.txt`
