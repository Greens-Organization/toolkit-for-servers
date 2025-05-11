#!/usr/bin/env bash
#
# Toolkit for Servers - Módulo de Configuração do Fail2Ban
#
# Este módulo instala e configura o Fail2Ban para proteger contra:
# - Ataques de força bruta no SSH
#
# O script detecta automaticamente os serviços instalados e adapta
# as configurações adequadamente.

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

# Configura o Fail2Ban
setup_fail2ban() {
    local ssh_port="${1:-22}"
    local ban_time="${2:-86400}"  # 24 horas em segundos
    local find_time="${3:-600}"   # 10 minutos em segundos
    local max_retry="${4:-5}"     # 5 tentativas

    log "INFO" "Configurando Fail2Ban..."

    # Verifica se o Fail2Ban está instalado
    if ! command -v fail2ban-server &> /dev/null; then
        log "INFO" "Fail2Ban não encontrado. Instalando..."

        case $OS_ID in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y -qq fail2ban || {
                    log "ERROR" "Falha ao instalar Fail2Ban. Verifique a conexão com a internet e tente novamente."
                    return 1
                }
                ;;
            centos|almalinux|rocky)
                if ! rpm -q epel-release &> /dev/null; then
                    yum install -y epel-release || {
                        log "ERROR" "Falha ao instalar EPEL repository. Verifique a conexão com a internet e tente novamente."
                        return 1
                    }
                fi
                yum install -y fail2ban fail2ban-systemd || {
                    log "ERROR" "Falha ao instalar Fail2Ban. Verifique a conexão com a internet e tente novamente."
                    return 1
                }
                ;;
            *)
                log "ERROR" "Sistema operacional não suportado para instalação automática do Fail2Ban."
                log "ERROR" "Por favor, instale o Fail2Ban manualmente e tente novamente."
                return 1
                ;;
        esac
    fi

    log "INFO" "Criando configurações do Fail2Ban..."

    # Cria diretório de backup
    local backup_dir="/etc/fail2ban/backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup das configurações existentes
    if [ -f /etc/fail2ban/jail.local ]; then
        cp -a /etc/fail2ban/jail.local "$backup_dir/"
    fi
    if [ -f /etc/fail2ban/jail.conf ]; then
        cp -a /etc/fail2ban/jail.conf "$backup_dir/"
    fi

    # Cria diretório para configurações personalizadas
    mkdir -p /etc/fail2ban/jail.d

    # Configuração principal do Fail2Ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Banimento por 24 horas (86400 segundos)
bantime = $ban_time
# Tempo de observação: 10 minutos (600 segundos)
findtime = $find_time
# Máximo de tentativas antes do banimento
maxretry = $max_retry

# Ignorar IPs locais e de redes privadas
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

# Ação padrão (bane e envia email)
banaction = iptables-multiport
banaction_allports = iptables-allports

# Use systemd para monitoramento quando disponível
backend = auto

# Ação para executar quando um IP for banido
# action = %(action_)s
action = %(action_mw)s

# Opção para enviar emails ao administrador quando um IP for banido
destemail = root@localhost
sender = fail2ban@localhost
mta = sendmail

# Configurações de protocolo e níveis de log
protocol = tcp
loglevel = INFO
logtarget = /var/log/fail2ban.log
EOF

    # Configuração para SSH
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = %(sshd_log)s
backend = %(sshd_backend)s
# Aumentamos para 10 tentativas apenas para SSH
maxretry = 5
# Aumentamos o bantime para 48 horas em caso de ataque SSH
bantime = 172800
EOF

    # Detecta e configura serviços adicionais
    detect_and_configure_services

    # Reinicia o Fail2Ban
    log "INFO" "Reiniciando o serviço Fail2Ban..."
    if command -v systemctl &> /dev/null; then
        systemctl enable fail2ban
        systemctl restart fail2ban
    elif command -v service &> /dev/null; then
        service fail2ban restart
    else
        log "WARN" "Não foi possível reiniciar o serviço Fail2Ban automaticamente."
        log "WARN" "Por favor, reinicie o serviço manualmente."
    fi

    # Verifica se o serviço está rodando
    sleep 2
    if command -v systemctl &> /dev/null && systemctl is-active fail2ban &> /dev/null; then
        log "INFO" "Fail2Ban está rodando corretamente."
    elif command -v service &> /dev/null && service fail2ban status &> /dev/null; then
        log "INFO" "Fail2Ban está rodando corretamente."
    else
        log "WARN" "Não foi possível verificar se o Fail2Ban está rodando."
        log "WARN" "Verifique o status do serviço manualmente."
    fi

    log "INFO" "Fail2Ban configurado com sucesso!"
    log "INFO" "Configurações:"
    log "INFO" "- Tempo de banimento: $(($ban_time/3600)) horas"
    log "INFO" "- Período de observação: $(($find_time/60)) minutos"
    log "INFO" "- Máximo de tentativas: $max_retry"

    return 0
}

# Detecta e configura serviços adicionais
detect_and_configure_services() {
    log "INFO" "Detectando serviços adicionais para configuração do Fail2Ban..."

    # Verifica Docker
    if command -v docker &> /dev/null; then
        configure_docker_protection
    fi
}

# Configuração para Docker
configure_docker_protection() {
    log "INFO" "Configurando proteção Fail2Ban para Docker..."

    # Cria filtro personalizado para Docker
    cat > /etc/fail2ban/filter.d/docker-auth.conf << EOF
[Definition]
failregex = ^time=".*" level=warning msg=".*" HTTP request: remote_ip=<HOST>.*$
ignoreregex =
EOF

    # Procura logs do Docker
    if [ -f "/var/log/docker.log" ]; then
        # Cria configuração para Docker
        cat > /etc/fail2ban/jail.d/docker.local << EOF
[docker-auth]
enabled = true
port = 2375,2376
filter = docker-auth
logpath = /var/log/docker.log
bantime = 86400
maxretry = 5
EOF
        log "INFO" "Proteção para Docker configurada com sucesso!"
    else
        # Configuração alternativa usando journald
        if command -v journalctl &> /dev/null; then
            cat > /etc/fail2ban/jail.d/docker-journald.local << EOF
[docker-auth]
enabled = true
port = 2375,2376
filter = docker-auth
backend = systemd
journalmatch = _SYSTEMD_UNIT=docker.service
bantime = 86400
maxretry = 5
EOF
            log "INFO" "Proteção para Docker (via journald) configurada com sucesso!"
        else
            log "WARN" "Docker detectado, mas não foi possível encontrar os logs."
            log "WARN" "A proteção para Docker não foi configurada."
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

    # Parâmetros padrão
    SSH_PORT=22
    BAN_TIME=86400     # 24 horas
    FIND_TIME=600      # 10 minutos
    MAX_RETRY=5        # 5 tentativas

    # Processa argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh-port=*)
                SSH_PORT="${1#*=}"
                shift
                ;;
            --ban-time=*)
                BAN_TIME="${1#*=}"
                shift
                ;;
            --find-time=*)
                FIND_TIME="${1#*=}"
                shift
                ;;
            --max-retry=*)
                MAX_RETRY="${1#*=}"
                shift
                ;;
            *)
                log "WARN" "Argumento desconhecido: $1"
                shift
                ;;
        esac
    done

    # Executa a função principal
    setup_fail2ban "$SSH_PORT" "$BAN_TIME" "$FIND_TIME" "$MAX_RETRY"
fi
