#!/usr/bin/env bash
#
# Toolkit for Servers - Módulo de Segurança SSH
#
# Este módulo implementa práticas de segurança recomendadas para SSH em 2025:
# - Autenticação por chave SSH (opcional)
# - Desativação de login direto como root
# - Mudança da porta padrão SSH
# - Configurações de criptografia e segurança atualizadas
# - Tempo limite para conexões inativas
# - Restrição de usuários e métodos de autenticação
# - Registro de logs aprimorado

# Importa funções comuns se executado de forma independente
if [ ! "$(type -t log)" ]; then
    # Cores para saída formatada
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # Função de log simplificada para execução standalone
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
fi

secure_ssh() {
    local ssh_port="${1:-$CUSTOM_SSH_PORT}"
    local backup_dir="/etc/ssh/backup_$(date +%Y%m%d%H%M%S)"
    local ssh_config="/etc/ssh/sshd_config"
    local ssh_config_dir="/etc/ssh/sshd_config.d"

    log "INFO" "Configurando SSH seguro..."

    # Verifica se o serviço SSH existe
    if ! command -v sshd &> /dev/null && ! command -v ssh &> /dev/null; then
        log "INFO" "SSH não encontrado. Instalando..."

        case $OS_ID in
            ubuntu|debian)
                apt-get install -y -qq openssh-server openssh-client || {
                    log "ERROR" "Falha ao instalar OpenSSH. Verifique a conexão com a internet e tente novamente."
                    return 1
                }
                ;;
            centos|almalinux|rocky)
                yum install -y openssh-server openssh-clients || {
                    log "ERROR" "Falha ao instalar OpenSSH. Verifique a conexão com a internet e tente novamente."
                    return 1
                }
                ;;
            *)
                log "ERROR" "Sistema operacional não suportado para instalação automática de SSH."
                return 1
                ;;
        esac
    fi

    # Cria backup do arquivo de configuração SSH
    log "INFO" "Fazendo backup das configurações SSH em $backup_dir"
    mkdir -p "$backup_dir"
    cp -a /etc/ssh/sshd_* "$backup_dir/"

    # Cria diretório para configurações modulares se não existir
    if [ ! -d "$ssh_config_dir" ]; then
        mkdir -p "$ssh_config_dir"
    fi

    # Verifica se a porta SSH solicitada está livre
    if [ "$ssh_port" != "22" ]; then
        if command -v netstat &> /dev/null; then
            if netstat -tuln | grep -q ":$ssh_port "; then
                log "WARN" "A porta $ssh_port já está em uso. Mantendo a porta SSH atual."
                ssh_port=$(grep "^Port " "$ssh_config" 2>/dev/null | awk '{print $2}')
                ssh_port=${ssh_port:-22}
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln | grep -q ":$ssh_port "; then
                log "WARN" "A porta $ssh_port já está em uso. Mantendo a porta SSH atual."
                ssh_port=$(grep "^Port " "$ssh_config" 2>/dev/null | awk '{print $2}')
                ssh_port=${ssh_port:-22}
            fi
        else
            log "WARN" "Impossível verificar se a porta está em uso. Prosseguindo com a mudança."
        fi
    fi

    # Cria configuração SSH segura
    local secure_ssh_config="${ssh_config_dir}/00-security.conf"
    log "INFO" "Criando configuração SSH segura em $secure_ssh_config"

    # Ciphers e MACs seguros para 2025
    cat > "$secure_ssh_config" << EOF
# Configuração SSH segura para Toolkit for Servers
# Gerado em: $(date +"%Y-%m-%d %H:%M:%S")

# Porta SSH
Port $ssh_port

# Configurações de segurança básicas
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Desabilita login root direto via SSH
PermitRootLogin no

# Configuração de autenticação
PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Criptografia (adequado para 2025)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

# Configurações de tempo limite
LoginGraceTime 30s
MaxStartups 10:30:100
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2

# Configurações adicionais de segurança
X11Forwarding no
TCPKeepAlive yes
Compression no
AllowAgentForwarding no
AllowTcpForwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp

