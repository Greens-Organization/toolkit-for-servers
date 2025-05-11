#!/usr/bin/env bash
#
# Toolkit for Servers - Módulo de Configuração de Firewall
#
# Este módulo implementa configurações de firewall utilizando:
# - UFW (para Ubuntu/Debian)
# - FirewallD (para CentOS/RHEL/AlmaLinux)
# - IPTables como fallback para outros sistemas
#
# O script detecta automaticamente qual ferramenta usar e configura
# regras adequadas baseadas no perfil do servidor.

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

# Configura o firewall
setup_firewall() {
    local ssh_port="${1:-22}"
    local web_server="${2:-false}"
    local db_server="${3:-false}"
    local mail_server="${4:-false}"
    local docker="${5:-false}"

    log "INFO" "Configurando firewall..."

    # Detecta qual firewall usar
    if command -v ufw &> /dev/null; then
        setup_ufw "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
    elif command -v firewall-cmd &> /dev/null; then
        setup_firewalld "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
    elif command -v iptables &> /dev/null; then
        setup_iptables "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
    else
        # Tenta instalar UFW ou FirewallD
        if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
            log "INFO" "Firewall não encontrado. Instalando UFW..."
            apt-get update -qq
            apt-get install -y -qq ufw
            setup_ufw "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
        elif [ "$OS_ID" = "centos" ] || [ "$OS_ID" = "almalinux" ] || [ "$OS_ID" = "rocky" ]; then
            log "INFO" "Firewall não encontrado. Instalando FirewallD..."
            yum install -y firewalld
            systemctl enable firewalld
            systemctl start firewalld
            setup_firewalld "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
        else
            log "ERROR" "Não foi possível instalar um firewall. Configure manualmente."
            return 1
        fi
    fi
}

# Configuração de UFW (Ubuntu/Debian)
setup_ufw() {
    local ssh_port="${1:-22}"
    local web_server="${2:-false}"
    local db_server="${3:-false}"
    local mail_server="${4:-false}"
    local docker="${5:-false}"

    log "INFO" "Configurando UFW..."

    # Reseta regras existentes
    ufw --force reset

    # Configuração padrão
    ufw default deny incoming
    ufw default allow outgoing

    # Permite SSH
    ufw allow "$ssh_port/tcp" comment "SSH"

    # Configurações adicionais baseadas no tipo de servidor
    if [ "$web_server" = "true" ]; then
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
    fi

    if [ "$db_server" = "true" ]; then
        # Não abrimos portas de DB diretamente
        log "WARN" "Para segurança, portas de banco de dados não serão abertas."
        log "WARN" "Use SSH tunneling ou VPN para acessar o banco de dados remotamente."
    fi

    if [ "$mail_server" = "true" ]; then
        ufw allow 25/tcp comment "SMTP"
        ufw allow 465/tcp comment "SMTPS"
        ufw allow 587/tcp comment "Submission"
        ufw allow 143/tcp comment "IMAP"
        ufw allow 993/tcp comment "IMAPS"
        ufw allow 110/tcp comment "POP3"
        ufw allow 995/tcp comment "POP3S"
    fi

    if [ "$docker" = "true" ]; then
        # Configura UFW para Docker
        log "INFO" "Configurando UFW para trabalhar com Docker..."

        # Verifica se o arquivo de configuração existe
        if [ -f /etc/default/ufw ]; then
            # Configura UFW para permitir tráfego de encaminhamento
            sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

            # Adiciona regras para NAT no arquivo after.rules
            local after_rules="/etc/ufw/after.rules"
            if ! grep -q "DOCKER NAT" "$after_rules"; then
                cat << 'EOF' >> "$after_rules"

# Regras para Docker NAT
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
COMMIT
EOF
            fi
        else
            log "WARN" "Arquivo /etc/default/ufw não encontrado. Configure manualmente o UFW para Docker."
        fi
    fi

    # Configurações avançadas de segurança
    # Proteção contra ataques de força bruta e escaneamento de portas
    if ! grep -q "RATE LIMITING" /etc/ufw/before.rules; then
        cat << 'EOF' >> /etc/ufw/before.rules

# RATE LIMITING
# Protege contra ataques de força bruta e escaneamento de portas
*filter
:ufw-rate-limit - [0:0]
:ufw-rate-reject - [0:0]
-A ufw-rate-limit -m hashlimit --hashlimit-mode srcip --hashlimit-above 30/min --hashlimit-burst 10 --hashlimit-htable-expire 60000 -j ufw-rate-reject
-A ufw-rate-reject -j DROP
COMMIT
EOF
    fi

    # Anti-spoofing
    if [ -f /etc/ufw/before.rules ]; then
        if ! grep -q "ANTI-SPOOFING" /etc/ufw/before.rules; then
            sed -i '/*filter/i # ANTI-SPOOFING\n-A FORWARD -i docker0 -o eth0 -j ACCEPT\n-A FORWARD -i eth0 -o docker0 -j ACCEPT\n' /etc/ufw/before.rules
        fi
    fi

    # Configura rate limiting para SSH
    ufw route allow proto tcp from any to any port "$ssh_port" comment "SSH Rate Limiting" \
        recent name=ssh set seconds=60 hits=10

    # Protege contra ataques de escaneamento de portas
    ufw limit in on eth0 to any port "$ssh_port" proto tcp

    # Proteção básica anti-DDoS
    if ! grep -q "ANTI-DDOS" /etc/ufw/before.rules; then
        cat << 'EOF' >> /etc/ufw/before.rules

# ANTI-DDOS
*filter
:ufw-ddos - [0:0]
-A ufw-ddos -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
-A ufw-ddos -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,ACK FIN -j DROP
-A ufw-ddos -p tcp --tcp-flags ACK,URG URG -j DROP
-A ufw-ddos -p tcp --tcp-flags ACK,FIN FIN -j DROP
-A ufw-ddos -p tcp --tcp-flags ACK,PSH PSH -j DROP
-A ufw-ddos -p tcp --tcp-flags ALL ALL -j DROP
-A ufw-ddos -p tcp --tcp-flags ALL NONE -j DROP
-A ufw-ddos -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
-A ufw-ddos -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
-A ufw-ddos -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
COMMIT
EOF
    fi

    # Habilita o firewall
    echo "y" | ufw enable
    ufw status verbose

    log "INFO" "UFW configurado com sucesso!"
    return 0
}

