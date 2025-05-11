#!/usr/bin/env bash
#
# Toolkit for Servers - Módulo de Otimização de Desempenho (Simplificado)
#
# Este módulo implementa otimizações essenciais para servidores Linux:
# - Ajustes de parâmetros do kernel via sysctl
# - Otimização de limites de recursos via limits.conf
# - Ajustes de escalonador de I/O para diferentes tipos de armazenamento
# - Configurações de rede otimizadas
#
# O script detecta automaticamente o hardware e adapta as configurações
# com base no tipo de servidor e nos recursos disponíveis.

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

    # Variáveis globais para uso independente
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
    TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    TOTAL_MEMORY_GB=$(( (TOTAL_MEMORY_KB + 1024*1024-1) / (1024*1024) ))

    # Detecta tipo de armazenamento
    ROOT_PARTITION=$(df -h / | awk 'NR==2 {print $1}' || echo "unknown")
    ROOT_DEVICE=$(echo "$ROOT_PARTITION" | sed -E 's/p?[0-9]+$//' || echo "$ROOT_PARTITION")
    if [[ "$ROOT_DEVICE" == *"nvme"* ]]; then
        IS_NVME=true
        IS_SSD=true
    elif lsblk -d -o name,rota 2>/dev/null | grep -i "$ROOT_DEVICE" | grep -q "0"; then
        IS_SSD=true
        IS_NVME=false
    else
        IS_SSD=false
        IS_NVME=false
    fi
fi

# Otimiza o sistema
optimize_system() {
    log "INFO" "Iniciando otimização do sistema..."

    # Cria diretórios para os arquivos de configuração
    mkdir -p /etc/sysctl.d/
    mkdir -p /etc/security/limits.d/

    # Backup de configurações existentes
    local backup_dir="/etc/sysctl.d/backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"

    if [ -f /etc/sysctl.conf ]; then
        cp -a /etc/sysctl.conf "$backup_dir/"
    fi

    if [ -f /etc/security/limits.conf ]; then
        cp -a /etc/security/limits.conf "$backup_dir/"
    fi

    # Executa as otimizações básicas
    optimize_kernel_parameters
    optimize_resource_limits
    optimize_io_scheduler
    optimize_network_stack

    # Aplica as mudanças
    log "INFO" "Aplicando configurações de otimização..."
    sysctl -p /etc/sysctl.d/99-toolkit-performance.conf

    log "INFO" "Sistema otimizado com sucesso!"
    return 0
}

# Otimização de parâmetros do kernel
optimize_kernel_parameters() {
    log "INFO" "Otimizando parâmetros do kernel..."

    # Calcula valores baseados nos recursos disponíveis
    local file_max=$((TOTAL_MEMORY_GB * 256 * 1024))
    [ "$file_max" -lt 524288 ] && file_max=524288  # Mínimo de 512k

    # Define o valor de swappiness baseado na quantidade de memória
    local swappiness=10
    if [ "$TOTAL_MEMORY_GB" -lt 4 ]; then
        swappiness=30
    elif [ "$TOTAL_MEMORY_GB" -gt 64 ]; then
        swappiness=5
    fi

    # Cria arquivo de configuração sysctl
    cat > /etc/sysctl.d/99-toolkit-performance.conf << EOF
# Toolkit for Servers - Configurações de Otimização do Kernel
# Gerado em: $(date +"%Y-%m-%d %H:%M:%S")

# Parâmetros de arquivo e processo
fs.file-max = $file_max
fs.nr_open = $file_max
kernel.pid_max = 4194304
kernel.threads-max = 65536

# Parâmetros de memória
vm.swappiness = $swappiness
vm.vfs_cache_pressure = 50
vm.max_map_count = 262144

# Parâmetros de kernel
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 1
kernel.panic = 10
kernel.panic_on_oops = 1

# Parâmetros de rede - configurações gerais
net.core.somaxconn = 65536
net.core.netdev_max_backlog = 65536
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576

# Parâmetros TCP
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535

# Proteções de segurança
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF

    # Adiciona otimizações específicas para SSD/NVMe
    if [ "$IS_SSD" = "true" ]; then
        log "INFO" "Aplicando otimizações específicas para SSD..."
        cat >> /etc/sysctl.d/99-toolkit-performance.conf << EOF

# Otimizações para SSD/NVMe
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 300
EOF
    fi
}

