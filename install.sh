#!/usr/bin/env bash
#
# Toolkit for Servers - Script de instalação automatizada
# Versão: 1.0.0
# Autor: GRN Group
# Data: 05/05/2025
#
# Uso: curl -fsSL https://grngroup.net/install.sh | bash
# Ou: curl -fsSL https://grngroup.net/install.sh | bash -s -- --ssh-port=2000
#
# Este script detecta automaticamente o sistema operacional e configura
# um ambiente de servidor seguro com mínima intervenção do usuário.

set -e          # Encerra o script se qualquer comando falhar
set -o pipefail # Propaga erros em pipes
set -u          # Trata variáveis não definidas como erro

# Cores para saída formatada
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Diretório de logs
readonly LOG_DIR="/var/log/toolkit-server"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

# Diretório temporário para downloads
readonly TMP_DIR=$(mktemp -d)

# Opções de instalação
MINIMAL_INSTALL=false
CUSTOM_SSH_PORT=22
SETUP_FIREWALL=true
ENABLE_FAIL2BAN=true
OPTIMIZE_PERFORMANCE=true

# Informações do sistema
OS_NAME=""
OS_VERSION=""
OS_ID=""
IS_CLOUD=false
IS_VPS=false
IS_DEDICATED=false
CPU_CORES=0
TOTAL_MEMORY_GB=0
TOTAL_DISK_GB=0
IS_SSD=false
IS_NVME=false

# Banner
show_banner() {
    echo -e "${BLUE}"
    echo "  ______              __ __    _  __      __                 _____                                 "
    echo " /_  __/___   ___    / //_/__ (_)/ /_    / /___  ____       / ___/___   _____ _   __ ___   _____ "
    echo "  / /  / _ \ / _ \  / ,< / -_)/ // __/   /  '_/ / __/ _    / (_ // -_) / __/| | / // -_) / ___/ "
    echo " /_/   \___//_//_/ /_/|_|\__//_/ \__/   /_/\_\ /_/   (_)   \___/ \__/ /_/   |_|/_/ \__/ /_/     "
    echo -e "${NC}"
    echo -e "${GREEN}Toolkit for Servers - Configuração Automatizada de Servidores Seguros${NC}"
    echo -e "${YELLOW}© 2025 GRN Group - https://grngroup.net${NC}"
    echo ""
}

# Função de log
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Garante que o diretório de logs existe
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || {
            echo -e "${RED}Erro ao criar diretório de logs. Executando com permissões limitadas.${NC}"
        }
    fi

    # Log para arquivo se possível
    if [[ -d "$LOG_DIR" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Log para console
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

# Função para verificar se é root
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log "ERROR" "Este script precisa ser executado como root ou usando sudo."
        exit 1
    fi
}

# Função para detectar o sistema operacional
detect_os() {
    log "INFO" "Detectando sistema operacional..."

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        OS_ID=$ID

        log "INFO" "Sistema detectado: $OS_NAME $OS_VERSION ($OS_ID)"
    else
        log "ERROR" "Não foi possível detectar o sistema operacional."
        exit 1
    fi

    # Verifica se há suporte
    case $OS_ID in
        ubuntu)
            if [[ "$OS_VERSION" != "20.04" && "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
                log "WARN" "Ubuntu $OS_VERSION não é oficialmente suportado. Tentando continuar..."
            fi
            ;;
        centos)
            if [[ "$OS_VERSION" != "7" && "$OS_VERSION" != "8" ]]; then
                log "WARN" "CentOS $OS_VERSION não é oficialmente suportado. Tentando continuar..."
            fi
            ;;
        almalinux|rocky)
            if [[ "$OS_VERSION" != "8" && "$OS_VERSION" != "9" ]]; then
                log "WARN" "$OS_NAME $OS_VERSION não é oficialmente suportado. Tentando continuar..."
            fi
            ;;
        debian)
            if [[ "$OS_VERSION" != "10" && "$OS_VERSION" != "11" && "$OS_VERSION" != "12" ]]; then
                log "WARN" "Debian $OS_VERSION não é oficialmente suportado. Tentando continuar..."
            fi
            ;;
        *)
            log "WARN" "Sistema operacional $OS_NAME não é oficialmente suportado. Tentando continuar..."
            ;;
    esac

    # Se não temos OS_ID válido, é um erro fatal
    if [[ -z "$OS_ID" ]]; then
        log "ERROR" "Falha ao detectar o ID do sistema operacional."
        exit 1
    fi
}

