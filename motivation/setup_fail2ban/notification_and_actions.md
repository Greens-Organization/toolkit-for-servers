# Ações e Notificações do Fail2Ban

## Visão Geral

O módulo `fail2ban.sh` do Toolkit for Servers implementa um sistema robusto de ações e notificações quando atividades suspeitas são detectadas. Este documento detalha as ações de banimento, mecanismos de notificação e suas justificativas técnicas.

## Implementação no Toolkit

A configuração de ações e notificações é implementada através das seguintes linhas no arquivo de configuração principal:

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

## Detalhamento das Ações

### 1. Mecanismos de Banimento

**Ações de Firewall Configuradas:**

```bash
banaction = iptables-multiport
banaction_allports = iptables-allports
```

**Explicação:**

1. **iptables-multiport**:
   - Usado quando o banimento se aplica a portas específicas
   - Cria regras que bloqueiam apenas o acesso às portas específicas do serviço
   - Mais eficiente em termos de recursos para serviços específicos (como SSH)
   - Exemplo de regra gerada: 
     ```
     iptables -A f2b-sshd -s 192.168.1.100/32 -p tcp -m multiport --dports 22 -j REJECT --reject-with icmp-port-unreachable
     ```

2. **iptables-allports**:
   - Usado quando o banimento se aplica a todas as portas do servidor
   - Bloqueia completamente o acesso do IP banido ao servidor
   - Utilizado para serviços que não têm portas específicas ou para ameaças sérias
   - Exemplo de regra gerada:
     ```
     iptables -A f2b-recidive -s 192.168.1.100/32 -j REJECT --reject-with icmp-port-unreachable
     ```

**Vantagens da Abordagem IPTables:**

- **Integração nativa com kernel**: Opera no nível mais baixo do sistema de rede
- **Baixo overhead**: Processamento de pacotes extremamente eficiente
- **Durabilidade**: Continua funcionando mesmo com alta carga no servidor
- **Persistência**: Configurado para persistir após reinicializações

### 2. Notificações por Email

**Configuração Implementada:**

```bash
# Ação para executar quando um IP for banido
action = %(action_mw)s

# Opção para enviar emails ao administrador
destemail = root@localhost
sender = fail2ban@localhost
mta = sendmail
```

**Explicação do action_mw:**

A ação `action_mw` é uma ação predefinida do Fail2Ban que:
- **Bane** o IP infrator usando o método banaction configurado
- **Envia email** ao administrador com detalhes do incidente

**Estrutura de um Email Típico de Notificação:**

```
From: fail2ban@localhost
To: root@localhost
Subject: [Fail2Ban] sshd: banned 192.168.1.100 from server1

The IP 192.168.1.100 has been banned by Fail2Ban after 5 failed attempts against sshd.

Details:
- Jail: sshd
- IP address: 192.168.1.100
- Time of ban: 2025-05-11 20:45:17 UTC
- Ban duration: 172800 seconds

Lines containing failures from IP:
2025-05-11 20:45:10 Failed password for invalid user admin from 192.168.1.100 port 55234 ssh2
2025-05-11 20:45:12 Failed password for invalid user admin from 192.168.1.100 port 55236 ssh2
2025-05-11 20:45:14 Failed password for invalid user admin from 192.168.1.100 port 55238 ssh2
2025-05-11 20:45:15 Failed password for invalid user admin from 192.168.1.100 port 55240 ssh2
2025-05-11 20:45:17 Failed password for invalid user admin from 192.168.1.100 port 55242 ssh2

Regards,
Fail2Ban
```

**Parâmetros de Notificação:**

1. **destemail = root@localhost**:
   - Email do destinatário das notificações
   - Em sistemas Unix/Linux, emails para root são frequentemente encaminhados para o administrador do sistema
   - Pode ser modificado para um endereço direto de email externo

2. **sender = fail2ban@localhost**:
   - Define o remetente das notificações
   - Facilita a configuração de filtros de email para administradores
   - Identifica claramente a origem dos alertas

3. **mta = sendmail**:
   - Utiliza o agente de transferência de mensagens (MTA) padrão do sistema
   - Compatível com a maioria das distribuições Linux
   - Alternativas comuns incluem postfix, exim ou smtp

### 3. Tipos de Ações Disponíveis

O Fail2Ban suporta diferentes níveis de ações, e o script implementa uma abordagem equilibrada:

| Ação | Descrição | Implementada |
|------|-----------|--------------|
| `action_` | Apenas bane o IP | Não |
| `action_mw` | Bane e envia email de aviso (warn) | **Sim** |
| `action_mwl` | Bane, envia email e inclui trecho do log | Não |
| `action_cf_mwl` | Bane via CloudFlare API + email com logs | Não |

**Justificativa para a Escolha de action_mw:**