# Otimização de limites de recursos
optimize_resource_limits() {
    log "INFO" "Otimizando limites de recursos do sistema..."

    # Cria arquivo de configuração de limites
    cat > /etc/security/limits.d/99-toolkit-limits.conf << EOF
# Toolkit for Servers - Configurações de Limites de Recursos
# Gerado em: $(date +"%Y-%m-%d %H:%M:%S")

# Limites padrão para todos os usuários
*               soft    nofile          131072
*               hard    nofile          524288
*               soft    nproc           65535
*               hard    nproc           131072
*               soft    memlock         unlimited
*               hard    memlock         unlimited
*               soft    core            unlimited
*               hard    core            unlimited

# Limites específicos para o root
root            soft    nofile          131072
root            hard    nofile          524288
root            soft    nproc           unlimited
root            hard    nproc           unlimited
EOF

    # Adiciona configuração do PAM limits se necessário
    if [ -d "/etc/pam.d" ]; then
        # Verifica se o módulo pam_limits já está configurado
        if ! grep -q "pam_limits.so" /etc/pam.d/common-session 2>/dev/null && \
           ! grep -q "pam_limits.so" /etc/pam.d/system-auth 2>/dev/null; then
            # Determina qual arquivo usar baseado na distribuição
            local pam_file=""
            if [ -f "/etc/pam.d/common-session" ]; then
                pam_file="/etc/pam.d/common-session"
            elif [ -f "/etc/pam.d/system-auth" ]; then
                pam_file="/etc/pam.d/system-auth"
            fi

            if [ -n "$pam_file" ]; then
                log "INFO" "Configurando PAM limits em $pam_file..."
                echo "session required pam_limits.so" >> "$pam_file"
            fi
        fi
    fi
}

# Otimização do escalonador de I/O
optimize_io_scheduler() {
    log "INFO" "Otimizando escalonador de I/O..."

    local scheduler=""

    # Determina o melhor escalonador baseado no tipo de armazenamento
    if [ "$IS_NVME" = "true" ]; then
        scheduler="none"
    elif [ "$IS_SSD" = "true" ]; then
        scheduler="mq-deadline"
    else
        scheduler="bfq"
    fi

    # Cria regras udev para aplicar escalonador automaticamente
    mkdir -p /etc/udev/rules.d/
    cat > /etc/udev/rules.d/60-toolkit-scheduler.rules << EOF
# Toolkit for Servers - Regras de Escalonador I/O
# Gerado em: $(date +"%Y-%m-%d %H:%M:%S")

# NVMe SSDs
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"

# SSDs regulares
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDDs
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

    # Aplica o escalonador para os dispositivos existentes
    for device in /sys/block/{sd*,nvme*n*}/queue/scheduler; do
        if [ -f "$device" ]; then
            dev_name=$(echo "$device" | cut -d/ -f4)

            # Determina o escalonador apropriado para este dispositivo
            if [[ "$dev_name" == nvme* ]]; then
                echo "none" > "$device" 2>/dev/null || true
            elif [ -f "/sys/block/$dev_name/queue/rotational" ]; then
                if [ "$(cat /sys/block/$dev_name/queue/rotational)" -eq 0 ]; then
                    echo "mq-deadline" > "$device" 2>/dev/null || true
                else
                    echo "bfq" > "$device" 2>/dev/null || true
                fi
            fi
        fi
    done

    # Ajusta parâmetros de I/O para SSDs
    if [ "$IS_SSD" = "true" ] || [ "$IS_NVME" = "true" ]; then
        for device in /sys/block/{sd*,nvme*n*}/queue/; do
            if [ -d "$device" ]; then
                # Aumenta o tamanho da fila de requisições para SSDs
                echo 1024 > "${device}nr_requests" 2>/dev/null || true

                # Aumenta o READ-AHEAD para melhorar performance de leitura sequencial
                echo 2048 > "${device}read_ahead_kb" 2>/dev/null || true
            fi
        done
    fi
}

# Otimização da pilha de rede
optimize_network_stack() {
    log "INFO" "Otimizando pilha de rede..."

    # Otimiza cada interface de rede
    for iface in $(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2}'); do
        if [ -d "/sys/class/net/$iface" ]; then
            log "INFO" "Otimizando interface de rede: $iface"

            # Aumenta o buffer da interface se o comando estiver disponível
            if command -v ethtool &> /dev/null; then
                ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true

                # Otimizações para melhor desempenho (desativa economia de energia)
                ethtool -K "$iface" gso on gro on tso on 2>/dev/null || true
            fi
        fi
    done
}

# Executa a função se o script for executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Verificar se é root
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "Este script precisa ser executado como root ou usando sudo."
        exit 1
    fi

    # Executa a função principal
    optimize_system
fi
