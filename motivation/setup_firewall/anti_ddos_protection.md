# Proteção Anti-DDoS em Firewalls Linux

## Visão Geral

O módulo `firewall.sh` do Toolkit for Servers implementa diversas proteções contra ataques de Negação de Serviço Distribuído (DDoS) em todos os sistemas de firewall suportados. Este documento explica em detalhes as proteções anti-DDoS implementadas, sua eficácia e limitações.

## Implementação no Toolkit

### UFW (Ubuntu/Debian)

```bash
# Trecho Anti-DDoS para UFW
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
```

### FirewallD (CentOS/RHEL/AlmaLinux)

```bash
# Proteção básica anti-DDoS
# Limita o número de conexões simultâneas
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --syn --dport "$ssh_port" -m connlimit --connlimit-above 10 -j REJECT

# Limita a taxa de novas conexões
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT

# Para servidores web - proteção adicional
if [ "$web_server" = "true" ]; then
    # Limita a taxa de novas conexões para HTTP/HTTPS
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 80 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT

    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 30 -j REJECT
fi
```

### IPTables (Fallback)

```bash
# Proteção básica anti-DDoS
# Limita o número de conexões simultâneas
iptables -A INPUT -p tcp --syn --dport "$ssh_port" -m connlimit --connlimit-above 10 -j REJECT

# Limita a taxa de novas conexões
iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport "$ssh_port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j REJECT

# Protege contra pacotes mal formados
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
```

## Detalhamento das Proteções

### 1. Filtragem de Pacotes TCP Malformados

**Técnica implementada:** Rejeição de pacotes com combinações de flags TCP inválidas ou suspeitas.

**Justificativa técnica:** Muitos ataques DDoS utilizam pacotes TCP malformados que não seguem a especificação padrão do protocolo. Estes pacotes não seriam enviados por clientes legítimos e frequentemente são usados em:

- Ataques de reconhecimento TCP (XMAS, NULL scan)
- SYN floods com flags adicionais
- Ataques que tentam consumir recursos do sistema operacional

**Exemplos de pacotes bloqueados:**
- `--tcp-flags ALL NONE` - Pacotes NULL (sem flags)
- `--tcp-flags ALL ALL` - Pacotes XMAS (todas as flags ativas)
- `--tcp-flags FIN,SYN FIN,SYN` - Combinação inválida segundo a RFC do TCP
- Várias outras combinações de flags que violam a especificação TCP

**Eficácia:** Esta proteção é altamente eficaz contra ataques por pacotes TCP malformados e tem impacto zero em tráfego legítimo.

### 2. Limitação de Taxa de Conexão

**Técnica implementada:** Limita a quantidade de novas conexões por origem em um determinado período.

```bash
# Exemplo (SSH): Máximo de 10 conexões novas em 60 segundos
-m recent --update --seconds 60 --hitcount 10 -j REJECT
```

**Justificativa técnica:** Os ataques DDoS frequentemente tentam sobrecarregar serviços abrindo um grande número de conexões simultâneas. Limitar a taxa de conexões novas de uma mesma origem:

- Protege contra ataques de inundação por um único endereço IP
- Mantém disponibilidade do serviço durante ataques moderados
- Impede que um único cliente consuma todos os recursos disponíveis

**Limites configurados:**
- SSH: 10 conexões por minuto
- HTTP/HTTPS (quando ativado): 30 conexões por minuto

**Consideração importante:** Os limites são calibrados para permitir uso normal enquanto bloqueiam padrões de tráfego anômalos.

### 3. Limitação de Conexões Simultâneas

**Técnica implementada:** Restringe o número de conexões concorrentes de uma única origem.

```bash
-m connlimit --connlimit-above 10 -j REJECT
```

**Justificativa técnica:** Complementa a limitação de taxa ao impedir que um único endereço IP mantenha muitas conexões abertas ao mesmo tempo. Esta proteção:

