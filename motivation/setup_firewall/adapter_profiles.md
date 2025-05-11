# Perfis de Segurança para Diferentes Tipos de Servidores

## Visão Geral

O módulo `firewall.sh` do Toolkit for Servers implementa configurações de firewall adaptadas a diferentes perfis de servidores. Este documento detalha as configurações específicas para cada tipo de servidor, explicando as escolhas de segurança e fornecendo recomendações adicionais.

## Implementação no Toolkit

O script aceita parâmetros que definem o tipo de servidor, adaptando automaticamente as regras de firewall:

```bash
setup_firewall() {
    local ssh_port="${1:-22}"
    local web_server="${2:-false}"
    local db_server="${3:-false}"
    local mail_server="${4:-false}"
    local docker="${5:-false}"
    
    # ...Configuração específica para cada tipo...
}
```

## 1. Perfil de Servidor Web

### Implementação

```bash
if [ "$web_server" = "true" ]; then
    # UFW
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    
    # FirewallD
    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
    
    # IPTables
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # Limitação de taxa para HTTP/HTTPS (em FirewallD)
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT
    
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT
}
```

### Justificativa das Escolhas

1. **Portas Abertas**: Apenas as portas HTTP (80) e HTTPS (443) são abertas explicitamente, seguindo o princípio de mínimo privilégio.

2. **Limitação de Taxa**: Implementada para HTTP/HTTPS permitindo até 30 novas conexões por minuto por IP de origem, um equilíbrio entre:
   - Desempenho para navegadores modernos (que podem abrir múltiplas conexões)
   - Proteção contra ataques de força bruta ou scraping

3. **Sem Restrições por Origem**: Diferente de SSH, as portas web são abertas para todos os IPs, permitindo acesso público ao conteúdo.

### Considerações de Segurança Adicionais

1. **Proxies Reversos**: Considere implementar NGINX ou Apache como proxy reverso para:
   - Adicionar camada extra de proteção
   - Implementar rate limiting mais sofisticado
   - Configurar buffer contra tráfego irregular

2. **CDN**: Para sites de produção voltados ao público, considere serviços como Cloudflare ou AWS CloudFront para:
   - Mitigação DDoS avançada
   - Caching que reduz carga no servidor
   - WAF (Firewall de Aplicação Web)

3. **Expansões Recomendadas**: Para maior segurança de servidores web, considere adicionar:
   - ModSecurity para proteção contra ataques comuns (SQLi, XSS)
   - Fail2ban com regras específicas para aplicações web
   - Headers de segurança (HSTS, CSP, X-Frame-Options)

## 2. Perfil de Servidor de Banco de Dados

### Implementação

```bash
if [ "$db_server" = "true" ]; then
    # Deliberadamente não abre portas de BD
    log "WARN" "Para segurança, portas de banco de dados não serão abertas."
    log "WARN" "Use SSH tunneling ou VPN para acessar o banco de dados remotamente."
}
```

### Justificativa das Escolhas

1. **Não Exposição de Portas**: O script intencionalmente não abre portas de banco de dados (MySQL: 3306, PostgreSQL: 5432, etc.), pois isso representa um alto risco de segurança.

2. **Privilégio Mínimo**: Bancos de dados raramente precisam ser acessados diretamente da internet - são quase sempre acessados por aplicações no mesmo servidor ou rede.

3. **Documentação de Melhores Práticas**: O script fornece orientações para métodos seguros de acesso remoto ao invés de abrir portas.

### Métodos Recomendados para Acesso Remoto

1. **SSH Tunneling**: Conexão segura através do canal SSH:
   ```bash
   # Exemplo para MySQL:
   ssh -L 3306:localhost:3306 usuario@servidor
   ```

2. **VPN**: Acesso através de rede privada virtual, limitando exposição:
   - OpenVPN
   - WireGuard
   - IPsec

