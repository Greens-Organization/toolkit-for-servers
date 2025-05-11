# Proteção Docker com Fail2Ban

## Visão Geral

O módulo `fail2ban.sh` do Toolkit for Servers implementa uma funcionalidade especial para detectar automaticamente e proteger ambientes Docker contra tentativas de acesso não autorizado. Este documento detalha a implementação, funcionamento e justificativa desta proteção.

## Implementação no Toolkit

### Detecção Automática do Docker

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

### Configuração da Proteção Docker

```bash
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
```

## Riscos de Segurança do Docker

### 1. Acesso Não Autorizado à API Docker

A API Docker (exposta nas portas 2375/2376) representa um vetor de ataque significativo:

1. **Risco de comprometimento completo**:
   - A API Docker fornece controle total sobre containers, volumes e redes
   - Acesso não autorizado pode permitir execução de código arbitrário no host
   - Potencial para escalação de privilégios para root no sistema host

2. **Superfície de ataque**:
   - Porta 2375: API HTTP não criptografada (extremamente perigosa se exposta)
   - Porta 2376: API HTTPS com TLS (mais segura, mas ainda crítica)

3. **Exposição acidental**:
   - Configurações incorretas frequentemente expõem a API Docker à internet
   - Binds em 0.0.0.0 em vez de 127.0.0.1
   - Ausência de autenticação TLS ou configurações TLS inadequadas

### 2. Estatísticas de Ataques

Servidores com a API Docker exposta são alvos frequentes:

- Varreduras constantes por botnets procurando especificamente pelas portas 2375/2376
- Tentativas de instalação de mineradores de criptomoedas
- Inserção em redes de DDoS
- Comprometimento para movimentação lateral em redes corporativas

## Detalhamento da Proteção Implementada

### 1. Filtro Docker Personalizado

```
[Definition]
failregex = ^time=".*" level=warning msg=".*" HTTP request: remote_ip=<HOST>.*$
ignoreregex =
```

**Análise da Expressão Regular:**

- `^time=".*"`: Corresponde ao timestamp no formato padrão de logs do Docker
- `level=warning`: Foca em entradas de log de nível WARNING
- `msg=".*"`: Captura a mensagem de erro/aviso
- `HTTP request: remote_ip=<HOST>`: Identifica o padrão específico que contém o IP remoto
- `<HOST>`: Marcador especial do Fail2Ban que captura o endereço IP a ser banido

**Justificativa:**
- Expressão focada especificamente em tentativas de acesso não autorizadas
- Ignora logs normais de operação para reduzir falsos positivos
- Detecta padrões comuns de tentativas de exploração da API

### 2. Dupla Estratégia de Logs

O script implementa uma abordagem adaptativa para fontes de log:

1. **Logs tradicionais** (`/var/log/docker.log`):
   - Compatível com configurações mais antigas do Docker
   - Funciona em sistemas que ainda usam syslog tradicional

2. **Journald** (sistemas com systemd):
   - Adaptação a sistemas modernos que utilizam logging via journald
   - Usa `journalmatch = _SYSTEMD_UNIT=docker.service` para filtrar logs específicos do Docker
   - Mais eficiente para sistemas baseados em systemd (maioria das distribuições atuais)

**Vantagem da abordagem dual:**
- Compatibilidade universal com diferentes configurações de sistema
- Adaptação automática sem necessidade de intervenção manual
- Funciona mesmo com diferentes rotações de log e configurações de logging

### 3. Parâmetros de Proteção

```bash
enabled = true
port = 2375,2376
bantime = 86400    # 24 horas
maxretry = 5
```

**Justificativa dos parâmetros:**

1. **Portas monitoradas (2375, 2376)**:
   - 2375: API Docker HTTP padrão (não criptografada)
   - 2376: API Docker HTTPS padrão (com TLS)
   - Cobertura completa das portas padrão da API Docker

2. **Tempo de banimento (86400s = 24 horas)**:
   - Alinhado com a política padrão do sistema
   - Suficiente para deter a maioria dos atacantes automatizados
   - Período longo o bastante para limitar varreduras persistentes

3. **Máximo de tentativas (5)**:
   - Equilibra usabilidade com segurança
   - Baixo o suficiente para bloquear ataques de força bruta
   - Permite algumas tentativas legítimas malsucedidas (ex: expiração de certificado)

## Melhores Práticas Adicionais

### 1. Hardening da API Docker

A proteção Fail2Ban é apenas uma camada de segurança. Recomenda-se adicionalmente:

1. **Desativar acesso remoto quando não necessário**:
   ```bash
   # Configuração segura no daemon.json
   {
     "hosts": ["unix:///var/run/docker.sock"]
   }
   ```

2. **Se acesso remoto for necessário, usar TLS mútuo**:
   ```bash
   # Configuração com TLS no daemon.json
   {
     "hosts": ["tcp://0.0.0.0:2376", "unix:///var/run/docker.sock"],
     "tls": true,
     "tlscacert": "/etc/docker/ca.pem",
     "tlscert": "/etc/docker/server-cert.pem",
     "tlskey": "/etc/docker/server-key.pem",
     "tlsverify": true
   }
   ```

3. **Usar Docker Context para clientes**:
   ```bash
   docker context create secure-remote --docker "host=tcp://server:2376,ca=/path/to/ca.pem,cert=/path/to/cert.pem,key=/path/to/key.pem"
   ```

### 2. Limitação de Acesso via Firewall

Complementar à proteção Fail2Ban:

```bash
# Limitar acesso apenas a IPs confiáveis com UFW
ufw allow from 192.168.1.100 to any port 2376 proto tcp

# Ou com FirewallD
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.100" port protocol="tcp" port="2376" accept'
```

### 3. Monitoramento Adicional

Para detecção precoce de tentativas de intrusão:

1. **Alertas em tempo real**:
   - Integrar logs Docker com sistemas SIEM
   - Configurar alertas para padrões suspeitos de acesso

2. **Auditoria regular**:
   - Verificar autorizações e acessos à API Docker
   - Monitorar criação de novos containers
   - Validar imagens em execução contra lista de aprovados

## Casos de Teste

Para verificar se a proteção Docker está funcionando corretamente:

```bash
# 1. Verificar se o filtro está carregado
sudo fail2ban-client get docker-auth failregex

# 2. Simular uma tentativa de acesso inválida (CUIDADO: teste apenas em ambientes seguros)
curl -k https://seu-servidor:2376/v1.41/containers/json

# 3. Verificar logs do Fail2Ban
sudo tail -f /var/log/fail2ban.log | grep docker

# 4. Verificar se o IP foi banido
sudo fail2ban-client status docker-auth
```

## Referências

1. Docker Security Documentation - https://docs.docker.com/engine/security/

2. CIS Docker Benchmark - https://www.cisecurity.org/benchmark/docker

3. NIST SP 800-190: "Application Container Security Guide" - https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf

4. Docker: "Protect the Docker daemon socket" - https://docs.docker.com/engine/security/protect-access/

5. Fail2Ban Wiki: "Custom Filters" - https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Filters

6. Snyk: "10 Docker Security Best Practices" - https://snyk.io/blog/10-docker-image-security-best-practices/

7. OWASP: "Docker Security Cheat Sheet" - https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html

8. DigitalOcean: "How To Secure A Containerized Node.js Application" - https://www.digitalocean.com/community/tutorials/how-to-secure-a-containerized-node-js-application-with-nginx-let-s-encrypt-and-fail2ban
