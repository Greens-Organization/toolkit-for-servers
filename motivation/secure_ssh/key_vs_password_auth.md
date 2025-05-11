# Autenticação por Chave SSH vs. Senha

## Visão Geral

A autenticação por chave SSH é implementada no Toolkit for Servers como único método de autenticação, desabilitando completamente a autenticação por senha. Este documento explica por que essa é uma prática essencial para a segurança de servidores modernos.

## Implementação no Toolkit

```bash
# Configurações de autenticação no sshd_config
PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
ChallengeResponseAuthentication no
```

```bash
# Função que configura as chaves autorizadas
configure_ssh_authorized_keys() {
    # Identificação do usuário não-root
    local current_user=$(logname 2>/dev/null || echo "$SUDO_USER" || id -un)
    
    # Criação da estrutura de diretórios .ssh com permissões corretas
    local user_home=$(eval echo ~"$current_user")
    local ssh_dir="$user_home/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Configuração do arquivo authorized_keys
    local auth_keys="$ssh_dir/authorized_keys"
    touch "$auth_keys"
    chmod 600 "$auth_keys"
    
    # Adição de chaves públicas ou geração de chave de emergência
    # ...
}
```

## Justificativa

### Vantagens da Autenticação por Chave SSH

1. **Resistência a Ataques de Força Bruta**: Uma chave SSH típica de 4096 bits ou ED25519 é virtualmente invulnerável a tentativas de força bruta, enquanto senhas podem ser quebradas com recursos computacionais suficientes.

2. **Eliminação de Credenciais Reutilizadas**: Usuários frequentemente reutilizam senhas em múltiplos sistemas. Vazamentos de dados em um serviço podem comprometer servidores que usam as mesmas senhas.

3. **Autenticação de Dois Fatores Intrínseca**: A autenticação por chave SSH requer algo que você tem (a chave privada) e algo que você sabe (a frase-senha da chave, se configurada).

4. **Revogação Simplificada**: Revogar acesso é tão simples quanto remover uma chave pública do arquivo `authorized_keys`, sem necessidade de alterar senhas compartilhadas.

5. **Automação Segura**: Permite scripts e automação sem armazenar senhas em texto simples em arquivos de configuração.

6. **Autenticação Silenciosa**: Não há transmissão de credenciais pela rede, mesmo em formato criptografado.

7. **Prevenção contra Keyloggers**: Mesmo se um keylogger estiver presente no cliente, a chave privada permanece protegida se estiver protegida por frase-senha.

### Riscos da Autenticação por Senha

1. **Vulnerabilidade a Ataques de Força Bruta**: Servidores expostos à internet recebem centenas ou milhares de tentativas de login diariamente.

2. **Senhas Fracas**: Estudos mostram que muitos usuários ainda escolhem senhas fáceis de adivinhar ou curtas demais.

3. **Phishing**: Usuários podem ser enganados para revelar suas senhas em sites falsos.

4. **Transmissão de Credenciais**: Senhas são verificadas enviando-as para o servidor, mesmo que criptografadas.

5. **Exposição em Logs ou Dumps de Memória**: Senhas podem aparecer em logs, dumps de memória ou histórico de comandos.

## Implementação Segura

O Toolkit implementa as seguintes práticas para garantir a segurança das chaves SSH:

1. **Permissões Estritas**: 
   - Diretórios `.ssh`: 700 (rwx------)
   - Arquivos de chave: 600 (rw-------)

2. **Geração de Chaves de Emergência**:
   - Oferece opção de gerar um par de chaves quando nenhuma chave é encontrada
   - Exibe a chave privada apenas uma vez para o usuário salvar
   - Remove a chave privada do servidor após exibição

3. **Usuário Não-Root**:
   - Configura as chaves para um usuário regular com privilégios sudo
   - Evita acesso direto como root

4. **Detecção Inteligente**:
   - Identifica usuários existentes no sistema
   - Cria um usuário admin se necessário

## Considerações Sobre Transição

Ao migrar de autenticação por senha para chave SSH, considere:

1. **Período de Transição**: Em ambientes de produção críticos, considere habilitar temporariamente ambos os métodos e depois desativar senhas.

2. **Backup das Chaves**: Mantenha backups seguros das chaves privadas e considere chaves múltiplas para casos de contingência.

3. **Rastreabilidade**: Para servidores com múltiplos administradores, use comentários nas chaves para identificar proprietários.

4. **Gestão de Chaves**: Implemente um processo para rotação e revogação de chaves quando funcionários saem da organização.

## Melhores Práticas Adicionais

1. **Proteção com Frase-Senha**: Proteja suas chaves privadas com frases-senha fortes
2. **Uso de ssh-agent**: Utilize ssh-agent para armazenar chaves temporariamente sem redigitar a frase-senha
3. **Rotação Periódica**: Considere trocar chaves anualmente ou após incidentes de segurança
4. **Hardware Security Modules**: Para ambientes de alta segurança, armazene chaves em HSMs ou YubiKeys

## Referências

1. NIST Special Publication 800-63B: Digital Identity Guidelines
2. OWASP Authentication Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html
3. SSH.com: "Password vs. Key Authentication": https://www.ssh.com/academy/ssh/key-authentication
4. Cybersecurity & Infrastructure Security Agency (CISA): "Security Tip (ST05-017) - Securing Network Infrastructure Devices"
5. Google Cloud: "SSH Key Management Best Practices"
6. AWS Security Best Practices: "Using SSH Keys with Amazon EC2"
