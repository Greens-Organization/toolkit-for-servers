# Desativando Login SSH Direto como Root

## Visão Geral

A desativação do login SSH direto como root é uma prática de segurança fundamental implementada no Toolkit for Servers através da configuração `PermitRootLogin no`. Este documento explica por que essa configuração é crítica e como o toolkit implementa uma abordagem mais segura.

## Implementação no Toolkit

```bash
# Desabilita login root direto via SSH no arquivo de configuração
PermitRootLogin no

# Trecho que cria um usuário alternativo com privilégios sudo
if [ "$current_user" = "root" ] && [ -z "$SUDO_USER" ]; then
    # Cria um usuário admin se não existir nenhum usuário regular
    current_user="admin"
    adduser --disabled-password --gecos "" "$current_user"
    
    # Adiciona ao grupo sudo ou wheel
    if getent group sudo >/dev/null; then
        usermod -aG sudo "$current_user"
    elif getent group wheel >/dev/null; then
        usermod -aG wheel "$current_user"
    fi
}

# Configuração de sudo sem senha para o usuário
echo "$current_user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$current_user"
chmod 440 "/etc/sudoers.d/$current_user"
```

## Justificativa de Segurança

### Riscos do Login Root Direto

1. **Alvo Primário de Ataques**: A conta root é o principal alvo para atacantes, pois oferece controle total sobre o sistema sem restrições.

2. **Sem Trilha de Auditoria Clara**: Login direto como root dificulta determinar qual administrador realizou alterações específicas no sistema.

3. **Sem Camada Adicional de Proteção**: Em caso de vulnerabilidade no servidor SSH, o atacante ganha imediatamente privilégios totais de sistema.

4. **Maior Superfície de Ataque**: Permitir login root multiplica os vetores de ataque comparado com um acesso em duas etapas (usuário regular + sudo).

5. **Risco de Erros Críticos**: Sessões sempre com privilégios totais aumentam o risco de comandos destrutivos acidentais.

### Benefícios da Abordagem por Usuário + Sudo

1. **Defesa em Profundidade**: Um atacante precisa comprometer uma conta regular E escalar privilégios, aumentando significativamente a dificuldade.

2. **Auditoria Aprimorada**: Comandos executados com sudo são registrados separadamente, facilitando auditoria e forense.

3. **Consciência de Privilégios**: O uso explícito de sudo lembra os administradores que estão executando comandos privilegiados.

4. **Proteção contra Erros**: Dificulta a execução acidental de comandos destrutivos que podem afetar todo o sistema.

5. **Conformidade com Padrões**: Exigido pela maioria dos frameworks de segurança e compliance como CIS, NIST, PCI-DSS e ISO 27001.

## Práticas Implementadas pelo Toolkit

### 1. Criação de Usuário Administrativo

Quando necessário, o script cria automaticamente um usuário administrativo não-root:

- Detecta se existem usuários não-root no sistema
- Se não encontrar, cria um usuário "admin" padrão
- Configura o diretório home e permissões apropriadas
- Adiciona o usuário ao grupo sudo (Debian/Ubuntu) ou wheel (RHEL/CentOS)

### 2. Configuração de Privilégios Sudo

Para facilitar a administração sem comprometer a segurança:

- Configura o usuário administrativo para usar sudo sem senha
- Utiliza o arquivo sudoers.d para isolar a configuração
- Define permissões 440 (r--r-----) para o arquivo sudoers
- Implementação compatível com sistemas baseados em RHEL e Debian

### 3. Uso de SSH com Elevação de Privilégios

O fluxo de trabalho recomendado para administração:

1. Conectar via SSH como usuário regular
2. Elevar privilégios quando necessário: `sudo comando`
3. Para sessões de administração prolongadas: `sudo -i`
4. Para executar scripts complexos: `sudo bash script.sh`

### 4. Verificações e Alertas

O toolkit implementa verificações de segurança:

- Alerta sobre configurações inseguras encontradas
- Verifica se PermitRootLogin está desativado nas configurações existentes
- Mantém logs detalhados de tentativas de login negadas

## Casos Extremos e Considerações

### Recuperação de Emergência

Em cenários de recuperação de emergência, considere:

- Manter um segundo usuário administrativo como backup
- Documentar procedimentos de recuperação para casos em que o acesso SSH principal falha
- Para necessidades de manutenção remota extrema, considerar configurações temporárias via console físico

### Ambientes Específicos

Em alguns ambientes altamente especializados ou automatizados, pode ser necessário:

- Configurar `PermitRootLogin without-password` (permitindo apenas chaves SSH para root)
- Limitar acesso root a endereços IP específicos através de firewall ou Match directives
- Implementar alertas para quaisquer logins bem-sucedidos como root

Estas exceções devem ser cuidadosamente consideradas, documentadas e aprovadas por equipes de segurança.

## Implementações em Sistemas de Gerenciamento de Configuração

Para integração com ferramentas como Ansible, Puppet, ou Chef:

```yaml
# Exemplo de playbook Ansible
- name: Desativar login SSH como root
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin no'
    validate: '/usr/sbin/sshd -t -f %s'
  notify: restart sshd

- name: Configurar usuário administrador
  user:
    name: admin
    groups: sudo
    shell: /bin/bash
    generate_ssh_key: yes
    ssh_key_bits: 4096
```

## Referências

1. CIS Benchmarks para Linux: https://www.cisecurity.org/benchmark/distribution_independent_linux/
2. NIST SP 800-53 - AC-6 (Least Privilege)
3. Linux Security Wiki: Securing OpenSSH
4. RedHat Security Hardening Guidelines
5. Ubuntu Server Guide: Security Best Practices
6. Center for Internet Security (CIS): "Critical Security Controls"
7. DISA STIG para Unix/Linux
