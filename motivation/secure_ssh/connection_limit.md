# Limitações de Conexão e Tempo para SSH

## Visão Geral

As configurações de limitação de conexão e tempo são essenciais para mitigar ataques de força bruta, prevenir negação de serviço (DoS) e gerenciar recursos do servidor. O módulo `secure_ssh.sh` do Toolkit for Servers implementa controles rigorosos que reduzem a janela de oportunidade para atacantes e minimizam o impacto de sessões abandonadas.

## Implementação no Toolkit

O script implementa as seguintes configurações de limitação no arquivo `/etc/ssh/sshd_config.d/00-security.conf`:

```bash
# Configurações de tempo limite
LoginGraceTime 30s
MaxStartups 10:30:100
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Justificativa de Segurança

### Limitações de Tempo de Login (LoginGraceTime)

1. **Configuração**: `LoginGraceTime 30s`

2. **Propósito**:
   - Limita o tempo que um cliente tem para autenticar após estabelecer conexão
   - Reduz a janela de oportunidade para ataques de força bruta
   - Libera recursos do servidor rapidamente para conexões legítimas

3. **Impacto de Segurança**:
   - Reduz o tempo disponível para ferramentas automatizadas testarem credenciais
   - Minimiza o número de sessões pendentes que consomem recursos
   - Dificulta ataques de temporização que exploram diferenças no tempo de resposta

4. **Valor Padrão vs. Configurado**:
   - Padrão: 120 segundos (2 minutos)
   - Configurado: 30 segundos (redução de 75%)
   - Justificativa: 30 segundos é suficiente para autenticação legítima, mesmo em conexões lentas

### Proteção contra Ataques de Conexão (MaxStartups)

1. **Configuração**: `MaxStartups 10:30:100`

2. **Formato e Significado**:
   - Formato: "início:taxa:máximo"
   - Início (10): Número de conexões não autenticadas permitidas sem restrição
   - Taxa (30): Probabilidade de rejeição (30%) para novas conexões após atingir o "início"
   - Máximo (100): Limite absoluto de conexões não autenticadas

3. **Mecanismo de Proteção**:
   - Implementa rejeição probabilística para mitigar ataques DoS
   - Prioriza conexões existentes sobre novas durante sobrecarga
   - Mantém capacidade de serviço para usuários legítimos

4. **Análise de Eficácia**:
   - Efetivo contra ataques de inundação de conexão (connection flooding)
   - Reduz carga no servidor durante picos de tentativas de login
   - Complementa proteções de firewall

### Limitação de Tentativas de Autenticação (MaxAuthTries)

1. **Configuração**: `MaxAuthTries 3`

2. **Propósito**:
   - Limita o número de tentativas de autenticação por sessão
   - Força o atacante a estabelecer novas conexões após falhas
   - Aumenta a visibilidade de tentativas de força bruta nos logs

3. **Valor Padrão vs. Configurado**:
   - Padrão: 6 tentativas
   - Configurado: 3 tentativas (redução de 50%)
   - Justificativa: Usuários legítimos raramente erram a senha mais de 2 vezes

### Gerenciamento de Sessões Inativas (ClientAlive)

1. **Configurações**:
   - `ClientAliveInterval 300`
   - `ClientAliveCountMax 2`

2. **Funcionamento**:
   - Intervalo (300s): O servidor envia um pacote de verificação a cada 5 minutos
   - Contagem (2): Após 2 verificações sem resposta (10 minutos total), a sessão é encerrada

3. **Benefícios de Segurança**:
   - Reduz risco de sessões abandonadas serem exploradas
   - Libera recursos do sistema de sessões inativas
   - Diminui janela de oportunidade para ataques de sequestro de sessão

4. **Considerações Operacionais**:
   - Equilibra segurança com usabilidade para administradores
   - Permite sessões de trabalho razoáveis sem interrupção
   - Compatível com a maioria dos clientes SSH modernos

## Análise de Logs

Exemplo de análise de logs para identificar tentativas de ataque:

```bash
# Análise de tentativas de login falhas
grep "Failed password" /var/log/auth.log | \
    awk '{print $11}' | sort | uniq -c | sort -nr
```

## Referências

1. NIST SP 800-123 - Guide to General Server Security
2. CIS Benchmarks para OpenSSH
3. DISA STIG para Unix/Linux
4. OWASP - Brute Force Prevention Cheat Sheet
5. Australian Cyber Security Centre - Hardening Linux Servers
6. SSH.com - DDoS Protection Best Practices
7. Red Hat Enterprise Linux Security Guide
