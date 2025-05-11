# Compatibilidade Cross-Platform do Fail2Ban

## Visão Geral

O módulo `fail2ban.sh` do Toolkit for Servers implementa uma estratégia de compatibilidade cross-platform que garante funcionamento consistente em diferentes distribuições Linux. Este documento detalha as abordagens e técnicas utilizadas para garantir essa compatibilidade universal, com foco especial na detecção e configuração automática do backend correto.

## Implementação no Toolkit

### Detecção e Instalação Específica por Sistema Operacional

```bash
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
```

### Detecção Automática de Systemd

```bash
# Detecta se o sistema está usando systemd
detect_systemd() {
    if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
        log "INFO" "Sistema usando systemd detectado."
        return 0
    else
        log "INFO" "Sistema sem systemd detectado."
        return 1
    fi
}
```

### Detecção de Arquivos de Log SSH

```bash
# Detecta os arquivos de log do SSH
detect_ssh_logs() {
    # Array para armazenar caminhos de logs encontrados
    local ssh_logs=()

    # Verificar logs comuns do SSH
    local common_logs=(
        "/var/log/auth.log"
        "/var/log/secure"
        "/var/log/audit/audit.log"
    )

    for log_file in "${common_logs[@]}"; do
        if [ -f "$log_file" ]; then
            ssh_logs+=("$log_file")
            log "INFO" "Arquivo de log SSH encontrado: $log_file"
        fi
    done

    # Se nenhum arquivo de log tradicional for encontrado, verificar se journald tem logs do SSH
    if [ ${#ssh_logs[@]} -eq 0 ] && command -v journalctl &> /dev/null; then
        if journalctl _COMM=sshd -n 1 &> /dev/null; then
            log "INFO" "Logs SSH encontrados no journald (systemd)."
            return 0
        else
            log "WARN" "Nenhum log SSH encontrado no journald."
            return 1
        fi
    fi

    if [ ${#ssh_logs[@]} -gt 0 ]; then
        return 0
    else
        log "WARN" "Nenhum arquivo de log SSH encontrado."
        return 1
    fi
}
```

### Configuração do Backend Baseada na Detecção

```bash
# Detecta se estamos usando systemd e escolhe o backend apropriado
local backend="auto"
local ssh_backend=""
local uses_systemd=false
local ssh_logpath="%(sshd_log)s"
    
if detect_systemd; then
    # Verifica se systemd tem logs do SSH
    if journalctl _COMM=sshd -n 1 &> /dev/null; then
        backend="systemd"
        ssh_backend="systemd"
        ssh_logpath=""
        uses_systemd=true
        log "INFO" "Usando systemd como backend para logs do SSH."
    else
        log "WARN" "Systemd detectado, mas não encontrou logs do SSH. Tentando detectar arquivos de log."
        if detect_ssh_logs; then
            log "INFO" "Usando arquivos de log tradicionais para SSH com backend auto."
        else
            log "WARN" "Nenhum log SSH encontrado. Tentando usar systemd mesmo assim."
            backend="systemd"
            ssh_backend="systemd"
            ssh_logpath=""
            uses_systemd=true
        fi
    fi
else
    if ! detect_ssh_logs; then
        log "WARN" "Nenhum log SSH encontrado. O Fail2Ban pode não funcionar corretamente."
    fi
fi
```

### Configuração Adaptativa para SSH

```bash
# Configuração para SSH
if [ "$uses_systemd" = true ]; then
    # Configuração específica para systemd
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = $ssh_port
filter = sshd
backend = systemd
journalmatch = _SYSTEMD_UNIT=sshd.service + _COMM=sshd
maxretry = 5
bantime = 172800
EOF
else
    # Configuração para logs tradicionais
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = $ssh_logpath
backend = $ssh_backend
maxretry = 5
bantime = 172800
EOF
fi
```

## Diferenças entre Distribuições

### Mapeamento de Sistemas Operacionais

O script lida automaticamente com as principais diferenças entre distribuições Linux:

| Distribuição | Gerenciador de Pacotes | Pacotes Adicionais | Local de Logs | Backend Típico |
|--------------|------------------------|-------------------|---------------|----------------|
| Ubuntu       | apt                    | fail2ban          | `/var/log/auth.log` | auto (pyinotify) |
| Debian       | apt                    | fail2ban          | `/var/log/auth.log` | auto (pyinotify) |
| CentOS       | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` | systemd |
| AlmaLinux    | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` | systemd |
| Rocky Linux  | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` | systemd |

### Diferenças Específicas por Distribuição

1. **Integração com Systemd**:
   - Distribuições modernas usam exclusivamente journald
   - Distribuições híbridas usam tanto arquivos de log como journald
   - Distribuições antigas usam apenas arquivos de log tradicionais
   - O script detecta cada caso e adapta a configuração

2. **Pacote fail2ban-systemd em Red Hat/CentOS**:
   - Distribuições RHEL requerem o pacote adicional para integração correta com systemd
   - Instalado automaticamente junto com o pacote principal
   - Garante funcionalidade completa em sistemas com journald

3. **Gerenciamento de Serviços**:
   - Detecção automática entre systemd e init tradicional
   - Uso de `systemctl` para sistemas modernos
   - Fallback para `service` em sistemas mais antigos
   - Alertas claros se nenhum método funcionar

## Técnicas de Compatibilidade

### 1. Detecção Proativa de Systemd

O script implementa detecção proativa do sistema de inicialização:

```bash
if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
    # Sistema usando systemd