- Impede que atacantes ocupem todas as conexões disponíveis
- Mitiga ataques de Slow Loris (que mantêm muitas conexões abertas por longos períodos)
- Distribui equitativamente os recursos entre os clientes

**Limite configurado:** 10 conexões simultâneas por endereço IP de origem.

### 4. Validação de MSS (Maximum Segment Size)

**Técnica implementada:** Bloqueia pacotes TCP com valores MSS inválidos.

```bash
-p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
```

**Justificativa técnica:** Clientes legítimos normalmente usam valores MSS dentro de intervalos específicos. Valores fora desse intervalo frequentemente indicam:
- Ferramentas de ataque mal configuradas
- Tentativas de explorar vulnerabilidades do sistema
- Pacotes artificialmente manipulados

**Benefício:** Reduz carga no servidor ao bloquear pacotes anômalos com mínimo impacto em clientes legítimos.

## Eficácia e Limitações

### Eficácia contra Diferentes Tipos de Ataques DDoS

| Tipo de Ataque | Nível de Proteção | Notas |
|----------------|-------------------|-------|
| SYN Flood | Alto | Combinação de regras de pacotes malformados e limitação de taxa |
| HTTP Flood | Médio | Limitação de conexões por IP (ineficaz contra ataques distribuídos) |
| Slow Loris | Alto | Limitação de conexões simultâneas por IP |
| UDP Flood | Baixo | O script foca principalmente em proteções TCP |
| Amplification Attacks | Baixo | Requer configurações adicionais específicas |
| Layer 7 (Aplicação) | Baixo | Requer proteções em nível de aplicação como WAF |

### Limitações

1. **Ataques Verdadeiramente Distribuídos**: Estas configurações são mais eficazes contra ataques de poucos origens. Contra ataques de milhares de IPs únicos, as proteções no nível de firewall local têm eficácia limitada.

2. **Ataques Volumétricos**: Quando o link de rede está saturado (ataques de grande volume), proteções no firewall local não são suficientes, pois o tráfego já atingiu o servidor.

3. **Ataques de Aplicação Sofisticados**: Ataques que exploram vulnerabilidades específicas de aplicações não são impedidos por regras de firewall de rede.

## Recomendações Adicionais

Para proteção DDoS mais abrangente, recomenda-se complementar as regras de firewall com:

1. **Serviços de Mitigação DDoS em Nuvem**:
   - Cloudflare
   - AWS Shield
   - Google Cloud Armor
   - Imperva/Incapsula

2. **Configurações Adicionais de Kernel**:
   ```bash
   # Exemplo: parâmetros sysctl recomendados
   net.ipv4.tcp_syncookies = 1
   net.ipv4.tcp_max_syn_backlog = 2048
   net.ipv4.tcp_synack_retries = 2
   net.ipv4.tcp_syn_retries = 5
   ```

3. **Software de Balanceamento/Proxy**:
   - Nginx com limitação de taxa
   - HAProxy com listas ACL dinâmicas
   - ModSecurity WAF para proteção de aplicações

## Referências

1. Cloudflare: "DDoS Attack Types & Mitigation Methods" - https://www.cloudflare.com/learning/ddos/ddos-attack-tools/

2. Red Hat: "Configure FirewallD to protect from DoS attacks" - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-using_firewalls

3. SANS Internet Storm Center: "DDoS Defense" - https://isc.sans.edu/forums/diary/DDoS+Defense/

4. NIST SP 800-44 Ver. 2: "Guidelines on Securing Public Web Servers" - https://csrc.nist.gov/publications/detail/sp/800-44/version-2/final

5. US-CERT: "Understanding Denial-of-Service Attacks" - https://www.cisa.gov/uscert/ncas/tips/ST04-015

6. Linux Kernel Documentation: Netfilter/Iptables - https://www.kernel.org/doc/Documentation/networking/netfilter.txt

7. OWASP: "Denial of Service Cheat Sheet" - https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html

8. Digital Ocean: "iptables Essentials: Common Firewall Rules and Commands" - https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
