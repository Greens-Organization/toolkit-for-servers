# Documentação de Configuração do Fail2Ban

Este documento explica as escolhas de configuração implementadas no módulo `fail2ban.sh` do Toolkit for Servers, detalhando a proteção contra ataques de força bruta e outras tentativas de intrusão.

## Visão Geral

O módulo Fail2Ban implementa um sistema de detecção e bloqueio de intrusões que:
- Monitora logs de serviços em busca de padrões de atividade suspeita
- Bloqueia temporariamente endereços IP que demonstram comportamento malicioso
- Adapta-se automaticamente aos serviços instalados no servidor
- Opera como uma camada adicional de segurança complementar ao firewall

## Principais Configurações Implementadas

### 1. Parâmetros de Proteção Globais

**Implementação:**
```bash
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
EOF
```

**Justificativa dos Parâmetros:**

1. **bantime (86400 segundos = 24 horas):**
   - Banimento prolongado dificulta ataques persistentes e automatizados
   - O período de 24 horas reduz significativamente a janela de oportunidade para atacantes
   - Longo o suficiente para desencorajar ataques, mas não permanente para evitar bloqueios acidentais permanentes

2. **findtime (600 segundos = 10 minutos):**
   - Janela de tempo adequada para detectar tentativas sistemáticas de ataque
   - Curta o suficiente para reagir rapidamente a ataques agressivos
   - Equilibra detecção oportuna com redução de falsos positivos

3. **maxretry (5 tentativas):**
   - Permite erros humanos genuínos (digitação incorreta de senha)
   - Número baixo o suficiente para bloquear tentativas óbvias de força bruta
   - Valor ajustado para equilibrar usabilidade e segurança

4. **ignoreip (redes locais e privadas):**
   - Evita bloqueios acidentais de usuários legítimos da rede interna
   - Inclui todas as faixas de IP privadas (RFC 1918)
   - Previne auto-bloqueio do servidor durante administração local

### 2. [Configuração Específica para SSH](./ssh_protection.md)

**Implementação:**
```bash
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
```

**Justificativa:**

1. **Detecção Automática da Porta SSH:**
   - Sincronização com a porta personalizada definida no módulo SSH
   - Garante proteção mesmo quando a porta SSH padrão é alterada
   - Integração perfeita com o módulo de segurança SSH

2. **bantime Estendido (172800 segundos = 48 horas):**
   - Tempo de bloqueio maior para SSH comparado ao padrão global
   - Proteção extra para o serviço mais visado em ataques
   - Desencorajamento adicional contra tentativas persistentes

3. **Uso de Variáveis de Backend e Logpath:**
   - `%(sshd_log)s` e `%(sshd_backend)s` são variáveis especiais do Fail2Ban
   - Adaptam-se automaticamente à localização dos logs em diferentes distribuições
   - Compatibilidade com sistemas que usam syslog tradicional ou journald

### 3. [Ações de Banimento](./notification_and_actions.md)

**Implementação:**
```bash
# Ação padrão (bane e envia email)
banaction = iptables-multiport
banaction_allports = iptables-allports

# Ação para executar quando um IP for banido
# action = %(action_)s
action = %(action_mw)s

# Opção para enviar emails ao administrador quando um IP for banido
destemail = root@localhost
sender = fail2ban@localhost
mta = sendmail
```

**Justificativa:**

1. **Ações Baseadas em IPTables:**
   - Compatibilidade universal com todos os sistemas Linux
   - Integração direta com o sistema de firewall do kernel
   - Baixo overhead e alta confiabilidade

2. **Notificação por Email (action_mw):**
   - Alerta administradores sobre atividades suspeitas em tempo real
   - Permite investigação manual quando necessário
   - Facilita auditoria de segurança e rastreamento de padrões de ataque

3. **Configurações de Email:**
   - Uso de `root@localhost` como destinatário padrão (geralmente encaminhado para o administrador)
   - Identifica claramente a origem das notificações via `sender`
   - Compatibilidade com MTA (Mail Transfer Agent) padrão

### 4. [Detecção Automatizada de Serviços]

**Implementação:**
```bash
# Detecta e configura serviços adicionais
detect_and_configure_services() {
    log "INFO" "Detectando serviços adicionais para configuração do Fail2Ban..."

    # Verifica Docker
    if command -v docker &> /dev/null; then
        configure_docker_protection
    fi
}
```

**Justificativa:**

1. **Função de Detecção Modular:**
   - Arquitetura extensível para adicionar serviços futuros facilmente
   - Configuração apenas para serviços realmente instalados
   - Reduz complexidade e overhead em servidores de propósito específico

2. **Abordagem de Descoberta Automática:**
   - Elimina necessidade de configuração manual para cada serviço
   - Adapta-se automaticamente ao perfil do servidor
   - Melhora a experiência "out-of-the-box" para administradores

### 5. [Proteção para Docker](./docker_protection.md)

**Implementação:**
```bash
# Cria filtro personalizado para Docker
cat > /etc/fail2ban/filter.d/docker-auth.conf << EOF
[Definition]
failregex = ^time=".*" level=warning msg=".*" HTTP request: remote_ip=<HOST>.*$
ignoreregex =
EOF

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
```

**Justificativa:**