# Registro detalhado
LogLevel VERBOSE
EOF

    # Permissões corretas para arquivos de configuração
    chmod 600 "$secure_ssh_config"

    # Testa se a configuração está correta
    if command -v sshd &> /dev/null; then
        if ! sshd -t; then
            log "ERROR" "Configuração SSH inválida. Restaurando backup..."
            cp -a "$backup_dir/sshd_config" "$ssh_config"
            rm -f "$secure_ssh_config"
            return 1
        fi
    else
        log "WARN" "Comando sshd não encontrado. Não foi possível testar a configuração."
    fi

    # Gera novas chaves de host se não existirem ou forem antigas
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ] || [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        log "INFO" "Gerando novas chaves de host SSH..."
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" < /dev/null
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" < /dev/null
    else
        # Verifica a idade das chaves (> 1 ano)
        local ed25519_age=$(stat -c %Y /etc/ssh/ssh_host_ed25519_key 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local one_year=$((365*24*60*60))

        if [ $((current_time - ed25519_age)) -gt $one_year ]; then
            log "WARN" "Chaves SSH têm mais de 1 ano. Considere renová-las com: ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''"
        fi
    fi

    # Configura autorização para usuário atual
    configure_ssh_authorized_keys

    # Reinicia o serviço SSH
    log "INFO" "Reiniciando serviço SSH..."
    if command -v systemctl &> /dev/null; then
        systemctl restart sshd || {
            log "ERROR" "Falha ao reiniciar o serviço SSH via systemctl."
            return 1
        }
    elif command -v service &> /dev/null; then
        service sshd restart || service ssh restart || {
            log "ERROR" "Falha ao reiniciar o serviço SSH via service."
            return 1
        }
    else
        log "ERROR" "Não foi possível reiniciar o serviço SSH. Faça isso manualmente."
        return 1
    fi

    # Mostrar informações da nova configuração
    log "INFO" "SSH configurado com sucesso na porta $ssh_port"
    log "INFO" "Autenticação por senha desativada - apenas chaves SSH são permitidas"
    log "INFO" "Login direto como root desativado"

    # Aviso sobre firewall
    if [ "$ssh_port" != "22" ]; then
        log "WARN" "Lembre-se de ajustar as regras de firewall para permitir a porta SSH $ssh_port"
    fi

    return 0
}

# Configura chaves SSH autorizadas
configure_ssh_authorized_keys() {
    log "INFO" "Configurando chaves SSH autorizadas..."

    # Determina o usuário corrente (não-root) para adicionar as chaves
    local current_user=$(logname 2>/dev/null || echo "$SUDO_USER" || id -un)

    # Se o usuário atual for root e SUDO_USER não estiver definido, pergunte pelo usuário
    if [ "$current_user" = "root" ] && [ -z "$SUDO_USER" ]; then
        # Lista usuários não-root com /home
        local available_users=$(grep "/home" /etc/passwd | cut -d: -f1 | grep -v "^root$")

        if [ -n "$available_users" ]; then
            log "INFO" "Usuários disponíveis:"
            echo "$available_users" | nl

            # Solicita o número do usuário
            read -p "Selecione o número do usuário para configurar as chaves SSH (ou Enter para usar o primeiro): " user_num

            if [ -z "$user_num" ]; then
                current_user=$(echo "$available_users" | head -n1)
            else
                current_user=$(echo "$available_users" | sed -n "${user_num}p")
            fi
        else
            log "WARN" "Nenhum usuário não-root encontrado com diretório home. Criando usuário..."
            current_user="admin"

            # Cria um usuário admin se não existir nenhum usuário regular
            case $OS_ID in
                ubuntu|debian)
                    adduser --disabled-password --gecos "" "$current_user"
                    ;;
                centos|almalinux|rocky)
                    adduser "$current_user"
                    ;;
                *)
                    adduser "$current_user"
                    ;;
            esac

            # Adiciona ao grupo sudo ou wheel
            if getent group sudo >/dev/null; then
                usermod -aG sudo "$current_user"
            elif getent group wheel >/dev/null; then
                usermod -aG wheel "$current_user"
            fi
        fi
    fi

    # Obtém o diretório home do usuário
    local user_home=$(eval echo ~"$current_user")
    local ssh_dir="$user_home/.ssh"

    log "INFO" "Configurando chaves SSH para o usuário: $current_user"

    # Cria diretório .ssh se não existir
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$current_user":"$current_user" "$ssh_dir"
    fi

    # Cria arquivo authorized_keys se não existir
    local auth_keys="$ssh_dir/authorized_keys"
    if [ ! -f "$auth_keys" ]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$current_user":"$current_user" "$auth_keys"
    fi

    # Verifica se existe alguma chave pública para adicionar
    local has_keys=false

    # Procura por chaves no diretório atual
    for key_file in id_rsa.pub id_ed25519.pub id_*.pub; do
        if [ -f "$key_file" ]; then
            cat "$key_file" >> "$auth_keys"
            log "INFO" "Adicionada chave pública do arquivo: $key_file"
            has_keys=true
        fi
    done

    if [ "$has_keys" = false ]; then
        log "INFO" "Nenhuma chave pública encontrada no diretório atual."
        log "INFO" "Opções para adicionar uma chave pública:"
        log "INFO" "1. Execute: ssh-copy-id ${current_user}@$(hostname -I | awk '{print $1}')"
        log "INFO" "2. Ou adicione manualmente sua chave pública ao arquivo: $auth_keys"

        # Perguntar se deseja gerar uma chave para uso emergencial
        read -p "Deseja gerar um par de chaves de emergência? (s/N): " generate_key
        if [[ "$generate_key" =~ ^[Ss]$ ]]; then
            local key_path="/tmp/emergency_key"
            ssh-keygen -t ed25519 -f "$key_path" -N "" -C "emergency-key-$(date +%Y%m%d)"
            cat "${key_path}.pub" >> "$auth_keys"
            chmod 600 "$key_path"

            # Exibe a chave privada para o usuário salvar
            log "INFO" "========== CHAVE PRIVADA DE EMERGÊNCIA =========="
            log "INFO" "SALVE ESTE CONTEÚDO EM UM LUGAR SEGURO AGORA!"
            log "INFO" "Esta é sua ÚNICA oportunidade de salvá-la."
            echo ""
            cat "$key_path"
            echo ""
            log "INFO" "============================================="

            # Remove a chave privada após exibição
            log "INFO" "A chave pública foi adicionada ao authorized_keys."
            log "INFO" "A chave privada será excluída após você pressionar ENTER."
            read -p "Pressione ENTER para continuar depois de salvar a chave privada..."
            rm -f "$key_path"
        fi
    fi

    # Configurar sudoers para o usuário se necessário (permitir sudo sem senha)
    if getent group sudo >/dev/null || getent group wheel >/dev/null; then
        if [ ! -f "/etc/sudoers.d/$current_user" ]; then
            echo "$current_user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$current_user"
            chmod 440 "/etc/sudoers.d/$current_user"
            log "INFO" "Configurado acesso sudo sem senha para $current_user"
        fi
    fi
}

# Executa a função se o script for executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Verificar se é root
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "Este script precisa ser executado como root ou usando sudo."
        exit 1
    fi

    # Detecta o SO se for executado standalone
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_ID=$ID
    fi

    # Define a porta SSH se fornecida como argumento
    SSH_PORT=${1:-22}

    # Executa a função principal
    secure_ssh "$SSH_PORT"
fi
