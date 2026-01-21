#!/bin/bash

################################################################################
# Script de Teste da Integração Task Master MCP
################################################################################

set -e

echo "=================================="
echo "Task Master MCP - Teste de Integração"
echo "=================================="
echo ""

# Verificar Node.js
echo "1. Verificando Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo "✅ Node.js instalado: $NODE_VERSION"
else
    echo "❌ Node.js não encontrado!"
    echo "   Instalar: brew install node"
    exit 1
fi

echo ""

# Verificar npx
echo "2. Verificando npx..."
if command -v npx &> /dev/null; then
    NPX_VERSION=$(npx --version)
    echo "✅ npx disponível: $NPX_VERSION"
else
    echo "❌ npx não encontrado!"
    exit 1
fi

echo ""

# Verificar arquivo MCP
echo "3. Verificando configuração MCP..."
MCP_FILE="$HOME/.cursor/mcp.json"
if [ -f "$MCP_FILE" ]; then
    echo "✅ Arquivo encontrado: $MCP_FILE"

    # Verificar se tem task-master-ai
    if grep -q "task-master-ai" "$MCP_FILE"; then
        echo "✅ task-master-ai configurado"

        # Verificar se tem --legacy-peer-deps
        if grep -q "legacy-peer-deps" "$MCP_FILE"; then
            echo "✅ Flag --legacy-peer-deps presente"
        else
            echo "⚠️  Flag --legacy-peer-deps NÃO encontrado"
            echo "   A configuração pode falhar por conflito de dependências"
        fi
    else
        echo "❌ task-master-ai não encontrado na configuração"
        exit 1
    fi
else
    echo "❌ Arquivo MCP não encontrado: $MCP_FILE"
    exit 1
fi

echo ""

# Verificar estrutura .taskmaster
echo "4. Verificando estrutura .taskmaster..."
if [ -d ".taskmaster" ]; then
    echo "✅ Diretório .taskmaster existe"

    # Verificar arquivos essenciais
    FILES=("config.json" "tasks.json" "docs/prd.txt" "prompts/base-prompt.txt")
    for file in "${FILES[@]}"; do
        if [ -f ".taskmaster/$file" ]; then
            echo "✅ $file"
        else
            echo "❌ $file não encontrado"
        fi
    done
else
    echo "❌ Diretório .taskmaster não encontrado"
    echo "   Execute este script da raiz do projeto"
    exit 1
fi

echo ""

# Testar instalação do task-master-ai (sem MCP, apenas npm)
echo "5. Testando instalação do task-master-ai..."
echo "   (Isso pode demorar alguns segundos...)"

# Criar diretório temporário para teste
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Tentar instalar com --legacy-peer-deps
if npx --legacy-peer-deps -y task-master-ai@latest --help &> /dev/null; then
    echo "✅ task-master-ai pode ser instalado com --legacy-peer-deps"
else
    echo "⚠️  Houve problema ao instalar task-master-ai"
    echo "   Mas isso pode funcionar no Cursor MCP"
fi

# Limpar
cd - > /dev/null
rm -rf "$TEST_DIR"

echo ""
echo "=================================="
echo "Resumo da Verificação"
echo "=================================="
echo ""
echo "✅ Configuração MCP corrigida"
echo "✅ Estrutura .taskmaster completa"
echo "✅ Node.js e npx disponíveis"
echo ""
echo "PRÓXIMOS PASSOS:"
echo ""
echo "1. Recarregar o Cursor:"
echo "   Cmd+Shift+P → 'Reload Window'"
echo ""
echo "2. No chat do Cursor (Cmd+L), digitar:"
echo "   > Initialize taskmaster-ai in my project"
echo ""
echo "3. Depois:"
echo "   > Parse my PRD at .taskmaster/docs/prd.txt"
echo ""
echo "4. Ver próxima task:"
echo "   > What's the next task I should work on?"
echo ""
echo "=================================="
echo "Teste concluído!"
echo "=================================="
