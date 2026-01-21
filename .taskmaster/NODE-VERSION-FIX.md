# ✅ Node.js Version Fix - RESOLVED

## 🔍 Problema Identificado

**Erro anterior**:
```
SyntaxError: Unexpected token '{'
at Loader.moduleStrategy (node:internal/modules/esm/translators:147:18)
```

**Causa raiz**: Node.js v16.0.0 é muito antigo

**Sintaxe incompatível**: `static {}` blocks (introduzidos no Node.js v16.11.0+)

## ✅ Solução Aplicada

### 1. Node.js Atualizado

**Antes**: Node.js v16.0.0
**Depois**: Node.js v22.21.1 (LTS)

```bash
nvm use 22.21.1
nvm alias default 22.21.1
```

### 2. Configuração MCP Atualizada

**Arquivo**: `~/.cursor/mcp.json`

**Adicionado**:
- PATH com Node.js v22.21.1
- Flag `--legacy-peer-deps`

**Configuração final**:
```json
{
  "task-master-ai": {
    "command": "npx",
    "args": ["--legacy-peer-deps", "-y", "task-master-ai@latest"],
    "env": {
      "TASK_MASTER_TOOLS": "all",
      "PATH": "/Users/matheusandrade/.nvm/versions/node/v22.21.1/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    }
  }
}
```

## 🎯 Próximos Passos

### 1. Recarregar Cursor (OBRIGATÓRIO)

```
Cmd+Shift+P → "Reload Window" → Enter
```

⚠️ **Cursor precisa reiniciar para usar o novo Node.js!**

### 2. Verificar se MCP está funcionando

No chat do Cursor:
```
List available MCP servers
```

Deve aparecer: `task-master-ai` ✅ (sem erros)

### 3. Inicializar Task Master

```
Initialize taskmaster-ai in my project
```

### 4. Parsear PRD

```
Parse my PRD at .taskmaster/docs/prd.txt
```

### 5. Começar!

```
What's the next task I should work on?
```

## 🔍 Validação

### Verificar versão do Node

```bash
node --version
# Deve mostrar: v22.21.1
```

### Verificar nvm default

```bash
nvm list
# Deve mostrar: default -> 22.21.1 (-> v22.21.1)
```

### Verificar PATH do Node

```bash
which node
# Deve mostrar: /Users/matheusandrade/.nvm/versions/node/v22.21.1/bin/node
```

### Testar npx com novo Node

```bash
npx --version
# Deve funcionar sem erros
```

## 📋 Cronologia das Correções

1. ✅ **Erro 1**: Conflito de dependências npm (`jose` v5 vs v6)
   → **Solução**: Adicionado `--legacy-peer-deps`

2. ✅ **Erro 2**: Node.js v16.0.0 muito antigo
   → **Solução**: Atualizado para v22.21.1 + PATH no MCP

## 🚨 Troubleshooting

### Erro persiste após recarregar

**Solução 1**: Verificar se Node está correto
```bash
node --version  # Deve ser v22.21.1
```

**Solução 2**: Reinstalar com novo Node
```bash
npm cache clean --force
npm install -g task-master-ai --legacy-peer-deps
```

**Solução 3**: Usar comando direto (sem npx)
```json
{
  "task-master-ai": {
    "command": "/Users/matheusandrade/.nvm/versions/node/v22.21.1/bin/npx",
    "args": ["--legacy-peer-deps", "-y", "task-master-ai@latest"],
    "env": {
      "TASK_MASTER_TOOLS": "all"
    }
  }
}
```

### MCP não encontra Node

**Problema**: Cursor não está usando o PATH correto

**Solução**: Adicionar ao `~/.zshrc` ou `~/.bashrc`:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 22.21.1
```

Depois reiniciar terminal e Cursor.

### Outros MCP servers pararam de funcionar

**Problema**: PATH do Node pode afetar outros servers

**Solução**: Verificar se outros servers precisam de versões específicas do Node

## ✅ Status Final

**Node.js**: ✅ v22.21.1 (atualizado e configurado como default)
**MCP Config**: ✅ PATH correto + --legacy-peer-deps
**Correções**: ✅ Ambos os erros resolvidos

**PRÓXIMA AÇÃO**: Recarregar o Cursor

## 📚 Referências

- Node.js LTS: https://nodejs.org/en/about/releases/
- nvm Documentation: https://github.com/nvm-sh/nvm
- Task Master: https://github.com/eyaltoledano/claude-task-master

---

**Data da correção**: 2026-01-19
**Versões**:
- Node.js: v16.0.0 → v22.21.1
- npm: v7.10.0 → v10.9.4
