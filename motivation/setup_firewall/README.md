# Documentação de Configuração de Firewall

Este documento explica as escolhas de configuração implementadas no módulo `firewall.sh` do Toolkit for Servers, detalhando as abordagens de segurança aplicadas para UFW, FirewallD e IPTables.

## Visão Geral

O módulo de firewall implementa uma configuração defensiva que:
- Detecta automaticamente a ferramenta de firewall disponível (UFW, FirewallD, IPTables)
- Adapta as regras ao perfil do servidor (web, banco de dados, email, Docker)
- Implementa proteções contra ataques comuns (DDoS, força bruta, escaneamento de portas)
- Mantém uma postura de segurança restritiva por padrão

## Principais Configurações Implementadas

### 1. Política de Negação por Padrão

**Implementação nos três firewalls:**
```bash
# UFW
ufw default deny incoming
ufw default allow outgoing

# FirewallD (implícito na zona pública)
firewall-cmd --set-default-zone=public

# IPTables
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
```

**Justificativa:** Seguindo o princípio de mínimo privilégio, essa configuração bloqueia todo o tráfego de entrada exceto o explicitamente permitido. Esta é uma prática de segurança fundamental que reduz drasticamente a superfície de ataque do servidor.

**Benefícios:**
- Expõe apenas os serviços estritamente necessários
- Elimina riscos de portas abertas não intencionalmente
- Simplifica a auditoria de segurança (todas as permissões são explícitas)

### 2. Permissão Seletiva para SSH

**Implementação nos três firewalls:**
```bash
# UFW
ufw allow "$ssh_port/tcp" comment "SSH"

# FirewallD
if [ "$ssh_port" != "22" ]; then
    firewall-cmd --permanent --zone=public --add-port="$ssh_port/tcp"
else
    firewall-cmd --permanent --zone=public --add-service=ssh
fi

# IPTables
iptables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
```

**Justificativa:** Permite acesso SSH na porta configurada (padrão ou personalizada), mantendo compatibilidade com o módulo de segurança SSH que pode alterar a porta padrão.

**Consideração de Segurança:** A flexibilidade para usar uma porta não-padrão complementa a estratégia de segurança do módulo SSH, reduzindo a visibilidade em varreduras automatizadas.

### 3. Proteção Contra Ataques de Força Bruta

**Implementação unificada:**
```bash
# UFW
ufw route allow proto tcp from any to any port "$ssh_port" comment "SSH Rate Limiting" \
    recent name=ssh set seconds=60 hits=10

# FirewallD
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT

# IPTables
iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT
```

**Justificativa:** Limita o número de novas conexões SSH a 10 por minuto, mitigando ataques de força bruta ao restringir a taxa de tentativas de conexão.

**Complementação:** Estas regras complementam ferramentas como Fail2ban, oferecendo uma primeira linha de defesa integrada ao firewall.

### 4. [Proteção Anti-DDoS](./anti_ddos_protection.md)

**Implementação em UFW:**
```bash
# Proteção Anti-DDoS em UFW
*filter
:ufw-ddos - [0:0]
-A ufw-ddos -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
-A ufw-ddos -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
# ... outras regras de pacotes malformados
```

**Implementação em IPTables:**
```bash
# Proteção contra pacotes malformados
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
```

**Justificativa:** Estas regras protegem contra:
- Ataques SYN flood
- Pacotes TCP malformados
- Tipos de escaneamento de portas
- Pacotes com combinações de flags inválidas ou suspeitas

**Eficácia:** Esta configuração bloqueia muitos ataques DDoS volumétricos e de protocolos simples. Para ataques DDoS mais sofisticados, seria necessário implementar soluções adicionais como CDN ou serviços específicos de mitigação.

### 5. [Adaptação a Perfis de Servidor](./adapter_profiles.md)

**Implementação:**
```bash
# Exemplo para servidores web
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
fi
```

**Justificativa:** Diferentes tipos de servidores exigem conjuntos distintos de portas abertas. A configuração modular permite personalizar o firewall exatamente para os serviços necessários.

**Benefício de Segurança:** Este design implementa o princípio de "menor privilégio" adaptado ao uso específico do servidor.

### 6. Segurança para Bancos de Dados

**Implementação comum:**
```bash
if [ "$db_server" = "true" ]; then
    # Deliberadamente não abre portas de DB
    log "WARN" "Para segurança, portas de banco de dados não serão abertas."
    log "WARN" "Use SSH tunneling ou VPN para acessar o banco de dados remotamente."
fi
```

**Justificativa:** Bancos de dados são alvos de alto valor e não devem ser expostos diretamente à internet. O script intencionalmente não abre portas de banco de dados e recomenda métodos seguros de acesso remoto.

**Melhores Práticas:** Para bancos de dados, o acesso deve ser restrito a:
- SSH tunneling
- VPNs
- Conexões de redes privadas
- Proxies de aplicação específicos e seguros

### 7. Configuração para Docker

**Implementação unificada:**
```bash
if [ "$docker" = "true" ]; then
    # UFW / IPTables
    # Permite comunicação entre containers e rede externa
    -A POSTROUTING ! -o docker0 -s 172.17.0.0/16 -j MASQUERADE
    
    # Permite comunicação entre host e containers
    -A FORWARD -i docker0 -o eth0 -j ACCEPT
    -A FORWARD -i eth0 -o docker0 -j ACCEPT
    
    # FirewallD
    # Cria uma zona específica para Docker
    firewall-cmd --permanent --new-zone=docker
    firewall-cmd --permanent --zone=docker --add-interface=docker0
    firewall-cmd --permanent --zone=docker --add-masquerade
}
```