1. **Equilíbrio entre informação e volume**:
   - Fornece detalhes suficientes para investigação
   - Não sobrecarrega o administrador com logs extensos
   - Reduz o tamanho dos emails em sistemas com muitos ataques

2. **Desempenho**:
   - Processamento mais rápido que `action_mwl`
   - Menor overhead de I/O para leitura e processamento de logs
   - Menor carga no servidor de email

3. **Flexibilidade**:
   - Fácil de atualizar para `action_mwl` em ambientes que requerem mais detalhes
   - Compatível com a maioria dos MTAs sem configuração adicional

## Customização das Ações

### Ações Alternativas Não Implementadas

O Fail2Ban oferece várias ações alternativas que não estão habilitadas por padrão no script, mas podem ser configuradas manualmente:

1. **Ações para serviços externos**:
   ```bash
   # Exemplo: integração com CloudFlare
   banaction = cloudflare
   cfcredentials = /etc/fail2ban/cloudflare.conf
   ```

2. **Ações com comandos personalizados**:
   ```bash
   # Exemplo: execução de scripts adicionais
   actionban = iptables -I fail2ban-<name> 1 -s <ip> -j DROP && /usr/local/bin/notify_security_team.sh <ip>
   ```

3. **Ações com banimento incremental**:
   Fail2Ban pode ser configurado para aumentar o tempo de banimento para IPs reincidentes, embora essa funcionalidade não esteja implementada no script por padrão.

### Integração com Sistemas de Monitoramento

As notificações por email podem ser facilmente integradas com sistemas de monitoramento existentes:

1. **Processamento automatizado**:
   - Formato previsível facilita parsing por scripts
   - Pode acionar alertas em plataformas como Nagios, Zabbix ou Prometheus
   - Integração com sistemas de tickets como OTRS ou RT

2. **Exemplos de integração**:
   ```bash
   # Redirecionar emails para sistema de tickets
   destemail = security-tickets@example.com
   
   # Usar script personalizado como MTA
   mta = /usr/local/bin/mail-to-slack.sh
   ```

## Considerações Operacionais

### 1. Volume de Notificações

Em servidores expostos à internet, especialmente com serviço SSH público, o volume de notificações pode se tornar problemático:

- Servidores sob ataque podem gerar dezenas ou centenas de notificações por dia
- Isto pode levar à "fadiga de alerta" onde notificações importantes são ignoradas

**Soluções implementáveis:**

1. **Agregação de alertas**:
   - Modificar a configuração para agregação temporal (ex: resumo diário)
   - Usar ferramentas externas como logwatch para análise consolidada

2. **Filtragem inteligente**:
   - Configurar filtros de email para separar notificações por severidade
   - Implementar regras para destacar padrões incomuns de ataque

### 2. Persistência dos Banimentos

A configuração padrão não mantém banimentos após reinicialização do serviço ou servidor:

```bash
# Persistência não implementada no script padrão
dbpurgeage = 86400    # 24 horas (padrão)
dbfile = /var/lib/fail2ban/fail2ban.sqlite3
```

**Recomendações para persistência:**

1. **Habilitação do banco de dados**:
   ```bash
   [DEFAULT]
   dbfile = /var/lib/fail2ban/fail2ban.sqlite3
   dbpurgeage = 604800   # 7 dias
   ```

2. **Configuração de recidiva**:
   ```bash
   [recidive]
   enabled = true
   filter = recidive
   logpath = /var/log/fail2ban.log
   action = iptables-allports[name=recidive]
           sendmail-whois[name=recidive, dest=root@localhost]
   bantime = 604800  # 1 semana
   findtime = 86400  # 1 dia
   maxretry = 5
   ```
   
   O jail "recidive" monitora o próprio log do Fail2Ban e bane IPs que foram banidos múltiplas vezes, criando um sistema de "lista negra" dinâmica.

## Referências

1. Fail2Ban Wiki - "Actions" - https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Actions

2. Digital Ocean - "How To Configure Fail2Ban Notifications" - https://www.digitalocean.com/community/tutorials/how-to-configure-fail2ban-notifications

3. LinuxServer.io - "Fail2Ban Email Notifications" - https://docs.linuxserver.io/general/fail2ban

4. Fail2Ban GitHub - Action Configuration - https://github.com/fail2ban/fail2ban/tree/master/config/action.d

5. SANS Internet Storm Center - "Advanced Usage of Fail2Ban" - https://isc.sans.edu/diary/

6. Fail2Ban Documentation - "Persistent Bans Database" - https://www.fail2ban.org/wiki/index.php/Commands#Database

7. Red Hat - "Configuring Actions in Fail2Ban" - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-configuring_the_fail2ban_service

8. Server Fault - "Fail2Ban Best Practices" - https://serverfault.com/questions/tagged/fail2ban
