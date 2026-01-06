#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/utils.sh"

echo -e "${CYAN}🔄 Forçando refresh do Backstage catalog...${NC}"

# Restart Backstage pod to force catalog reload
echo -e "${YELLOW}⏳ Reiniciando pod do Backstage...${NC}"
kubectl rollout restart deployment/backstage -n backstage --kubeconfig $KUBECONFIG_FILE

echo -e "${YELLOW}⏳ Aguardando pod reiniciar...${NC}"
kubectl rollout status deployment/backstage -n backstage --kubeconfig $KUBECONFIG_FILE --timeout=300s

echo -e "${GREEN}✅ Backstage reiniciado! Templates atualizados.${NC}"
echo -e "${CYAN}📋 Aguarde ~30 segundos e recarregue a página do Backstage (F5)${NC}"
