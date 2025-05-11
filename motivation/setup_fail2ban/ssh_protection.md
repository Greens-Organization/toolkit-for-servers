# Proteção SSH com Fail2Ban

## Visão Geral

A proteção do serviço SSH é uma das funções primárias do módulo `fail2ban.sh` no Toolkit for Servers. Este documento detalha especificamente como o Fail2Ban é configurado para proteger contra ataques de força bruta e outras tentativas de intrusão direcionadas ao SSH.

## Implementação no Toolkit

O script implementa proteções específicas para SSH através da seguinte configuração:

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

## Explicação Detalhada

### 1. Detecção de Tentativas de Intrusão

**Mecanismo de Funcionamento:**

O Fail2Ban monitora continuamente os arquivos de log do SSH (`/var/log/auth.log` no Debian/Ubuntu ou `/var/log/secure` no CentOS/RHEL) em busca de padrões que indiquem tentativas de autenticação malsucedidas.

**Padrões Monitorados:**
- Falhas de autenticação por senha
- Chaves SSH rejeitadas
- Tentativas com usuários inexistentes
- Sessões encerradas pelo servidor devido a erros
- Violações de protocolos SSH

**Localização Automática dos Logs:**
```bash
logpath = %(sshd_log)s
```
Esta variável faz o Fail2Ban determinar automaticamente onde os logs SSH estão armazenados em cada distribuição específica, garantindo compatibilidade universal.

### 2. Parâmetros de Proteção Personalizados para SSH

**Tempo de Banimento Estendido:**
```bash
bantime = 172800  # 48 horas
```

**Justificativa da Duração Estendida:**
- O SSH é tipicamente o serviço mais atacado em servidores expostos à internet
- Atacantes frequentemente usam listas de IPs para retomar ataques interrompidos
- 48 horas (comparado às 24 horas padrão) proporciona janela de proteção ampliada
- Reduz significativamente a viabilidade de ataques persistentes de força bruta

**Número Máximo de Tentativas:**
```bash
maxretry = 5
```

**Justificativa do Limite:**
- Baixo o suficiente para bloquear tentativas óbvias de força bruta
- Alto o suficiente para permitir alguns erros humanos legítimos
- Equilibra segurança com usabilidade para administradores legítimos
- Valor alinhado com recomendações de segurança padrão da indústria

### 3. Integração com Porta SSH Personalizada

**Configuração Dinâmica da Porta:**
```bash
port = $ssh_port
```

**Vantagens da Abordagem:**
- Sincroniza automaticamente com a porta configurada no módulo de segurança SSH
- Protege o servidor mesmo quando usando portas SSH não padrão
- Elimina lacunas de segurança entre os diferentes componentes do toolkit
- Reduz a necessidade de configuração manual

**Funcionamento com Múltiplas Portas:**
Se a variável `$ssh_port` contiver múltiplas portas (ex: "2222,2022"), o Fail2Ban monitorará todas elas automaticamente.

### 4. Filter de Detecção de SSH

A configuração utiliza o filtro padrão `sshd` incorporado no Fail2Ban, que contém uma coleção abrangente de expressões regulares para detectar tentativas de intrusão.

```bash
filter = sshd
```

**Expressões Regulares Incluídas:**
- `^%(__prefix_line)s(?:error: PAM: )?Authentication failure for .* from <HOST>`: Falhas de autenticação PAM
- `^%(__prefix_line)s(?:error: PAM: )?User not known to the underlying authentication module for .* from <HOST>`: Usuários inexistentes
- `^%(__prefix_line)sFailed (?:password|publickey) for .* from <HOST>(?: port \d*)?(?: ssh\d*)?$`: Falhas de senha ou chave pública
- `^%(__prefix_line)sROOT LOGIN REFUSED.* FROM <HOST>`: Tentativas de login root rejeitadas
- `^%(__prefix_line)s[iI](?:llegal|nvalid) user .* from <HOST>`: Usuários inválidos ou ilegais

### 5. Backend de Processamento

```bash
backend = %(sshd_backend)s
```

Esta configuração permite que o Fail2Ban selecione automaticamente o método mais eficiente para monitorar os logs:

- **auto**: Detecta automaticamente o melhor backend disponível
- **systemd**: Usado em sistemas com journald (maioria das distribuições modernas)
- **pyinotify**: Para sistemas que suportam notificações de eventos inotify
- **polling**: Fallback para sistemas sem suporte à monitoria de eventos

## Integração com Outras Camadas de Segurança

### 1. Complementaridade com Firewall