# Função para detectar ambiente (Cloud, VPS, Dedicado)
detect_environment() {
    log "INFO" "Detectando ambiente..."

    # Verifica se está em uma nuvem conhecida
    if grep -q "amazon\|aws" /sys/hypervisor/uuid 2>/dev/null || \
       grep -q "amazon\|aws" /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || \
       grep -q "amazon\|aws" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        IS_CLOUD=true
        log "INFO" "Ambiente detectado: AWS Cloud"
    elif grep -q "Google" /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || \
         grep -q "Google" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        IS_CLOUD=true
        log "INFO" "Ambiente detectado: Google Cloud"
    elif grep -q "Microsoft\|Azure" /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || \
         grep -q "Microsoft\|Azure" /sys/devices/virtual/dmi/id/product_name 2>/dev/null; then
        IS_CLOUD=true
        log "INFO" "Ambiente detectado: Microsoft Azure"
    elif grep -q "QEMU\|KVM" /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || \
         grep -q "QEMU\|KVM" /sys/devices/virtual/dmi/id/product_name 2>/dev/null || \
         command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt 2>/dev/null | grep -q "kvm\|qemu"; then
        IS_VPS=true
        log "INFO" "Ambiente detectado: VPS (KVM/QEMU)"
    elif grep -q "VMware" /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || \
         grep -q "VMware" /sys/devices/virtual/dmi/id/product_name 2>/dev/null || \
         command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt 2>/dev/null | grep -q "vmware"; then
        IS_VPS=true
        log "INFO" "Ambiente detectado: VPS (VMware)"
    elif grep -q "Xen" /sys/hypervisor/type 2>/dev/null || \
         command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt 2>/dev/null | grep -q "xen"; then
        IS_VPS=true
        log "INFO" "Ambiente detectado: VPS (Xen)"
    elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt 2>/dev/null | grep -q "none" || ! command -v systemd-detect-virt >/dev/null 2>&1; then
        IS_DEDICATED=true
        log "INFO" "Ambiente detectado: Servidor Dedicado"
    else
        IS_VPS=true
        log "INFO" "Ambiente detectado: VPS (tipo desconhecido)"
    fi
}

# Função para detectar hardware
detect_hardware() {
    log "INFO" "Detectando hardware..."

    # CPU cores
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
    log "INFO" "Núcleos de CPU: $CPU_CORES"

    # Memória total (em GB, arredondado)
    local TOTAL_MEMORY_KB
    TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    TOTAL_MEMORY_GB=$(( (TOTAL_MEMORY_KB + 1024*1024-1) / (1024*1024) ))
    log "INFO" "Memória Total: ${TOTAL_MEMORY_GB}GB"

    # Espaço em disco
    local ROOT_PARTITION
    ROOT_PARTITION=$(df -h / | awk 'NR==2 {print $1}' || echo "unknown")
    local ROOT_DEVICE
    ROOT_DEVICE=$(echo "$ROOT_PARTITION" | sed -E 's/p?[0-9]+$//' || echo "$ROOT_PARTITION")
    TOTAL_DISK_GB=$(df -h --total / 2>/dev/null | grep "total" | awk '{print $2}' | sed 's/G//' || echo "0")
    log "INFO" "Espaço em Disco: ~${TOTAL_DISK_GB}GB (partição /)"

    # Verifica se é SSD ou NVMe
    if [[ "$ROOT_DEVICE" == *"nvme"* ]]; then
        IS_NVME=true
        IS_SSD=true
        log "INFO" "Tipo de armazenamento: NVMe SSD"
    elif command -v lsblk >/dev/null 2>&1 && lsblk -d -o name,rota 2>/dev/null | grep -i "$ROOT_DEVICE" | grep -q "0"; then
        IS_SSD=true
        log "INFO" "Tipo de armazenamento: SSD"
    else
        log "INFO" "Tipo de armazenamento: HDD (ou desconhecido)"
    fi
}

