# Compatibilidade Cross-Platform do Fail2Ban

## Visão Geral

O módulo `fail2ban.sh` do Toolkit for Servers implementa uma estratégia de compatibilidade cross-platform que garante funcionamento consistente em diferentes distribuições Linux. Este documento detalha as abordagens e técnicas utilizadas para garantir essa compatibilidade universal.

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

### Detecção de Gerenciador de Serviços

```bash
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
```

### Abstração de Fontes de Log

```bash
# Para SSH
logpath = %(sshd_log)s
backend = %(sshd_backend)s

# Para Docker via journald
backend = systemd
journalmatch = _SYSTEMD_UNIT=docker.service
```

## Diferenças entre Distribuições

### Mapeamento de Sistemas Operacionais

O script lida automaticamente com as principais diferenças entre distribuições Linux:

| Distribuição | Gerenciador de Pacotes | Pacotes Adicionais | Local de Logs |
|--------------|------------------------|-------------------|---------------|
| Ubuntu       | apt                    | fail2ban          | `/var/log/auth.log` |
| Debian       | apt                    | fail2ban          | `/var/log/auth.log` |
| CentOS       | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` |
| AlmaLinux    | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` |
| Rocky Linux  | yum                    | epel-release, fail2ban, fail2ban-systemd | `/var/log/secure` |

### Diferenças Específicas por Distribuição

1. **Repositórios EPEL no Red Hat/CentOS**:
   - Sistemas baseados em RHEL requerem o repositório EPEL para instalar o Fail2Ban
   - O script verifica automaticamente se o EPEL já está instalado antes de prosseguir
   - Instalação transparente do EPEL quando necessário

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

### 1. Variáveis Internas do Fail2Ban

O script aproveita as variáveis internas do Fail2Ban para abstração:

```bash
# Exemplo: configuração SSH
logpath = %(sshd_log)s
backend = %(sshd_backend)s
```

Estas variáveis são automaticamente resolvidas pelo Fail2Ban baseado na distribuição:

| Variável | Ubuntu/Debian | CentOS/RHEL |
|----------|---------------|-------------|
| `%(sshd_log)s` | `/var/log/auth.log` | `/var/log/secure` |
| `%(sshd_backend)s` | `auto` (geralmente pyinotify) | `auto` (geralmente systemd) |

**Vantagens desta abordagem:**
- Elimina necessidade de lógica condicional complexa
- Adapta-se automaticamente à estrutura de cada distribuição
- Mantém-se funcional mesmo após atualizações do sistema

### 2. Detecção Automática de Backend

```bash
# Configuração principal do Fail2Ban
backend = auto
```

O parâmetro `backend = auto` faz o Fail2Ban selecionar automaticamente:
- `systemd`: Em sistemas usando journald
- `pyinotify`: Em sistemas com suporte a inotify
- `gamin`: Em alguns sistemas mais antigos
- `polling`: Como último recurso, monitoramento por polling

**Benefícios:**
- Melhor desempenho em cada plataforma
- Adaptação automática à infraestrutura de logging
- Funcionamento suave em sistemas híbridos

### 3. Múltiplas Estratégias para Logs Docker

```bash
# Estratégia 1: Logs tradicionais
if [ -f "/var/log/docker.log" ]; then
    # Configuração para arquivos de log tradicionais
    ...
else
    # Estratégia 2: Journald
    if command -v journalctl &> /dev/null; then
        # Configuração para journald
        ...
    fi
fi
```

**Benefício da abordagem múltipla:**
- Cobertura para diferentes configurações de logging do Docker
- Adaptação a diferentes versões e configurações do Docker
- Graceful degradation quando opções preferenciais não estão disponíveis

## Verificação e Diagnóstico Cross-Platform

Para verificar que o Fail2Ban está funcionando corretamente em qualquer distribuição:

```bash
# 1. Verificar status do serviço (funciona em todas as distribuições)
sudo fail2ban-client status

# 2. Verificar regras de firewall (método independente de distribuição)
sudo iptables -L | grep f2b

# 3. Testar configuração (compatível com todas as distribuições)
sudo fail2ban-client -d

# 4. Verificar logs
# Para sistemas systemd:
sudo journalctl -u fail2ban

# Para sistemas não-systemd:
sudo tail -f /var/log/fail2ban.log
```

## Recomendações para Extensão

Para adicionar suporte a distribuições adicionais:

1. **Alpine Linux**:
   ```bash
   # Adicionar ao case statement
   alpine)
       apk add --no-cache fail2ban
       ;;
   ```

2. **Arch Linux**:
   ```bash
   # Adicionar ao case statement
   arch|manjaro)
       pacman -Sy --noconfirm fail2ban
       ;;
   ```

3. **SUSE/openSUSE**:
   ```bash
   # Adicionar ao case statement
   suse|opensuse*)
       zypper install -y fail2ban
       ;;
   ```

## Referências

1. Fail2Ban Wiki - Supported Systems - https://www.fail2ban.org/wiki/index.php/Main_Page

2. Red Hat Documentation - "Installing and Using Fail2Ban" - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-using_fail2ban

3. Debian Wiki - Fail2Ban - https://wiki.debian.org/Fail2ban

4. Ubuntu Server Guide - Fail2Ban - https://ubuntu.com/server/docs/security-fail2ban

5. DigitalOcean - "How To Protect SSH with Fail2Ban on CentOS 7" - https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-centos-7

6. Arch Linux Wiki - Fail2Ban - https://wiki.archlinux.org/title/Fail2ban

7. Fail2Ban on GitHub - Distribution Specifics - https://github.com/fail2ban/fail2ban/wiki/Distribution-Packaging

8. EPEL Wiki - https://fedoraproject.org/wiki/EPEL