3. **Acesso Através de Bastion Host**: Servidor intermediário dedicado que:
   - Limita origens de acesso
   - Fornece auditoria de conexões
   - Implementa autenticação adicional

### Configurações Internas Recomendadas

1. **Binding de Interface**: Configure o banco de dados para escutar apenas em localhost:
   ```
   # MySQL: my.cnf
   bind-address = 127.0.0.1
   
   # PostgreSQL: postgresql.conf
   listen_addresses = 'localhost'
   ```

2. **Autenticação Forte**: Mesmo para conexões locais, implemente:
   - Senhas complexas
   - Autenticação baseada em certificados (quando disponível)
   - Rotação periódica de credenciais

## 3. Perfil de Servidor de Email

### Implementação

```bash
if [ "$mail_server" = "true" ]; then
    # UFW
    ufw allow 25/tcp comment "SMTP"
    ufw allow 465/tcp comment "SMTPS"
    ufw allow 587/tcp comment "Submission"
    ufw allow 143/tcp comment "IMAP"
    ufw allow 993/tcp comment "IMAPS"
    ufw allow 110/tcp comment "POP3"
    ufw allow 995/tcp comment "POP3S"
    
    # FirewallD
    firewall-cmd --permanent --zone=public --add-service=smtp
    firewall-cmd --permanent --zone=public --add-service=smtps
    firewall-cmd --permanent --zone=public --add-port=587/tcp
    firewall-cmd --permanent --zone=public --add-service=imap
    firewall-cmd --permanent --zone=public --add-service=imaps
    firewall-cmd --permanent --zone=public --add-service=pop3
    firewall-cmd --permanent --zone=public --add-service=pop3s
    
    # IPTables
    iptables -A INPUT -p tcp --dport 25 -j ACCEPT
    iptables -A INPUT -p tcp --dport 465 -j ACCEPT
    # ... outras portas de email ...
}
```

### Justificativa das Portas Abertas

| Porta | Serviço | Justificativa |
|-------|---------|---------------|
| 25 | SMTP | Necessária para receber emails de outros servidores |
| 465 | SMTPS | SMTP sobre SSL (mais seguro, embora obsoleto por padrões modernos) |
| 587 | Submission | Porta moderna para envio de email autenticado por clientes |
| 143 | IMAP | Acesso a caixas de email (não criptografado) |
| 993 | IMAPS | IMAP sobre SSL (versão segura recomendada) |
| 110 | POP3 | Acesso a caixas de email (não criptografado, legado) |
| 995 | POP3S | POP3 sobre SSL (mais seguro) |

### Considerações de Segurança

1. **Superfície de Ataque Ampla**: Servidores de email têm maior superfície de ataque devido à necessidade de múltiplas portas expostas.

2. **Portas Não Criptografadas**: As portas 25, 143 e 110 são incluídas para compatibilidade, mas representam risco de segurança por não serem criptografadas.

3. **Potencial para Abuso**: Servidores SMTP podem ser utilizados para spam ou ataques se mal configurados.

### Recomendações Adicionais

1. **Configurações Anti-Spam**:
   - Implementar SPF, DKIM e DMARC
   - Utilizar software anti-spam como SpamAssassin
   - Configurar greylisting

2. **Segurança Adicional**:
   - Limitar o número de conexões SMTP por IP
   - Implementar controles de taxa de conexão
   - Utilizar listas negras (RBL) para bloquear origens conhecidas de spam

3. **Consideração de Alternativas**:
   - Avaliar serviços de email gerenciados em vez de auto-hospedagem
   - Utilizar gateways de email dedicados (Postfix + Proxy)
   - Implementar appliances virtuais de segurança de email

## 4. Perfil de Servidor Docker

### Implementação