1. **Expressão Regular Customizada:**
   - Focada em detectar tentativas de autenticação inválidas na API Docker
   - Extrai corretamente o IP de origem dos logs do Docker
   - Ignora mensagens de log normais para reduzir falsos positivos

2. **Proteção nas Portas da API Docker:**
   - Cobre ambas as portas padrão (2375 não-TLS e 2376 TLS)
   - Previne ataques de força bruta contra a API Docker
   - Proteção crítica para ambientes onde a API Docker é exposta

3. **Adaptação aos Logs do Sistema:**
   - Suporte tanto para logs tradicionais quanto para journald
   - Detecta automaticamente o método de logging do sistema
   - Implementa configuração alternativa quando necessário

## [Implementação Cross-Platform](./cross_platform_compatibility.md)

### Detecção e Instalação Automática

```bash
# Verifica se o Fail2Ban está instalado
if ! command -v fail2ban-server &> /dev/null; then
    log "INFO" "Fail2Ban não encontrado. Instalando..."

    case $OS_ID in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq fail2ban
            ;;
        centos|almalinux|rocky)
            if ! rpm -q epel-release &> /dev/null; then
                yum install -y epel-release
            fi
            yum install -y fail2ban fail2ban-systemd
            ;;
        *)
            log "ERROR" "Sistema operacional não suportado para instalação automática do Fail2Ban."
            log "ERROR" "Por favor, instale o Fail2Ban manualmente e tente novamente."
            return 1
            ;;
    esac
fi
```

**Considerações de Compatibilidade:**

1. **Distribuições Debian/Ubuntu:**
   - Instalação direta via apt
   - Disponível nos repositórios padrão
   - Configuração padronizada

2. **Distribuições Red Hat (CentOS/AlmaLinux/Rocky):**
   - Requer repositório EPEL (verificação e instalação automática)
   - Instalação do pacote adicional fail2ban-systemd para melhor integração
   - Abordagem diferenciada para lidar com peculiaridades do Red Hat

3. **Gerenciamento de Serviços:**
   - Detecção automática de systemd ou init tradicional
   - Ativação e reinício do serviço de forma apropriada
   - Verificação de status para confirmar funcionamento correto

### Backup das Configurações Existentes

```bash
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
```

**Justificativa:**

1. **Timestamping Único:** Cada execução cria um backup com timestamp único, permitindo histórico de alterações.

2. **Preservação de Configurações Personalizadas:** Impede perda de configurações anteriores durante atualização.

3. **Rollback Facilitado:** Permite retorno rápido a configurações anteriores em caso de problemas.

## Considerações Sobre Segurança

### 1. Abordagem Multi-camada

O Fail2Ban funciona como parte de uma estratégia de segurança em camadas:

- **Integração com Firewall:** Complementa as regras de limitação de taxa no firewall
- **Proteção Comportamental:** Enquanto o firewall impõe regras estáticas, o Fail2Ban reage a comportamentos suspeitos
- **Defesa Adaptativa:** Bloqueia dinamicamente origens maliciosas mesmo que elas sigam regras de firewall

### 2. Impacto em Recursos

A configuração implementada leva em consideração o impacto em recursos do servidor:

- **Backend Auto:** Detecta e utiliza o método mais eficiente disponível (systemd ou files)
- **Regras IPTables Eficientes:** Usa iptables-multiport para reduzir o número de regras
- **Logs Otimizados:** Define nível de log apropriado para balancear informação e tamanho de arquivo

### 3. Mitigação de Riscos

A configuração mitiga vários riscos comuns:

- **Auto-bloqueio:** Previne através da lista ignoreip abrangente
- **Sobrecarga do Sistema:** Limita o tamanho de logs e frequência de ações
- **Falsos Positivos:** Equilibra maxretry para reduzir bloqueios acidentais

## Recomendações Adicionais

Para aumentar ainda mais a segurança proporcionada pelo Fail2Ban, considere:

1. **Monitoramento Adicional:**
   - Instalar ferramentas como LogWatch ou GoAccess para análise regular de logs
   - Configurar verificações periódicas do status do Fail2Ban

2. **Expansão para Outros Serviços:**
   - Adicionar proteção para serviços web (Apache, Nginx)
   - Configurar proteção para FTP, SMTP, e outros serviços expostos
   - Implementar jails personalizadas para aplicações específicas

3. **Notificações Avançadas:**
   - Configurar roteamento de email para endereços externos
   - Integrar com sistemas de monitoramento (Nagios, Zabbix, etc.)
   - Implementar notificações via Slack, Discord ou outros serviços

## Referências

1. Fail2Ban Documentation - https://www.fail2ban.org/wiki/index.php/Main_Page

2. Digital Ocean - "How To Protect SSH With Fail2Ban" - https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-20-04

3. Red Hat - "Using Fail2Ban to Secure Your Server" - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-using-fail2ban-to-secure-your-server

4. OWASP - "Authentication Cheat Sheet" - https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html

5. Docker Security - "Protecting the Docker Daemon Socket" - https://docs.docker.com/engine/security/protect-access/

6. CIS Benchmarks - "Linux Security Configuration" - https://www.cisecurity.org/benchmark/distribution_independent_linux

7. NIST SP 800-123 - "Guide to General Server Security" - https://csrc.nist.gov/publications/detail/sp/800-123/final

8. Fail2Ban Wiki - "Filters" - https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Filters
