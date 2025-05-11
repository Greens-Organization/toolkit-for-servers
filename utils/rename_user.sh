#!/usr/bin/env bash
#
# Script para renomear um usuário existente no Linux
#
# Uso: sudo ./rename_user.sh usuario_antigo novo_usuario
#
# Autor: Toolkit for Servers

# Cores para saída formatada
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Função de log
log() {
    local level=$1
    local message=$2

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "[${level}] $message"
            ;;
    esac
}

# Verifica se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR" "Este script precisa ser executado como root ou usando sudo."
    exit 1
fi

# Verifica se foram fornecidos os parâmetros corretos
if [ $# -ne 2 ]; then
    log "ERROR" "Uso: $0 usuario_antigo novo_usuario"
    exit 1
fi

OLD_USER="$1"
NEW_USER="$2"

# Verifica se o usuário antigo existe
if ! id "$OLD_USER" &>/dev/null; then
    log "ERROR" "O usuário '$OLD_USER' não existe."
    exit 1
fi

# Verifica se o novo nome de usuário já existe
if id "$NEW_USER" &>/dev/null; then
    log "ERROR" "O usuário '$NEW_USER' já existe. Escolha outro nome."
    exit 1
fi

# Verifica se o usuário a ser renomeado está logado
if who | grep -q "^$OLD_USER "; then
    log "WARN" "O usuário '$OLD_USER' está atualmente logado no sistema."
    log "WARN" "É recomendável que o usuário seja deslogado antes de continuar."

    read -p "Deseja continuar mesmo assim? (s/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Ss]$ ]]; then
        log "INFO" "Operação cancelada pelo usuário."
        exit 0
    fi
fi

# Verifica se há processos em execução do usuário
RUNNING_PROCESSES=$(ps -u "$OLD_USER" --no-headers | wc -l)
if [ "$RUNNING_PROCESSES" -gt 0 ]; then
    log "WARN" "Há $RUNNING_PROCESSES processos em execução para o usuário '$OLD_USER'."
    log "WARN" "Isso pode causar problemas durante a renomeação."

    ps -u "$OLD_USER" -o pid,cmd --no-headers

    read -p "Deseja continuar mesmo assim? (s/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Ss]$ ]]; then
        log "INFO" "Operação cancelada pelo usuário."
        exit 0
    fi
fi

# Obter o grupo principal do usuário antigo
OLD_GROUP=$(id -gn "$OLD_USER")

# Backup do estado atual
log "INFO" "Criando backup das informações do usuário..."
mkdir -p /root/"$OLD_USER"_migration_backup
cp /etc/passwd /etc/shadow /etc/group /etc/gshadow /root/"$OLD_USER"_migration_backup/

# Inicia o processo de renomeação
log "INFO" "Iniciando processo de renomeação de '$OLD_USER' para '$NEW_USER'..."

# 1. Renomear o usuário
log "INFO" "Renomeando o login do usuário..."
usermod -l "$NEW_USER" "$OLD_USER" || {
    log "ERROR" "Falha ao renomear o usuário. Abortando."
    exit 1
}

# 2. Renomear o grupo principal se ele tiver o mesmo nome do usuário
if [ "$OLD_GROUP" = "$OLD_USER" ]; then
    log "INFO" "Renomeando o grupo principal..."
    groupmod -n "$NEW_USER" "$OLD_USER" || {
        log "ERROR" "Falha ao renomear o grupo. Tentando restaurar o usuário..."
        usermod -l "$OLD_USER" "$NEW_USER"
        exit 1
    }
fi

# 3. Mover e renomear o diretório home
if [ -d "/home/$OLD_USER" ]; then
    log "INFO" "Atualizando o diretório home para /home/$NEW_USER..."
    usermod -d "/home/$NEW_USER" -m "$NEW_USER" || {
        log "WARN" "Falha ao mover o diretório home automaticamente."
        log "INFO" "Tentando mover manualmente..."

        # Criar novo diretório home se não existir
        if [ ! -d "/home/$NEW_USER" ]; then
            mkdir -p "/home/$NEW_USER"
        fi

        # Copiar arquivos e preservar atributos
        cp -a "/home/$OLD_USER/." "/home/$NEW_USER/"

        # Atualizar o caminho no passwd
        usermod -d "/home/$NEW_USER" "$NEW_USER"

        # Remover diretório antigo somente se a cópia foi bem-sucedida
        if [ $? -eq 0 ]; then
            rm -rf "/home/$OLD_USER"
        else
            log "ERROR" "Falha ao mover o diretório home. Verifique manualmente."
        fi
    }

    # Corrigir permissões do novo diretório home
    log "INFO" "Corrigindo permissões no novo diretório home..."
    chown -R "${NEW_USER}:${NEW_USER}" "/home/$NEW_USER" || {
        log "WARN" "Falha ao ajustar as permissões. Verifique manualmente."
    }
fi

# 4. Atualizar o shell se necessário
log "INFO" "Verificando e atualizando o shell..."
USER_SHELL=$(grep "^$NEW_USER:" /etc/passwd | cut -d: -f7)
if [ -z "$USER_SHELL" ] || [ "$USER_SHELL" = "/bin/false" ] || [ "$USER_SHELL" = "/usr/sbin/nologin" ]; then
    log "INFO" "Definindo shell padrão para o usuário..."
    usermod -s "/bin/bash" "$NEW_USER"
fi

# 5. Verificar se o usuário está em grupos especiais (sudo/wheel)
log "INFO" "Verificando associação a grupos especiais..."
if groups "$NEW_USER" | grep -q '\<sudo\>'; then
    log "INFO" "O usuário já pertence ao grupo sudo."
elif getent group sudo >/dev/null; then
    log "INFO" "Adicionando o usuário ao grupo sudo..."
    usermod -aG sudo "$NEW_USER"
fi

if groups "$NEW_USER" | grep -q '\<wheel\>'; then
    log "INFO" "O usuário já pertence ao grupo wheel."
elif getent group wheel >/dev/null; then
    log "INFO" "Adicionando o usuário ao grupo wheel..."
    usermod -aG wheel "$NEW_USER"
fi

# 6. Verificar arquivos sudoers
if [ -f "/etc/sudoers.d/$OLD_USER" ]; then
    log "INFO" "Atualizando configuração do sudoers..."
    sed "s/$OLD_USER/$NEW_USER/g" "/etc/sudoers.d/$OLD_USER" > "/etc/sudoers.d/$NEW_USER"
    chmod 440 "/etc/sudoers.d/$NEW_USER"
    rm -f "/etc/sudoers.d/$OLD_USER"
fi

# 7. Verificar se há arquivos no sistema que precisam ser atualizados
log "INFO" "Verificando outras referências ao usuário anterior (pode demorar)..."
SYSTEM_FILES_WITH_OLD_USER=$(grep -l "$OLD_USER" /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers* 2>/dev/null)

if [ -n "$SYSTEM_FILES_WITH_OLD_USER" ]; then
    log "WARN" "Os seguintes arquivos ainda contêm referências ao usuário antigo:"
    echo "$SYSTEM_FILES_WITH_OLD_USER"
    log "WARN" "Você pode precisar atualizar esses arquivos manualmente."
fi

# Verificação final
log "INFO" "Verificando se a renomeação foi bem-sucedida..."
if id "$NEW_USER" &>/dev/null; then
    log "INFO" "=== Resumo da operação ==="
    log "INFO" "Usuário '$OLD_USER' renomeado para '$NEW_USER' com sucesso."
    log "INFO" "Novo diretório home: /home/$NEW_USER"
    log "INFO" "UID: $(id -u "$NEW_USER")"
    log "INFO" "Grupo principal: $(id -gn "$NEW_USER") (GID: $(id -g "$NEW_USER"))"
    log "INFO" "Grupos: $(id -Gn "$NEW_USER")"
    log "INFO" "Shell: $(grep "^$NEW_USER:" /etc/passwd | cut -d: -f7)"

    # Sugestão para operações adicionais
    log "INFO" "=== Próximos passos ==="
    log "INFO" "1. Verifique se o usuário pode fazer login normalmente."
    log "INFO" "2. Verifique se as permissões de arquivos estão corretas no diretório home."
    log "INFO" "3. Verifique se as configurações de aplicativos específicos do usuário ainda funcionam."

    exit 0
else
    log "ERROR" "Falha ao verificar o novo usuário. Algo deu errado durante o processo."
    log "ERROR" "Verifique manualmente o estado do sistema."
    exit 1
fi