```bash
if [ "$docker" = "true" ]; then
    # UFW
    # Configura UFW para permitir tráfego de encaminhamento
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    
    # Regras para Docker NAT
    cat << 'EOF' >> "$after_rules"
# Regras para Docker NAT
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
COMMIT
EOF
    
    # FirewallD
    # Cria uma zona específica para Docker
    firewall-cmd --permanent --new-zone=docker
    firewall-cmd --permanent --zone=docker --add-interface=docker0
    firewall-cmd --permanent --zone=docker --add-masquerade
    
    # Permite tráfego entre o host e os containers
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i docker0 -o eth0 -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i eth0 -o docker0 -j ACCEPT
    
    # IPTables
    # Adiciona regras para Docker
    iptables -A FORWARD -i docker0 -o eth0 -j ACCEPT
    iptables -A FORWARD -i eth0 -o docker0 -j ACCEPT
    iptables -t nat -A POSTROUTING -o eth0 -s 172.17.0.0/16 -j MASQUERADE
}
```

### Justificativa das Configurações

1. **Masquerading e NAT**: Essencial para permitir que containers se comuniquem com a rede externa através do endereço IP do host.

2. **Zonas Separadas**: No FirewallD, uma zona dedicada para Docker isola as regras específicas de containers do restante da configuração.

3. **Regras de Encaminhamento**: Necessárias para permitir tráfego entre containers e redes externas, mantendo a conectividade.

### Considerações de Segurança

1. **Exposição Controlada**: As configurações não expõem automaticamente containers à internet - isso ainda exige mapeamento explícito de portas.

2. **DEFAULT_FORWARD_POLICY**: Alterada de "DROP" para "ACCEPT", o que é necessário para Docker, mas também potencialmente menos seguro.

3. **Rede Docker**: Apenas a rede padrão do Docker (172.17.0.0/16) é configurada para NAT, redes customizadas exigiriam regras adicionais.

### Recomendações para Segurança do Docker

1. **Redes Definidas pelo Usuário**:
   ```bash
   docker network create --subnet=172.20.0.0/16 app_network
   ```
   - Isole containers em redes específicas para suas aplicações
   - Minimize a comunicação entre containers não relacionados

2. **Restrições de Publicação de Portas**:
   - Vincule serviços apenas a localhost quando possível:
     ```
     docker run -p 127.0.0.1:8080:80 nginx
     ```
   - Evite `-p 80:80` que expõe o serviço em todas as interfaces de rede

3. **Grupos de Segurança por Serviço**:
   - Considere múltiplas zonas FirewallD para diferentes grupos de containers
   - Implemente regras por serviço, não apenas por container

## Referências

1. **Servidores Web**:
   - OWASP: "Web Application Firewall" - https://owasp.org/www-community/Web_Application_Firewall
   - Mozilla: "Web Security Guidelines" - https://infosec.mozilla.org/guidelines/web_security
   - Nginx: "Securing HTTP Traffic" - https://docs.nginx.com/nginx/admin-guide/security-controls/

2. **Bancos de Dados**:
   - OWASP: "Database Security Cheat Sheet" - https://cheatsheetseries.owasp.org/cheatsheets/Database_Security_Cheat_Sheet.html
   - MySQL: "Security Guidelines" - https://dev.mysql.com/doc/refman/8.0/en/security-guidelines.html
   - PostgreSQL: "Security Best Practices" - https://www.postgresql.org/docs/current/admin-security-checklist.html

3. **Servidores de Email**:
   - RFC 7817: "Updated TLS Recommendations for Email" - https://tools.ietf.org/html/rfc7817
   - Mailserver Anti-Abuse: "Email Server Security" - https://www.mailserver-anti-abuse.org/
   - Postfix Documentation: "Postfix Architecture Overview" - http://www.postfix.org/OVERVIEW.html

4. **Docker**:
   - Docker Security: "Docker Security" - https://docs.docker.com/engine/security/
   - CIS Docker Benchmark - https://www.cisecurity.org/benchmark/docker
   - NIST: "Application Container Security Guide" - https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf
   - Snyk: "10 Docker Security Best Practices" - https://snyk.io/blog/10-docker-image-security-best-practices/