**Justificativa:** Docker requer configurações especiais de NAT e encaminhamento para permitir que containers se comuniquem com a rede externa enquanto mantém a segurança.

**Consideração Importante:** A configuração do Docker é implementada de maneira que não exponha acidentalmente os containers diretamente à internet, a menos que seja explicitamente configurado para isso.

### 8. Limitação de Conexões Simultâneas

**Implementação:**
```bash
# FirewallD e IPTables
iptables -A INPUT -p tcp --syn --dport "$ssh_port" -m connlimit --connlimit-above 10 -j REJECT

# Implementado via outras regras em UFW
```

**Justificativa:** Limitar o número de conexões simultâneas a 10 por IP de origem ajuda a prevenir ataques de força bruta distribuídos e preserva recursos do servidor.

**Benefício Adicional:** Esta configuração também protege contra aplicações cliente mal configuradas que podem abrir muitas conexões simultaneamente.

## Considerações sobre Compatibilidade e Adaptabilidade

### Detecção Automática da Ferramenta de Firewall

```bash
# Detecta qual firewall usar
if command -v ufw &> /dev/null; then
    setup_ufw "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
elif command -v firewall-cmd &> /dev/null; then
    setup_firewalld "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
elif command -v iptables &> /dev/null; then
    setup_iptables "$ssh_port" "$web_server" "$db_server" "$mail_server" "$docker"
else
    # Tenta instalar UFW ou FirewallD...
fi
```

**Justificativa:** Esta abordagem permite que o script funcione automaticamente em diferentes distribuições Linux sem configuração manual:
- UFW: Principalmente em Ubuntu/Debian
- FirewallD: CentOS/RHEL/AlmaLinux
- IPTables: Como fallback universal

**Benefício:** Garante o funcionamento em praticamente qualquer sistema Linux moderno, seguindo o princípio de "configurar uma vez, executar em qualquer lugar".

### Persistência de Configurações

O script implementa métodos específicos para cada sistema para garantir que as regras de firewall persistam após reinicializações:

```bash
# UFW (automático)
echo "y" | ufw enable

# FirewallD (automático)
firewall-cmd --reload

# IPTables (requer configuração adicional)
if command -v iptables-save &> /dev/null; then
    # Salva em locais específicos de cada distribuição
    if [ -d "/etc/iptables" ]; then
        iptables-save > /etc/iptables/rules.v4
    elif [ -d "/etc/sysconfig" ]; then
        iptables-save > /etc/sysconfig/iptables
    else
        # Cria serviço systemd para restaurar regras na inicialização
        # ...
    fi
fi
```

**Justificativa:** Garantir que as regras persistam após reinicializações é crucial para a segurança contínua do sistema.

## Referências

1. **Política de Negação por Padrão**:
   - NIST SP 800-41 Rev 1: "Guidelines on Firewalls and Firewall Policy" - https://csrc.nist.gov/publications/detail/sp/800-41/rev-1/final
   - CIS Benchmarks for Linux - https://www.cisecurity.org/benchmark/distribution_independent_linux

2. **Proteção contra Força Bruta**:
   - OWASP Automated Threats to Web Applications - https://owasp.org/www-project-automated-threats-to-web-applications/
   - SANS Institute: "Hardening Linux Servers" - https://www.sans.org/reading-room/whitepapers/linux/

3. **Mitigação DDoS**:
   - US-CERT: "Understanding Denial-of-Service Attacks" - https://www.cisa.gov/uscert/ncas/tips/ST04-015
   - Cloudflare: "DDoS Protection" - https://www.cloudflare.com/learning/ddos/what-is-a-ddos-attack/

4. **Segurança de Contêineres Docker**:
   - Docker Security Documentation - https://docs.docker.com/engine/security/
   - CIS Docker Benchmark - https://www.cisecurity.org/benchmark/docker

5. **Configuração UFW**:
   - Ubuntu Security Documentation - https://ubuntu.com/server/docs/security-firewall
   - Digital Ocean: "UFW Essentials" - https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands

6. **Configuração FirewallD**:
   - Red Hat Documentation - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-using_firewalls
   - CentOS Wiki: FirewallD - https://wiki.centos.org/HowTos/Network/FirewallD

7. **Configuração IPTables**:
   - Netfilter Documentation - https://www.netfilter.org/documentation/
   - Linux Journal: "Advanced IPTables" - https://www.linuxjournal.com/content/advanced-firewall-configurations-ipchains-and-iptables

8. **Segurança de Banco de Dados**:
   - OWASP Database Security Cheat Sheet - https://cheatsheetseries.owasp.org/cheatsheets/Database_Security_Cheat_Sheet.html
   - MySQL Security Best Practices - https://dev.mysql.com/doc/refman/8.0/en/security-guidelines.html

9. **Limitação de Conexões**:
   - Linux Kernel Documentation: Netfilter connlimit module - https://www.kernel.org/doc/Documentation/networking/netfilter-extensions.txt
   - SANS Institute: "TCP/IP and tcpdump" - https://www.sans.org/reading-room/whitepapers/protocols/