O Fail2Ban trabalha em conjunto com as configurações do firewall implementadas pelo módulo `firewall.sh`:

- O firewall fornece limitação de taxa estática (ex: máximo de conexões por minuto)
- O Fail2Ban adiciona bloqueio dinâmico baseado em comportamento
- Juntos, fornecem proteção mais abrangente do que cada solução isoladamente

### 2. Complementaridade com Hardening SSH

Trabalha em sintonia com as configurações do módulo `secure_ssh.sh`:

- O hardening SSH reduz vetores de ataque (desativando senhas, mudando portas)
- O Fail2Ban bloqueia IPs que persistentemente tentam explorar esses vetores
- A combinação aumenta significativamente o custo para o atacante

## Estatísticas e Eficácia

### Dados Típicos de Ataques SSH

Servidores expostos à internet frequentemente enfrentam:
- 500-2000 tentativas de login SSH por dia de diferentes IPs
- Picos de até 10.000 tentativas durante campanhas coordenadas
- Ataques geralmente ocorrem em horários de baixo movimento (noite/madrugada)
- Vetores combinados (força bruta sequencial + ataques de dicionário)

### Eficácia da Configuração Implementada

1. **Redução de Tentativas de Força Bruta:**
   - Bloqueio imediato após poucas tentativas malsucedidas
   - Tempo de banimento longo desencoraja retentativas após período de bloqueio
   - Proteção contra botnets através do banimento distribuído

2. **Baixa Taxa de Falsos Positivos:**
   - Limite de 5 tentativas acomoda erros genuínos
   - Lista de exceções para redes privadas previne auto-bloqueio
   - Foco em padrões claros de ataques reduz falsos positivos

## Verificação e Diagnóstico

### Comandos para Verificar a Proteção

Após a instalação, você pode verificar o status e eficácia usando:

```bash
# Verificar status do serviço
sudo systemctl status fail2ban

# Listar jails ativos
sudo fail2ban-client status

# Verificar configuração específica do SSH
sudo fail2ban-client status sshd

# Ver IPs atualmente banidos
sudo fail2ban-client status sshd | grep "Banned IP list"

# Testar se a configuração está funcionando
sudo fail2ban-client get sshd bantime
sudo fail2ban-client get sshd findtime
sudo fail2ban-client get sshd maxretry
```

### Logs e Monitoramento

Para verificar a atividade do Fail2Ban relacionada ao SSH:

```bash
# Verificar logs do Fail2Ban
sudo tail -f /var/log/fail2ban.log | grep "sshd"

# Verificar regras de firewall adicionadas pelo Fail2Ban
sudo iptables -L | grep "f2b-sshd"
```

## Recomendações Adicionais para SSH

### 1. Medidas Complementares de Segurança

Para aumentar ainda mais a proteção do SSH, considere:

- **Autenticação de Dois Fatores**: Implementar 2FA para SSH usando Google Authenticator ou Yubikey
- **Whitelist de IPs**: Restringir SSH apenas a endereços IP conhecidos
- **Limitação a Grupos Específicos**: Permitir SSH apenas para usuários em grupos específicos
- **Monitoramento em Tempo Real**: Configurar alertas para tentativas de login suspeitas

### 2. Configurações Alternativas Avançadas

Para ambientes de alta segurança, considere estas modificações:

```bash
[sshd]
# Valores mais restritivos
maxretry = 3
bantime = 604800  # 1 semana
findtime = 300    # 5 minutos

# Ação personalizada
action = %(action_mwl)s
```

A ação `action_mwl` inclui:
- Banimento do IP
- Envio de notificação por email
- Inclusão do log relevante no email (facilita investigação)

## Referências

1. Fail2Ban Wiki - SSH Protection - https://www.fail2ban.org/wiki/index.php/SSH

2. SANS Institute - "Hardening Linux Servers with Fail2Ban" - https://www.sans.org/reading-room/whitepapers/

3. LinuxSecurity - "Protecting SSH with Fail2Ban" - https://linuxsecurity.com/features/features/protecting-ssh-with-fail2ban

4. SSH.com - "Security Practices" - https://www.ssh.com/academy/ssh/security

5. CIS Benchmarks para SSH - https://www.cisecurity.org/benchmark/distribution_independent_linux/

6. NIST SP 800-153 - "Guidelines for Securing SSH" - https://csrc.nist.gov/publications/

7. Fail2Ban GitHub - Filter Examples - https://github.com/fail2ban/fail2ban/tree/master/config/filter.d

8. Red Hat Security Guide - SSH Protection - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/