else
    # Sistema usando init tradicional
fi
```

**Vantagens desta abordagem:**
- Identificação precisa do método de gerenciamento de serviços
- Adaptação imediata ao ambiente de execução
- Base para decisões sobre backend de log

### 2. Detecção Inteligente de Logs

O script implementa uma estratégia em camadas para detecção de logs:

1. Procura por arquivos de log tradicionais em locais específicos de cada distribuição
2. Verifica se o journald contém logs do serviço quando arquivos tradicionais não são encontrados
3. Configura o backend com base no método de logging detectado

**Benefícios:**
- Funciona em sistemas que migraram completamente para journald
- Funciona em sistemas híbridos (com ambos os métodos)
- Funciona em sistemas tradicionais (apenas arquivos de log)
- Fornece alertas claros quando nenhum log é encontrado

### 3. Configuração Específica por Backend

O script gera configurações adaptadas ao backend detectado:

**Para journald (systemd):**
```
[sshd]
enabled = true
port = $ssh_port
filter = sshd
backend = systemd
journalmatch = _SYSTEMD_UNIT=sshd.service + _COMM=sshd
```

**Para sistemas tradicionais:**
```
[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = $ssh_logpath
backend = $ssh_backend
```

**Benefícios da abordagem dupla:**
- Configurações otimizadas para cada tipo de sistema
- Uso correto das diretivas específicas de cada backend
- Prevenção de erros comuns como "log file not found"

### 4. Parâmetro fail_on_missing_logfile

```bash
# Prevenção de falhas quando logs não são encontrados
fail_on_missing_logfile = false
```

O parâmetro `fail_on_missing_logfile = false` é crucial para distribuições modernas onde:
- Logs estão exclusivamente no journald (sem arquivos físicos)
- Arquivos de log são gerados dinamicamente pelo rsyslog
- Serviços usam rotação de logs agressiva

**Impacto:**
- Evita falhas na inicialização do Fail2Ban
- Permite que o serviço continue funcionando mesmo se os logs não existirem inicialmente
- Especialmente importante em sistemas que usam containers ou ambientes cloud com logs externos

### 5. Configuração Explícita de allowipv6

```bash
# Permitir IPv6 explicitamente para evitar warnings
allowipv6 = auto
```

Esta configuração explícita:
- Elimina warnings no log
- Garante comportamento consistente em todas as distribuições
- Melhora a legibilidade dos logs para depuração

## Verificação e Diagnóstico Cross-Platform

Para verificar que o Fail2Ban está funcionando corretamente em qualquer distribuição:

```bash
# 1. Verificar status do serviço (funciona em todas as distribuições)
sudo fail2ban-client status

# 2. Verificar regras de firewall (método independente de distribuição)
sudo iptables -L | grep f2b

# 3. Testar configuração (compatível com todas as distribuições)
sudo fail2ban-client -d

# 4. Verificar logs (adaptativo por distribuição)
# Para sistemas systemd:
sudo journalctl -u fail2ban

# Para sistemas não-systemd:
sudo tail -f /var/log/fail2ban.log
```

## Recomendações para Extensão

Para adicionar suporte a outras distribuições modernas que usam exclusivamente systemd:

1. **Fedora**:
   ```bash
   # Adicionar ao case statement
   fedora)
       dnf install -y fail2ban
       ;;
   ```

2. **Arch Linux**:
   ```bash
   # Adicionar ao case statement
   arch|manjaro)
       pacman -Sy --noconfirm fail2ban
       # Arch Linux usa exclusivamente systemd
       ;;
   ```

3. **SUSE/openSUSE**:
   ```bash
   # Adicionar ao case statement
   suse|opensuse*)
       zypper install -y fail2ban
       # openSUSE usa systemd como padrão
       ;;
   ```

## Principais Benefícios da Detecção Automática de Backend

1. **Zero configuração necessária pelo usuário final**
   - O script determina automaticamente a configuração ótima
   - Nenhuma pesquisa ou ajuste manual necessário

2. **Adaptabilidade a ambientes heterogêneos**
   - Funciona em servidores com configurações personalizadas de logging
   - Adaptável a diferentes versões de distribuições

3. **Resiliência a mudanças de sistema**
   - Se a distribuição migrar para systemd nas atualizações, o script se adapta
   - Se logs forem movidos ou reconfigados, o script detectará as mudanças

4. **Manutenibilidade simplificada**
   - Um único script que funciona em diversas plataformas
   - Lógica clara de fallback quando opções primárias não estão disponíveis

## Referências

1. Fail2Ban Wiki - Systemd Integration - https://www.fail2ban.org/wiki/index.php/HOWTO_fail2ban_with_systemd

2. Red Hat Documentation - "Using journald with Fail2Ban" - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/security_guide/using-fail2ban-to-protect-against-brute-force-attacks

3. Debian Wiki - Fail2Ban with Systemd - https://wiki.debian.org/Fail2ban#Systemd_integration

4. Ubuntu Server Guide - Fail2Ban and journald - https://ubuntu.com/server/docs/security-fail2ban

5. DigitalOcean - "How To Configure Fail2Ban with journald in CentOS 7" - https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs

6. Arch Linux Wiki - Fail2Ban with Systemd - https://wiki.archlinux.org/title/Fail2ban#Systemd_integration

7. Fail2Ban Backend Documentation - https://github.com/fail2ban/fail2ban/wiki/Backends