# Função para fazer parsing dos argumentos
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh-port=*)
                CUSTOM_SSH_PORT="${1#*=}"
                log "INFO" "Porta SSH personalizada: $CUSTOM_SSH_PORT"
                ;;
            --no-firewall)
                SETUP_FIREWALL=false
                log "INFO" "Configuração de firewall desativada"
                ;;
            --no-fail2ban)
                ENABLE_FAIL2BAN=false
                log "INFO" "Instalação do Fail2ban desativada"
                ;;
            --no-optimize)
                OPTIMIZE_PERFORMANCE=false
                log "INFO" "Otimização de desempenho desativada"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "WARN" "Argumento desconhecido: $1"
                ;;
        esac
        shift
    done
}

# Mostra ajuda
show_help() {
    cat << EOF
Uso: curl -fsSL https://grngroup.net/install.sh | bash -s -- [OPÇÕES]

Opções:
  --ssh-port=PORTA  Define uma porta SSH personalizada (padrão: 22)
  --no-firewall     Desativa a configuração do firewall
  --no-fail2ban     Desativa a instalação do Fail2ban
  --no-optimize     Desativa otimizações de desempenho
  --help, -h        Mostra esta mensagem de ajuda

Exemplos:
  curl -fsSL https://grngroup.net/install.sh | bash
  curl -fsSL https://grngroup.net/install.sh | bash -s -- --ssh-port=2222
EOF
}

# Prepara sistema para instalação
prepare_system() {
    log "INFO" "Preparando sistema para instalação..."

    # Cria diretório temporário
    mkdir -p "$TMP_DIR/modules"

    # Atualiza repositórios de pacotes baseado na distribuição
    case $OS_ID in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || log "WARN" "Não foi possível atualizar os repositórios. Continuando..."
            apt-get install -y -qq curl wget git sudo ca-certificates gnupg lsb-release apt-transport-https || log "WARN" "Falha ao instalar pacotes essenciais."
            ;;
        centos|almalinux|rocky)
            yum -y install epel-release || log "WARN" "Não foi possível instalar EPEL. Algumas funcionalidades podem não estar disponíveis."
            yum update -y -q || log "WARN" "Não foi possível atualizar os repositórios. Continuando..."
            yum install -y curl wget git sudo ca-certificates gnupg || log "WARN" "Falha ao instalar pacotes essenciais."
            ;;
        *)
            log "WARN" "Sistema operacional não reconhecido para atualização de pacotes."
            log "WARN" "Por favor, atualize manualmente os repositórios e instale: curl wget git sudo"
            ;;
    esac
}

# Função para verificar integridade do download
verify_download() {
    local file=$1
    local module_name=$2

    if [[ ! -f "$file" ]]; then
        log "ERROR" "Falha ao baixar o módulo $module_name"
        return 1
    fi

    # Verifica se o arquivo tem conteúdo válido (não está vazio e é um script shell)
    if [[ ! -s "$file" ]] || ! grep -q "#!/usr/bin/env bash" "$file"; then
        log "ERROR" "O arquivo $module_name parece corrompido ou inválido"
        return 1
    fi

    return 0
}

