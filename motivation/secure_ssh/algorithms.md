# Algoritmos de Criptografia Modernos para SSH

## Visão Geral

A implementação de algoritmos criptográficos modernos é essencial para proteger o tráfego SSH contra ataques de interceptação, descriptografia e manipulação. O módulo `secure_ssh.sh` do Toolkit for Servers implementa uma configuração robusta que prioriza algoritmos seguros e eficientes, removendo opções obsoletas ou vulneráveis.

## Implementação no Toolkit

O script implementa as seguintes configurações de criptografia no arquivo `/etc/ssh/sshd_config.d/00-security.conf`:

```bash
# Criptografia (adequado para 2025)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
```

Adicionalmente, o script configura as chaves de host:

```bash
# Configurações de segurança básicas
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
```

O script também verifica e gera novas chaves de host se necessário:

```bash
# Gera novas chaves de host se não existirem ou forem antigas
if [ ! -f /etc/ssh/ssh_host_ed25519_key ] || [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    log "INFO" "Gerando novas chaves de host SSH..."
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" < /dev/null
    ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" < /dev/null
else
    # Verifica a idade das chaves (> 1 ano)
    local ed25519_age=$(stat -c %Y /etc/ssh/ssh_host_ed25519_key 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local one_year=$((365*24*60*60))
    
    if [ $((current_time - ed25519_age)) -gt $one_year ]; then
        log "WARN" "Chaves SSH têm mais de 1 ano. Considere renová-las com: ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''"
    fi
fi
```

## Justificativa de Segurança

### Algoritmos de Troca de Chaves (KexAlgorithms)

1. **Curve25519**: 
   - Projetado pelo renomado criptógrafo Daniel J. Bernstein
   - Resistente a ataques de canal lateral (timing attacks)
   - Implementação mais simples e menos propensa a erros que curvas NIST
   - Desempenho superior em hardware diverso

2. **Diffie-Hellman com Grupos Fortes**:
   - Grupos 16 e 18 utilizam primos de 4096 e 8192 bits respectivamente
   - Resistentes a ataques de pré-computação e criptoanálise quântica parcial
   - Compatíveis com clientes mais antigos quando Curve25519 não está disponível

3. **Algoritmos Excluídos**:
   - Removidos grupos DH 1, 14 e menores (vulneráveis a ataques Logjam)
   - Eliminados algoritmos baseados em ECDSA (potencialmente comprometidos por agências governamentais)
   - Excluídos algoritmos baseados em SHA-1 (colisões demonstradas)

### Cifras (Ciphers)

1. **ChaCha20-Poly1305**:
   - Cifra de fluxo moderna com autenticação integrada
   - Excelente desempenho em hardware sem aceleração AES
   - Resistente a ataques de timing por design
   - Priorizada para dispositivos móveis e sistemas embarcados

2. **AES-GCM (256/128 bits)**:
   - Modo de operação autenticado que protege confidencialidade e integridade
   - Aproveitamento de instruções AES-NI em CPUs modernas
   - Resistente a ataques de padding e oracle
   - Conformidade com padrões FIPS e requisitos governamentais

### Códigos de Autenticação de Mensagem (MACs)

1. **ETM (Encrypt-then-MAC)**:
   - Verifica a integridade do ciphertext antes da descriptografia
   - Previne ataques de padding oracle e manipulação de ciphertext
   - Implementação mais segura que MAC-then-Encrypt

2. **SHA-2 (256/512)**:
   - Funções hash criptograficamente seguras
   - Resistentes a ataques de colisão e pré-imagem
   - Conformidade com padrões de segurança governamentais

3. **UMAC-128**:
   - MAC baseado em hash universal, extremamente rápido
   - Segurança comprovada matematicamente
   - Excelente desempenho em hardware limitado

### Algoritmos de Chave de Host

1. **ED25519**:
   - Algoritmo de assinatura digital baseado em curvas elípticas
   - Chaves menores (256 bits) com segurança equivalente a RSA 3072+
   - Verificação e geração de assinaturas extremamente rápidas
   - Resistente a falhas de implementação comuns em outros algoritmos

2. **RSA com tamanho de 4096 bits**:
   - Mantido para compatibilidade com clientes mais antigos
   - Tamanho de chave de 4096 bits oferece margem de segurança adequada
   - Gerado automaticamente se não existir

## Rotação de Chaves e Manutenção

O script implementa verificação de idade das chaves de host:

1. **Verificação Automática**: Alerta quando as chaves têm mais de 1 ano
2. **Geração Automática**: Cria novas chaves se não existirem
3. **Recomendação de Renovação**: Fornece comando para renovação manual

Esta abordagem equilibra segurança com estabilidade operacional, permitindo que administradores decidam o melhor momento para rotação de chaves.

## Monitoramento e Manutenção

### Verificações Periódicas

1. Alertas para algoritmos que se tornam obsoletos
2. Verificação de novas vulnerabilidades via CVE
3. Rotação automática de chaves de host a cada 365 dias
4. Testes de conexão após atualizações do sistema

### Exemplo de Verificação de Algoritmos

```bash
# Script para verificar algoritmos em uso
ssh -vv -o HostKeyAlgorithms=ssh-ed25519 -o KexAlgorithms=curve25519-sha256 \
    -o Ciphers=chacha20-poly1305@openssh.com \
    -o MACs=hmac-sha2-512-etm@openssh.com \
    -p $ssh_port user@localhost exit
```

## Referências

1. Mozilla SSH Guidelines: https://infosec.mozilla.org/guidelines/openssh
2. IETF RFC 9142 - Key Exchange (KEX) Method Updates and Recommendations
3. NIST SP 800-57 - Recommendation for Key Management
4. BSI TR-02102-4 - Cryptographic Mechanisms: SSH
5. stribika SSH Guide: https://stribika.github.io/2015/01/04/secure-secure-shell.html
6. SSH.com Security Best Practices
7. OpenSSH Security Advisories
