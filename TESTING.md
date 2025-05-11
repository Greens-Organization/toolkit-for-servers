# Guia de Testes para o Toolkit for Servers

Este documento descreve como configurar e executar a suíte de testes para o Toolkit for Servers, garantindo que todas as funcionalidades funcionem conforme esperado em diferentes distribuições Linux.

## Tipos de Testes

O Toolkit for Servers utiliza três camadas de testes:

1. **Análise Estática (Linting)**: Verifica a qualidade do código usando ShellCheck
2. **Testes Unitários**: Testa funções individuais usando Bats (Bash Automated Testing System)
3. **Testes de Integração**: Verifica o funcionamento completo do toolkit em diferentes distribuições usando Docker/Podman

## Pré-requisitos

Para executar todos os testes, você precisará:

- Bash 4.0+
- [ShellCheck](https://www.shellcheck.net/) para análise estática
- [Bats](https://github.com/bats-core/bats-core) para testes unitários
- Docker ou Podman para testes de integração

OBS: O [`test-suite.sh`](./test-suite.sh) já verifica e instala para você as dependências necessárias baseado em alguns sistemas operacionais.

## Estrutura de Diretórios

```
toolkit-for-servers/
├── install.sh              # Script principal
├── modules/                # Módulos individuais
│   ├── secure_ssh.sh
│   ├── setup_firewall.sh
│   ├── setup_fail2ban.sh
│   ├── optimize_system.sh
│   └── install_docker.sh
├── tests/                  # Testes unitários e auxiliares
│   ├── test_helper.bash    # Funções auxiliares para testes
│   ├── test_secure_ssh.bats
│   ├── test_setup_firewall.bats
│   ├── test_setup_fail2ban.bats
│   ├── test_optimize_system.bats
│   └── test_install_docker.bats
├── docker/                 # Arquivos Dockerfile para testes
│   ├── ubuntu-22.04.Dockerfile
│   ├── debian-12.Dockerfile
│   ├── centos-7.Dockerfile
│   └── almalinux-9.Dockerfile
└── test-suite.sh           # Script de execução de testes
```

## Executando os Testes

### Executar Todos os Testes

```bash
./test-suite.sh
```

### Executar Testes Específicos

```bash
# Testar apenas o módulo SSH
./test-suite.sh --module=secure_ssh

# Testar apenas no Ubuntu
./test-suite.sh --distro=ubuntu

# Pular a análise de linting
./test-suite.sh --skip-lint

# Executar apenas testes unitários
./test-suite.sh --skip-lint --skip-integration
```

## Testes Unitários com Bats

Os testes unitários usam o framework Bats para verificar o comportamento de funções individuais. Cada arquivo `.bats` corresponde a um módulo específico.

### Exemplo de Teste Bats

```bash
#!/usr/bin/env bats

load 'test_helper'

@test "secure_ssh creates config file" {
  # Configura o ambiente de teste
  local test_dir=$(setup_test_root)
  
  # Executa a função
  run secure_ssh 2222
  
  # Verifica se a execução foi bem-sucedida
  [ "$status" -eq 0 ]
  
  # Verifica se o arquivo de configuração foi criado
  [ -f "$test_dir/etc/ssh/sshd_config.d/00-security.conf" ]
  
  # Verifica configurações específicas
  assert_file_contains "$test_dir/etc/ssh/sshd_config.d/00-security.conf" "Port 2222"
  assert_file_contains "$test_dir/etc/ssh/sshd_config.d/00-security.conf" "PermitRootLogin no"
  
  # Limpa o ambiente de teste
  teardown_test_root "$test_dir"
}
```

### Escrevendo Bons Testes Unitários

1. **Isolamento**: Cada teste deve ser independente e não depender de outros testes
2. **Determinismo**: Os testes devem ser reproduzíveis e não depender de condições externas
3. **Simplicidade**: Cada teste deve verificar uma única funcionalidade ou caso de uso
4. **Cobertura**: Os testes devem cobrir tanto os casos de sucesso quanto os de falha
5. **Legibilidade**: Os testes devem ser fáceis de entender e manter

## Testes de Integração com Docker/Podman

Os testes de integração verificam o comportamento do toolkit em um ambiente real simulado usando containers. Isso permite testar em diferentes distribuições Linux.

### Exemplo de Dockerfile para Testes

```dockerfile
FROM ubuntu:22.04

# Configuração para systemd
ENV container docker
STOPSIGNAL SIGRTMIN+3

# Diretório de trabalho
WORKDIR /toolkit

# Copia os arquivos do toolkit
COPY install.sh /toolkit/
COPY modules/ /toolkit/modules/

# Instala dependências
RUN apt-get update && \
    apt-get install -y curl wget systemd systemd-sysv

# Script de teste
RUN echo '#!/bin/bash' > /toolkit/run-tests.sh && \
    echo 'set -e' >> /toolkit/run-tests.sh && \
    echo 'chmod +x /toolkit/install.sh' >> /toolkit/run-tests.sh && \
    echo '/toolkit/install.sh --minimal' >> /toolkit/run-tests.sh && \
    echo 'echo "Teste concluído com sucesso!"' >> /toolkit/run-tests.sh && \
    chmod +x /toolkit/run-tests.sh

# Entrypoint
ENTRYPOINT ["/usr/sbin/init"]
CMD ["/toolkit/run-tests.sh"]
```

## Integração Contínua (CI)

O Toolkit for Servers utiliza GitHub Actions para executar testes automaticamente em cada push e pull request.

### Fluxo de CI

1. **Lint**: Verifica a qualidade do código com ShellCheck
2. **Testes Unitários**: Executa testes Bats
3. **Testes de Integração**: Executa testes em diferentes distribuições usando Docker
4. **Notificação**: Envia notificação do resultado dos testes

## Boas Práticas para Testes

### 1. Criar Mocks para Comandos Externos

Em vez de executar comandos reais que podem modificar o sistema, crie funções simuladas (mocks):

```bash
# Exemplo de mock para systemctl
function systemctl() {
  echo "Called: systemctl $*"
  return 0
}
export -f systemctl
```

### 2. Usar Diretórios Temporários

Crie sempre diretórios temporários para os testes e limpe-os após a execução:

```bash
# Criar diretório temporário
TEST_DIR=$(mktemp -d)

# Limpar diretório após o teste
rm -rf "$TEST_DIR"
```

### 3. Testar Casos Extremos

Não teste apenas o caminho feliz; teste também cenários de falha:

- O que acontece se o arquivo de configuração não existir?
- O que acontece se o serviço estiver ausente?
- O que acontece se o usuário não tiver permissões suficientes?

### 4. Testar em Distribuições Diferentes

Certifique-se de que os testes cubram todas as distribuições suportadas:

- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12
- CentOS 7, 8
- AlmaLinux/Rocky Linux 8, 9

### 5. Documentar os Testes

Adicione comentários explicando o propósito de cada teste e o que está sendo verificado.

## Solução de Problemas Comuns

### Permissões Insuficientes

Se ocorrerem erros relacionados a permissões:

```bash
# Dê permissões de execução aos scripts
chmod +x install.sh
chmod +x modules/*.sh
chmod +x tests/*.bats
chmod +x test-suite.sh
```

### Bats Não Encontrado

Se o Bats não for encontrado no PATH:

```bash
# Instale o Bats globalmente
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Testes Falhando em Docker

Se os testes de integração falharem no Docker:

```bash
# Execute o container em modo privilegiado
docker run --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro toolkit-test
```

## Conclusão

Manter uma suíte de testes abrangente é essencial para garantir a qualidade e confiabilidade do Toolkit for Servers. Ao seguir as práticas recomendadas neste guia, você pode desenvolver e contribuir com scripts robustos e bem testados.

Lembre-se:
- **Teste antes de confirmar**: Execute os testes antes de enviar alterações
- **Novos recursos = novos testes**: Adicione testes para cada nova funcionalidade
- **Corrigir bugs = corrigir testes**: Atualize os testes ao corrigir bugs

Para mais informações sobre as ferramentas de teste:
- [ShellCheck](https://www.shellcheck.net/)
- [Bats](https://github.com/bats-core/bats-core)
- [Docker](https://docs.docker.com/engine/reference/commandline/docker/)