# Função principal
main() {
    show_banner
    check_root

    # Configurar limpeza ao sair
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Parseia argumentos se fornecidos
    if [[ $# -gt 0 ]]; then
        parse_args "$@"
    fi

    # Detecta ambiente e hardware
    detect_os || { log "ERROR" "Falha na detecção do sistema operacional. Abortando."; exit 1; }
    detect_environment
    detect_hardware

    # Prepara o sistema
    prepare_system

    # Diretório de módulos
    local MODULES_DIR="$TMP_DIR/modules"

    log "INFO" "Iniciando configuração do servidor..."

    # 1. Configuração segura de SSH
    log "INFO" "Configurando SSH seguro..."
    if curl -fsSL "https://grngroup.net/modules/secure_ssh.sh" -o "$MODULES_DIR/secure_ssh.sh"; then
        chmod +x "$MODULES_DIR/secure_ssh.sh"
        if verify_download "$MODULES_DIR/secure_ssh.sh" "SSH seguro"; then
            # shellcheck disable=SC1090
            if source "$MODULES_DIR/secure_ssh.sh"; then
                secure_ssh "$CUSTOM_SSH_PORT"
            else
                log "ERROR" "Falha ao carregar o módulo de SSH seguro."
            fi
        fi
    else
        log "ERROR" "Falha ao baixar o módulo de SSH seguro."
    fi

    # 2. Configuração do Firewall (se não desativado)
    if [[ "$SETUP_FIREWALL" = true ]]; then
        log "INFO" "Configurando Firewall..."
        if curl -fsSL "https://grngroup.net/modules/setup_firewall.sh" -o "$MODULES_DIR/setup_firewall.sh"; then
            chmod +x "$MODULES_DIR/setup_firewall.sh"
            if verify_download "$MODULES_DIR/setup_firewall.sh" "Firewall"; then
                # shellcheck disable=SC1090
                if source "$MODULES_DIR/setup_firewall.sh"; then
                    # Configura o firewall apenas com SSH
                    setup_firewall "$CUSTOM_SSH_PORT" "true" "true" "false" "true"
                else
                    log "ERROR" "Falha ao carregar o módulo de Firewall."
                fi
            fi
        else
            log "ERROR" "Falha ao baixar o módulo de Firewall."
        fi
    else
        log "INFO" "Configuração do Firewall desativada pelo usuário."
    fi

    # 3. Configuração do Fail2Ban (se não desativado)
    if [[ "$ENABLE_FAIL2BAN" = true ]]; then
        log "INFO" "Configurando Fail2Ban..."
        if curl -fsSL "https://grngroup.net/modules/setup_fail2ban.sh" -o "$MODULES_DIR/setup_fail2ban.sh"; then
            chmod +x "$MODULES_DIR/setup_fail2ban.sh"
            if verify_download "$MODULES_DIR/setup_fail2ban.sh" "Fail2Ban"; then
                # shellcheck disable=SC1090
                if source "$MODULES_DIR/setup_fail2ban.sh"; then
                    setup_fail2ban "$CUSTOM_SSH_PORT"
                else
                    log "ERROR" "Falha ao carregar o módulo do Fail2Ban."
                fi
            fi
        else
            log "ERROR" "Falha ao baixar o módulo do Fail2Ban."
        fi
    else
        log "INFO" "Configuração do Fail2Ban desativada pelo usuário."
    fi

    # 4. Otimização do Sistema (se não desativado)
    if [[ "$OPTIMIZE_PERFORMANCE" = true ]]; then
        log "INFO" "Otimizando sistema..."
        if curl -fsSL "https://grngroup.net/modules/optimize_system.sh" -o "$MODULES_DIR/optimize_system.sh"; then
            chmod +x "$MODULES_DIR/optimize_system.sh"
            if verify_download "$MODULES_DIR/optimize_system.sh" "Otimização do sistema"; then
                # shellcheck disable=SC1090
                if source "$MODULES_DIR/optimize_system.sh"; then
                    optimize_system
                else
                    log "ERROR" "Falha ao carregar o módulo de otimização do sistema."
                fi
            fi
        else
            log "ERROR" "Falha ao baixar o módulo de otimização do sistema."
        fi
    else
        log "INFO" "Otimização de desempenho desativada pelo usuário."
    fi

    # Exibe resumo da instalação
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    log "INFO" "Instalação concluída com sucesso!"
    log "INFO" "IP do servidor: $IP_ADDRESS"
    log "INFO" "Porta SSH: $CUSTOM_SSH_PORT"
    log "INFO" "Ambiente detectado: $(if [[ "$IS_CLOUD" = true ]]; then echo "Cloud"; elif [[ "$IS_VPS" = true ]]; then echo "VPS"; else echo "Servidor Dedicado"; fi)"
    log "INFO" "Hardware: ${CPU_CORES} cores, ${TOTAL_MEMORY_GB}GB RAM, ${TOTAL_DISK_GB}GB disk ($(if [[ "$IS_SSD" = true ]]; then echo "SSD"; else echo "HDD"; fi))"
    log "INFO" "Para ver os logs detalhados: cat $LOG_FILE"
}

# Executa a função principal passando todos os argumentos
main "$@"
