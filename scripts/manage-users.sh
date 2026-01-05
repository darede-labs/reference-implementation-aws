#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
CONFIG_FILE="${REPO_ROOT}/config.yaml"
USERS_FILE="${REPO_ROOT}/catalog/users.yaml"

# Load config
AWS_PROFILE="${AWS_PROFILE:-darede}"
COGNITO_USER_POOL_ID=$(yq eval '.cognito.user_pool_id // ""' "$CONFIG_FILE")
REGION=$(echo "$COGNITO_USER_POOL_ID" | cut -d'_' -f1)

usage() {
  echo -e "${BLUE}Gerenciamento de Usuários - Backstage + Cognito${NC}"
  echo ""
  echo "Uso: $0 <comando> [opções]"
  echo ""
  echo "Comandos:"
  echo "  add <email> <nome> [senha]    Adiciona novo usuário"
  echo "  list                          Lista todos os usuários"
  echo "  delete <email>                Remove usuário"
  echo "  reset-password <email> <nova-senha>  Reseta senha"
  echo ""
  echo "Exemplos:"
  echo "  $0 add joao@empresa.com 'João Silva' 'SenhaForte123!'"
  echo "  $0 list"
  echo "  $0 delete joao@empresa.com"
  echo ""
}

add_user() {
  local EMAIL="$1"
  local DISPLAY_NAME="$2"
  local PASSWORD="${3:-$(openssl rand -base64 12)!}"

  if [[ -z "$EMAIL" || -z "$DISPLAY_NAME" ]]; then
    echo -e "${RED}Erro: Email e nome são obrigatórios${NC}"
    usage
    exit 1
  fi

  # Extract username from email
  local USERNAME=$(echo "$EMAIL" | cut -d'@' -f1 | tr '.' '-')

  echo -e "${BLUE}Adicionando usuário: ${EMAIL}${NC}"

  # 1. Create user in Cognito
  echo -e "  1️⃣ Criando no Cognito..."
  aws cognito-idp admin-create-user \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --temporary-password "$PASSWORD" \
    --message-action SUPPRESS \
    --region "$REGION" \
    --profile "$AWS_PROFILE" > /dev/null 2>&1 || true

  # Set permanent password
  aws cognito-idp admin-set-user-password \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$EMAIL" \
    --password "$PASSWORD" \
    --permanent \
    --region "$REGION" \
    --profile "$AWS_PROFILE"

  echo -e "${GREEN}  ✓ Usuário criado no Cognito${NC}"

  # 2. Add to Backstage catalog
  echo -e "  2️⃣ Adicionando ao catálogo Backstage..."

  # Check if user already exists in catalog
  if grep -q "name: $USERNAME" "$USERS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}  ⚠ Usuário já existe no catálogo${NC}"
  else
    # Append user to catalog file
    cat >> "$USERS_FILE" << EOF
---
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: ${USERNAME}
  namespace: default
spec:
  profile:
    displayName: ${DISPLAY_NAME}
    email: ${EMAIL}
  memberOf: []
EOF
    echo -e "${GREEN}  ✓ Usuário adicionado ao catálogo${NC}"
  fi

  # 3. Update ConfigMap
  echo -e "  3️⃣ Atualizando ConfigMap no cluster..."
  kubectl create configmap backstage-users -n backstage \
    --from-file=users.yaml="$USERS_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

  # 4. Restart Backstage to pick up changes
  echo -e "  4️⃣ Reiniciando Backstage..."
  kubectl rollout restart deployment backstage -n backstage
  kubectl rollout status deployment backstage -n backstage --timeout=120s

  echo -e "\n${GREEN}✅ Usuário adicionado com sucesso!${NC}"
  echo -e "   Email: ${EMAIL}"
  echo -e "   Senha: ${PASSWORD}"
}

list_users() {
  echo -e "${BLUE}Usuários no Cognito:${NC}"
  aws cognito-idp list-users \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --query 'Users[].{Email: Attributes[?Name==`email`].Value | [0], Status: UserStatus}' \
    --output table

  echo -e "\n${BLUE}Usuários no Catálogo Backstage:${NC}"
  grep -A5 "kind: User" "$USERS_FILE" | grep -E "(name:|email:)" | paste - - | \
    awk '{print "  - " $2 " (" $4 ")"}'
}

delete_user() {
  local EMAIL="$1"

  if [[ -z "$EMAIL" ]]; then
    echo -e "${RED}Erro: Email é obrigatório${NC}"
    exit 1
  fi

  echo -e "${BLUE}Removendo usuário: ${EMAIL}${NC}"

  # Delete from Cognito
  echo -e "  1️⃣ Removendo do Cognito..."
  aws cognito-idp admin-delete-user \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$EMAIL" \
    --region "$REGION" \
    --profile "$AWS_PROFILE" 2>/dev/null || echo -e "${YELLOW}  ⚠ Usuário não encontrado no Cognito${NC}"

  echo -e "${GREEN}✅ Usuário removido${NC}"
  echo -e "${YELLOW}Nota: Para remover do catálogo, edite manualmente: ${USERS_FILE}${NC}"
}

reset_password() {
  local EMAIL="$1"
  local NEW_PASSWORD="$2"

  if [[ -z "$EMAIL" || -z "$NEW_PASSWORD" ]]; then
    echo -e "${RED}Erro: Email e nova senha são obrigatórios${NC}"
    exit 1
  fi

  echo -e "${BLUE}Resetando senha para: ${EMAIL}${NC}"

  aws cognito-idp admin-set-user-password \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --username "$EMAIL" \
    --password "$NEW_PASSWORD" \
    --permanent \
    --region "$REGION" \
    --profile "$AWS_PROFILE"

  echo -e "${GREEN}✅ Senha resetada com sucesso${NC}"
}

# Main
case "${1:-}" in
  add)
    add_user "$2" "$3" "$4"
    ;;
  list)
    list_users
    ;;
  delete)
    delete_user "$2"
    ;;
  reset-password)
    reset_password "$2" "$3"
    ;;
  *)
    usage
    exit 1
    ;;
esac
