# Configurações de Timeout e Limitação de Conexão SSH

## Visão Geral

Configurações apropriadas de timeout e limitação de conexões são elementos cruciais da segurança SSH. O Toolkit for Servers implementa várias medidas para mitigar ataques de força bruta e garantir que recursos do servidor não sejam consumidos por conexões inativas ou maliciosas.

## Implementação no Toolkit

```bash
# Configurações de tempo limite e limitação de conexão no sshd_config
LoginGraceTime 30s
MaxStartups 10:30:100
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Justificativa das Configurações

### 1. LoginGraceTime (30s)

**Propósito**: Define o tempo máximo permitido para um cliente se autenticar após estabelecer uma conexão.

**Benefícios de Segurança**:
- Reduz a janela de oportunidade para ataques de força bruta
- Libera recursos rapidamente de tentativas de conexão abandonadas
- Minimiza tempo em que processos de autenticação incompletos consomem recursos

**Consideração**: O padrão original (2 minutos) é excessivamente longo para servidores modernos com conexões estáveis.

### 2. MaxStartups (10:30:100)

**Formato**: `início:taxa:máximo`
- **início**: Número de conexões não autenticadas permitidas sem probabilidade de descarte
- **taxa**: Probabilidade percentual de recusar novas conexões após atingir "início"
- **máximo**: Limite absoluto de conexões não autenticadas

**Explicação**: Após 10 conexões não autenticadas simultâneas, novas conexões começam a ser recusadas com probabilidade crescente de 30%. Quando o número de conexões atinge 100, todas as novas tentativas são recusadas.

**Benefícios de Segurança**:
- Proteção contra ataques DoS por saturação de conexões
- Mitigação de ataques de força bruta distribuídos
- Preservação de recursos do servidor durante picos de tráfego malicioso

### 3. MaxAuthTries (3)

**Propósito**: Número máximo de tentativas de autenticação permitidas por sessão.

**Benefícios de Segurança**:
- Dificulta ataques de força bruta limitando as tentativas por conexão
- Complementa soluções como Fail2ban, adicionando uma camada de proteção no próprio serviço SSH
- Equilibra usabilidade (permitindo alguns erros humanos) e segurança

**Impacto Prático**: Se um cliente tentar mais de 3 métodos ou credenciais diferentes, a conexão será fechada e ele precisará reconectar.

### 4. ClientAliveInterval (300) e ClientAliveCountMax (2)

**Funcionamento Conjunto**:
- **ClientAliveInterval**: O servidor envia um pacote de verificação de status a cada 300 segundos (5 minutos)
- **ClientAliveCountMax**: Se o cliente não responder a 2 verificações consecutivas, a conexão é encerrada

**Tempo Total até Desconexão**: 300s × 2 = 600s (10 minutos de inatividade)

**Benefícios de Segurança**:
- Liberação automática de recursos de sessões abandonadas ou mortas
- Redução do risco de sessões não supervisionadas serem exploradas
- Fechamento limpo de conexões interrompidas por problemas de rede
- Menor exposição para sessões SSH esquecidas abertas

**Vantagem sobre TCPKeepAlive**: Os pacotes ClientAlive são enviados através do canal SSH criptografado, diferentemente do TCPKeepAlive que opera no nível TCP.

## Equilibrando Segurança e Usabilidade

As configurações implementadas pelo Toolkit buscam um equilíbrio entre:

1. **Mitigação de Riscos**: Proteção contra ataques conhecidos
2. **Usabilidade**: Evitar interrupções frequentes para usuários legítimos
3. **Eficiência de Recursos**: Liberação oportuna de conexões inativas

## Considerações para Ajustes

Em certos ambientes, estas configurações podem precisar de ajustes:

### Ambientes com Alta Latência

Se seus servidores são acessados por conexões de alta latência ou instáveis:
- Aumente `LoginGraceTime` para 60s
- Ajuste `ClientAliveInterval` para 600 e `ClientAliveCountMax` para 3

### Servidores de Alta Segurança

Para ambientes com requisitos de segurança extraordinários:
- Reduza `LoginGraceTime` para 20s
- Diminua `MaxAuthTries` para 2
- Reduza `ClientAliveInterval` para 180 (3 minutos)
- Mantenha `ClientAliveCountMax` em 2

### Servidores com Muitos Usuários Simultâneos

Para servidores que legitimamente recebem muitas conexões:
- Aumente `MaxStartups` para 20:30:200
- Mantenha os outros valores

## Integração com Outras Medidas de Segurança

Estas configurações funcionam melhor quando combinadas com:

1. **Fail2ban**: Banimento temporário de IPs após múltiplas tentativas falhas
2. **Firewall (UFW/FirewallD)**: Limitação de acesso à porta SSH
3. **Rate Limiting**: Limitação de novas conexões por minuto no nível de firewall
4. **Monitoramento de Logs**: Alerta sobre padrões suspeitos de tentativas de login

## Verificação das Configurações

Para verificar as configurações atuais em um sistema:

```bash
sshd -T | grep -E 'logingracetime|maxstartups|maxauthtries|clientalive'
```

## Referências

1. OpenSSH Manual: sshd_config(5)
2. NIST SP 800-123: Guide to General Server Security
3. CIS Benchmarks para SSH
4. SSH.com: "Bulletproof SSH Protection"
5. Mozilla SSH Guidelines: https://infosec.mozilla.org/guidelines/openssh
6. AWS Security Best Practices for EC2
7. The Practical Linux Hardening Guide: https://github.com/trimstray/the-practical-linux-hardening-guide
