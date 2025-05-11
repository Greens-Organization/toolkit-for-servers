# Desativação de Recursos Desnecessários no SSH

## Visão Geral

A desativação de recursos desnecessários no SSH segue o princípio de segurança de menor privilégio, reduzindo a superfície de ataque do servidor. O módulo `secure_ssh.sh` do Toolkit for Servers implementa uma configuração defensiva que desativa funcionalidades raramente necessárias em ambientes de servidor, mas que podem ser exploradas para movimento lateral, exfiltração de dados ou escalação de privilégios.

## Implementação no Toolkit

O script implementa as seguintes configurações de desativação no arquivo `/etc/ssh/sshd_config.d/00-security.conf`:

```bash
# Configurações adicionais de segurança
X11Forwarding no
TCPKeepAlive yes
Compression no
AllowAgentForwarding no
AllowTcpForwarding no
PrintMotd no
AcceptEnv LANG LC_*
```

Outras configurações de segurança relacionadas:

```bash
# Configuração de autenticação
PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
```

## Justificativa de Segurança

### Encaminhamento X11 (X11Forwarding)

1. **Configuração**: `X11Forwarding no`

2. **Riscos de Segurança**:
   - Permite captura de teclado e tela remotamente (keylogging)
   - Possibilita exfiltração de dados via interface gráfica
   - Expõe o servidor X local a vulnerabilidades remotas
   - Aumenta a superfície de ataque significativamente

3. **Impacto Operacional**:
   - Impede uso de aplicativos gráficos via SSH
   - Alternativas seguras: VNC/RDP sobre túnel SSH ou VPN

### Encaminhamento de Agente SSH (AllowAgentForwarding)

1. **Configuração**: `AllowAgentForwarding no`

2. **Riscos de Segurança**:
   - Permite que um servidor comprometido use chaves SSH do cliente
   - Facilita movimento lateral sem necessidade de novas credenciais
   - Possibilita ataques de "salto" entre servidores
   - Dificulta auditoria de quem acessou qual servidor

3. **Alternativas Seguras**:
   - ProxyJump (SSH -J) para conexões multi-hop
   - Chaves SSH específicas por servidor
   - Bastion hosts configurados adequadamente

### Encaminhamento TCP (AllowTcpForwarding)

1. **Configuração**: `AllowTcpForwarding no`

2. **Riscos de Segurança**:
   - Permite contornar firewalls e controles de rede
   - Facilita tunelamento de tráfego não autorizado
   - Possibilita acesso a serviços internos restritos
   - Dificulta detecção de comunicações maliciosas

3. **Impacto na Segurança de Rede**:
   - Compromete segmentação de rede
   - Permite bypass de IDS/IPS
   - Cria canais de comunicação ocultos
   - Facilita exfiltração de dados

### Compressão (Compression)

1. **Configuração**: `Compression no`

2. **Riscos de Segurança**:
   - Vulnerável a ataques de oracle de compressão (CRIME/BREACH)
   - Pode ser explorada para extrair informações de tráfego criptografado
   - Aumenta a superfície de ataque do servidor

3. **Considerações de Desempenho**:
   - Impacto mínimo em redes modernas de alta velocidade
   - Benefício de compressão raramente justifica o risco em servidores

### Autenticação por Senha (PasswordAuthentication)

1. **Configuração**: `PasswordAuthentication no`

2. **Riscos de Segurança**:
   - Vulnerável a ataques de força bruta e dicionário
   - Frequentemente alvo de tentativas automatizadas de invasão
   - Senhas podem ser comprometidas por phishing ou vazamentos

3. **Benefícios da Desativação**:
   - Elimina completamente ataques de força bruta de senha
   - Simplifica auditoria de acesso (apenas chaves autorizadas)
   - Aumenta significativamente a segurança geral do servidor

### Outras Configurações Defensivas

1. **PermitEmptyPasswords no**:
   - Previne login com senhas vazias, mesmo que permitido pelo sistema
   - Camada adicional de proteção contra contas mal configuradas

2. **ChallengeResponseAuthentication no**:
   - Desativa métodos de autenticação menos seguros
   - Reforça o uso exclusivo de chaves SSH

3. **PrintMotd no**:
   - Reduz informações expostas após login
   - Minimiza vazamento de informações sobre o sistema

4. **Subsystem sftp internal-sftp**:
   - Usa implementação interna de SFTP mais segura
   - Evita execução de processos externos desnecessários

## Registro e Auditoria

O script implementa registro detalhado para facilitar a detecção de tentativas de intrusão:

```bash
# Registro detalhado
LogLevel VERBOSE
```

Esta configuração:
- Registra tentativas de login com detalhes completos
- Facilita a detecção de padrões de ataque
- Melhora a capacidade de resposta a incidentes
- Fornece trilhas de auditoria mais completas

## Verificação e Auditoria

### Monitoramento Contínuo

Implementação de monitoramento para detectar tentativas de bypass:

1. Alertas para tentativas de usar recursos desativados
2. Verificação periódica de configuração via scripts automatizados
3. Integração com sistemas SIEM para correlação de eventos

## Considerações para Ambientes Específicos

### Servidores de Desenvolvimento

```bash
# Configuração para ambientes de desenvolvimento
X11Forwarding yes
AllowAgentForwarding yes
AllowTcpForwarding yes
```

### Bastion Hosts / Jump Servers

```bash
# Configuração para bastion hosts
AllowTcpForwarding yes
GatewayPorts clientspecified
MaxSessions 20
```

### Servidores de Produção Críticos

```bash
# Configuração para servidores críticos
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
GatewayPorts no
PermitUserEnvironment no
MaxSessions 5
```

## Referências

1. OpenSSH Security Best Practices: https://www.ssh.com/academy/ssh/security
2. NIST SP 800-123 - Guide to General Server Security
3. CIS Benchmarks para OpenSSH
4. ANSSI - Recommandations de sécurité relatives à OpenSSH
5. NSA/CISA Hardening Guide for OpenSSH
6. OWASP - SSH Security Cheat Sheet
7. Mozilla SSH Guidelines: https://infosec.mozilla.org/guidelines/openssh
8. SSH.com - SSH Tunneling Explained