# Configuração de FirewallD (CentOS/RHEL/AlmaLinux)
setup_firewalld() {
    local ssh_port="${1:-22}"
    local web_server="${2:-false}"
    local db_server="${3:-false}"
    local mail_server="${4:-false}"
    local docker="${5:-false}"

    log "INFO" "Configurando FirewallD..."

    # Inicia e habilita o serviço
    systemctl enable firewalld
    systemctl start firewalld

    # Configuração padrão
    firewall-cmd --set-default-zone=public

    # Reseta regras existentes
    firewall-cmd --permanent --zone=public --remove-service=ssh || true

    # Permite SSH na porta personalizada
    if [ "$ssh_port" != "22" ]; then
        firewall-cmd --permanent --zone=public --add-port="$ssh_port/tcp"
    else
        firewall-cmd --permanent --zone=public --add-service=ssh
    fi

    # Configurações adicionais baseadas no tipo de servidor
    if [ "$web_server" = "true" ]; then
        firewall-cmd --permanent --zone=public --add-service=http
        firewall-cmd --permanent --zone=public --add-service=https
    fi

    if [ "$db_server" = "true" ]; then
        # Não abrimos portas de DB diretamente
        log "WARN" "Para segurança, portas de banco de dados não serão abertas."
        log "WARN" "Use SSH tunneling ou VPN para acessar o banco de dados remotamente."
    fi

    if [ "$mail_server" = "true" ]; then
        firewall-cmd --permanent --zone=public --add-service=smtp
        firewall-cmd --permanent --zone=public --add-service=smtps
        firewall-cmd --permanent --zone=public --add-port=587/tcp
        firewall-cmd --permanent --zone=public --add-service=imap
        firewall-cmd --permanent --zone=public --add-service=imaps
        firewall-cmd --permanent --zone=public --add-service=pop3
        firewall-cmd --permanent --zone=public --add-service=pop3s
    fi

    if [ "$docker" = "true" ]; then
        # Configura FirewallD para Docker
        log "INFO" "Configurando FirewallD para trabalhar com Docker..."

        # Cria uma zona para Docker
        firewall-cmd --permanent --new-zone=docker || true

        # Adiciona interface do Docker à zona
        firewall-cmd --permanent --zone=docker --add-interface=docker0 || true

        # Configura masquerading para permitir containers acessar a rede externa
        firewall-cmd --permanent --zone=docker --add-masquerade

        # Permite tráfego entre o host e os containers
        firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i docker0 -o eth0 -j ACCEPT
        firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i eth0 -o docker0 -j ACCEPT
    fi

    # Proteção básica anti-DDoS
    # Limita o número de conexões simultâneas
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --syn --dport "$ssh_port" -m connlimit --connlimit-above 10 -j REJECT

    # Limita a taxa de novas conexões
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT

    # Se houver servidor web, adiciona proteção contra escaneamento
    if [ "$web_server" = "true" ]; then
        # Limita a taxa de novas conexões para HTTP/HTTPS
        firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --set
        firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT

        firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --set
        firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT
    fi

    # Aplica as configurações
    firewall-cmd --reload
    firewall-cmd --list-all

    log "INFO" "FirewallD configurado com sucesso!"
    return 0
}

