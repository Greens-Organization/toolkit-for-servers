# Documentação de Segurança SSH

Este documento explica as escolhas de segurança implementadas no módulo [`secure_ssh.sh`](../../modules/secure_ssh.sh) do Toolkit for Servers.

## Visão Geral

O módulo de segurança SSH implementa práticas recomendadas para servidores, focando em:
- Autenticação segura
- Prevenção contra ataques de força bruta
- Criptografia forte
- Configuração defensiva por padrão
- Manutenção e atualização de chaves

## Principais Configurações e Justificativas

### 1. [Alteração da Porta SSH Padrão](./change_default_port.md)

**Configuração:** `Port $ssh_port` (diferente de 22)

**Justificativa:** Embora não seja uma medida de segurança por obscuridade, usar uma porta não-padrão reduz significativamente os ataques automatizados que visam a porta 22. Estudos mostram uma redução de até 80% nas tentativas de conexão maliciosas ao usar portas alternativas.

**Considerações:**
- O script verifica se a porta escolhida já está em uso por outro serviço
- Alerta sobre a necessidade de ajustar regras de firewall

### 2. [Desativação de Login como Root](./disable_root_login.md)

**Configuração:** `PermitRootLogin no`

**Justificativa:** Impede acesso direto à conta com privilégios máximos, obrigando atacantes a comprometer primeiro uma conta de usuário regular e depois escalar privilégios, aumentando a dificuldade de invasão.

**Implementação:**
- Cria um usuário não-root com privilégios sudo se necessário
- Configuração baseada em defesa por camadas (defense-in-depth)

### 3. [Autenticação por Chaves SSH](./key_vs_password_auth.md)

**Configurações:**
```
PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey
```

**Justificativa:** Autenticação por chave é virtualmente imune a ataques de força bruta, diferentemente de senhas. Eliminar completamente a autenticação por senha remove um vetor de ataque comum.

**Recursos:**
- Suporte à adição de chaves públicas existentes
- Geração de par de chaves de emergência quando necessário
- Configuração adequada de permissões para arquivos de chaves

### 4. [Algoritmos de Criptografia Modernos](./algorithms.md)

**Configurações:**
```
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
```

**Justificativa:** Utiliza apenas algoritmos considerados seguros em 2025, removendo cifras obsoletas ou vulneráveis. A configuração prioriza:
- Curve25519 para troca de chaves (superior às curvas NIST)
- ChaCha20-Poly1305 e AES-GCM para cifragem autenticada
- ETM (encrypt-then-MAC) para maior segurança

### 5. [Limitações de Conexão e Tempo](./connection_limit.md)

**Configurações:**
```
LoginGraceTime 30s
MaxStartups 10:30:100
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

**Justificativa:** 
- Reduz janela de oportunidade para ataques de força bruta
- Limita o número de conexões simultâneas não autenticadas
- Desconecta sessões inativas após aproximadamente 10 minutos
- Previne consumo de recursos por sessões abandonadas

### 6. [Desativação de Recursos Desnecessários](./disable_unnecessary_resources.md)

**Configurações:**
```
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
```

**Justificativa:** Segue o princípio de menor privilégio, desativando funcionalidades que raramente são necessárias em servidores e que podem ser exploradas para movimento lateral em uma rede.

### 7. Geração e Rotação de Chaves de Host

**Implementação:**
- Gera novas chaves ED25519 e RSA se não existirem
- Avisa sobre chaves com mais de um ano de idade
- Prioriza ED25519 sobre RSA (porém mantém RSA para compatibilidade)

**Justificativa:** Chaves de host são cruciais para prevenir ataques MITM (Man-in-the-Middle). Rotação periódica de chaves limita o impacto de uma possível exposição.

### 8. Logs Detalhados

**Configuração:** `LogLevel VERBOSE`

**Justificativa:** Facilita a detecção de tentativas de intrusão e análise forense, auxiliando na resposta a incidentes.

### 9. Backup Automático das Configurações

**Implementação:** Backup datado de todos os arquivos de configuração SSH antes de modificações

**Justificativa:** Permite reversão rápida em caso de problemas, minimizando tempo de inatividade e erros humanos durante configurações.

### 10. [Idempotência](./idempotence.md)

**Implementação:** O script pode ser executado várias vezes sem efeitos negativos

**Justificativa:** Segue práticas de infraestrutura como código (IaC), permitindo execução repetida e uso em automações como Ansible, Chef ou Puppet.

## Integração com Outros Módulos

O módulo de segurança SSH deve ser complementado com:

1. **Configuração de Firewall** - Limitar acesso à porta SSH
2. **Fail2ban** - Banir IPs após múltiplas tentativas falhas
3. **LogWatch** - Monitorar e alertar sobre tentativas de acesso
4. **Auditoria** - Tracking completo de comandos executados por sessão

## Detecção e Adaptação ao Ambiente

O script detecta automaticamente:
- Distribuição Linux em uso
- Ferramentas disponíveis (systemd vs init.d)
- Usuários existentes no sistema
- Verificação de portas em uso