# Configuração de IPTables (fallback)
setup_iptables() {
    local ssh_port="${1:-22}"
    local web_server="${2:-false}"
    local db_server="${3:-false}"
    local mail_server="${4:-false}"
    local docker="${5:-false}"

    log "INFO" "Configurando IPTables..."

    # Limpa todas as regras existentes
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Política padrão
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Permitir tráfego loopback
    iptables -A INPUT -i lo -j ACCEPT

    # Permitir conexões estabelecidas e relacionadas
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Permitir SSH
    iptables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT

    # Configurações adicionais baseadas no tipo de servidor
    if [ "$web_server" = "true" ]; then
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    fi

    if [ "$mail_server" = "true" ]; then
        iptables -A INPUT -p tcp --dport 25 -j ACCEPT
        iptables -A INPUT -p tcp --dport 465 -j ACCEPT
        iptables -A INPUT -p tcp --dport 587 -j ACCEPT
        iptables -A INPUT -p tcp --dport 143 -j ACCEPT
        iptables -A INPUT -p tcp --dport 993 -j ACCEPT
        iptables -A INPUT -p tcp --dport 110 -j ACCEPT
        iptables -A INPUT -p tcp --dport 995 -j ACCEPT
    fi

    if [ "$docker" = "true" ]; then
        # Adiciona regras para Docker
        iptables -A FORWARD -i docker0 -o eth0 -j ACCEPT
        iptables -A FORWARD -i eth0 -o docker0 -j ACCEPT
        iptables -t nat -A POSTROUTING -o eth0 -s 172.17.0.0/16 -j MASQUERADE
    fi

    # Proteção básica anti-DDoS
    # Limita o número de conexões simultâneas
    iptables -A INPUT -p tcp --syn --dport "$ssh_port" -m connlimit --connlimit-above 10 -j REJECT

    # Limita a taxa de novas conexões
    iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT

    # Protege contra pacotes mal formados
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

    # Salva configurações
    if command -v iptables-save &> /dev/null; then
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
        elif [ -d "/etc/sysconfig" ]; then
            iptables-save > /etc/sysconfig/iptables
        else
            iptables-save > /etc/iptables.rules

            # Cria serviço para restaurar as regras na inicialização
            cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables firewall rules
Before=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules
ExecStop=/sbin/iptables-save -c /etc/iptables.rules
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable iptables-restore.service
        fi
    else
        log "WARN" "iptables-save não encontrado. As regras serão perdidas após a reinicialização."
        log "WARN" "Instale o pacote iptables-persistent para manter as regras."
    fi

    # Lista as regras configuradas
    iptables -L -v

    log "INFO" "IPTables configurado com sucesso!"
    return 0
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
    WEB_SERVER=false
    DB_SERVER=false
    MAIL_SERVER=false
    DOCKER=false

    # Processa argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh-port=*)
                SSH_PORT="${1#*=}"
                shift
                ;;
            --web)
                WEB_SERVER=true
                shift
                ;;
            --db)
                DB_SERVER=true
                shift
                ;;
            --mail)
                MAIL_SERVER=true
                shift
                ;;
            --docker)
                DOCKER=true
                shift
                ;;
            *)
                log "WARN" "Argumento desconhecido: $1"
                shift
                ;;
        esac
    done

    # Executa a função principal
    setup_firewall "$SSH_PORT" "$WEB_SERVER" "$DB_SERVER" "$MAIL_SERVER" "$DOCKER"
fi
