#!/usr/bin/env bash
#
# Toolkit for Servers - Suíte de Testes
#
# Este script executa testes automatizados para o Toolkit for Servers,
# verificando a funcionalidade de todos os módulos em diferentes distribuições.
#
# Requisitos:
# - Docker ou Podman instalado
# - Bats-core (https://github.com/bats-core/bats-core)
# - ShellCheck (https://www.shellcheck.net/)
#
# Uso: ./test-suite.sh [--distro=ubuntu|debian|centos|almalinux] [--module=all|secure_ssh|...]

set -e

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests"
MODULES_DIR="${SCRIPT_DIR}/modules"
DOCKER_DIR="${SCRIPT_DIR}/docker"

# Opções padrão
DISTRO="all"
MODULE="all"
CONTAINER_ENGINE="docker"
SKIP_LINT=false
SKIP_UNIT=false
SKIP_INTEGRATION=false

# Distribuições suportadas
SUPPORTED_DISTROS=(
  "ubuntu:22.04"
  "debian:12"
  "centos:7"
  "almalinux:9"
)

# Módulos a testar
MODULES=(
  "install.sh"
  "secure_ssh.sh"
  "setup_firewall.sh"
  "setup_fail2ban.sh"
  "optimize_system.sh"
  "install_docker.sh"
)

# Mensagem de ajuda
show_help() {
  cat << EOF
Toolkit for Servers - Suíte de Testes

Uso: ./test-suite.sh [OPÇÕES]

Opções:
  --distro=DISTRO       Distribuição para testar (ubuntu, debian, centos, almalinux, all)
  --module=MODULE       Módulo específico para testar (install, secure_ssh, all, etc.)
  --podman              Usar Podman em vez de Docker
  --skip-lint           Pular verificação de linting (ShellCheck)
  --skip-unit           Pular testes unitários (Bats)
  --skip-integration    Pular testes de integração (Docker)
  --help, -h            Mostra esta mensagem

Exemplos:
  ./test-suite.sh                            # Executa todos os testes em todas as distribuições
  ./test-suite.sh --distro=ubuntu            # Testa apenas no Ubuntu
  ./test-suite.sh --module=secure_ssh        # Testa apenas o módulo SSH
  ./test-suite.sh --skip-lint --skip-unit    # Executa apenas testes de integração
EOF
}

# Função para mensagens de log
log() {
  local level=$1
  local message=$2

  case $level in
    "INFO")
      echo -e "${GREEN}[INFO]${NC} $message"
      ;;
    "WARN")
      echo -e "${YELLOW}[WARN]${NC} $message"
      ;;
    "ERROR")
      echo -e "${RED}[ERROR]${NC} $message"
      ;;
    "TEST")
      echo -e "${BLUE}[TEST]${NC} $message"
      ;;
    *)
      echo -e "[${level}] $message"
      ;;
  esac
}

# Verifica dependências
check_dependencies() {
  log "INFO" "Verificando dependências..."

  # Verifica Docker/Podman
  if [ "$CONTAINER_ENGINE" = "docker" ]; then
    if ! command -v docker &> /dev/null; then
      log "ERROR" "Docker não encontrado. Instale o Docker ou use --podman."
      exit 1
    fi
  else
    if ! command -v podman &> /dev/null; then
      log "ERROR" "Podman não encontrado. Instale o Podman ou use Docker."
      exit 1
    fi
  fi

  # Verifica ShellCheck para linting (se não for pulado)
  if [ "$SKIP_LINT" = false ]; then
    if ! command -v shellcheck &> /dev/null; then
      log "WARN" "ShellCheck não encontrado. Instalando..."

      if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y shellcheck
      elif command -v yum &> /dev/null; then
        sudo yum -y install epel-release
        sudo yum -y install ShellCheck
      elif command -v brew &> /dev/null; then
        brew install shellcheck
      else
        log "ERROR" "Não foi possível instalar ShellCheck automaticamente."
        log "ERROR" "Instale manualmente ou use --skip-lint."
        exit 1
      fi
    fi
  fi

  # Verifica Bats para testes unitários (se não for pulado)
  if [ "$SKIP_UNIT" = false ]; then
    if ! command -v bats &> /dev/null; then
      log "WARN" "Bats não encontrado. Instalando..."

      # Cria diretório temporário para instalação
      local tmp_dir
      tmp_dir=$(mktemp -d)

      # Clona e instala Bats
      git clone https://github.com/bats-core/bats-core.git "$tmp_dir"
      cd "$tmp_dir"
      sudo ./install.sh /usr/local
      cd - || exit 1

      # Limpa diretório temporário
      rm -rf "$tmp_dir"

      # Verifica se a instalação foi bem-sucedida
      if ! command -v bats &> /dev/null; then
        log "ERROR" "Falha ao instalar Bats."
        log "ERROR" "Instale manualmente (https://github.com/bats-core/bats-core) ou use --skip-unit."
        exit 1
      fi
    fi
  fi
}

# Executa linting com ShellCheck
run_lint_tests() {
  if [ "$SKIP_LINT" = true ]; then
    log "INFO" "Testes de linting ignorados."
    return 0
  fi

  log "TEST" "Executando testes de linting com ShellCheck..."

  local failed=false

  # Testa o script principal
  log "TEST" "Verificando install.sh..."
  if ! shellcheck -x "${SCRIPT_DIR}/install.sh"; then
    log "ERROR" "Falha na verificação de install.sh"
    failed=true
  fi

  # Testa cada módulo
  for module in "${MODULES[@]}"; do
    if [ "$MODULE" = "all" ] || [ "$MODULE" = "${module%.sh}" ]; then
      if [ -f "${MODULES_DIR}/${module}" ]; then
        log "TEST" "Verificando ${module}..."
        if ! shellcheck -x "${MODULES_DIR}/${module}"; then
          log "ERROR" "Falha na verificação de ${module}"
          failed=true
        fi
      fi
    fi
  done

  # Testa os scripts de teste
  if [ -d "${TEST_DIR}" ]; then
    for test_file in "${TEST_DIR}"/*.bats; do
      if [ -f "$test_file" ]; then
        log "TEST" "Verificando $(basename "$test_file")..."
        if ! shellcheck -x "$test_file"; then
          log "ERROR" "Falha na verificação de $(basename "$test_file")"
          failed=true
        fi
      fi
    done
  fi

  if [ "$failed" = true ]; then
    log "ERROR" "Falha nos testes de linting."
    return 1
  else
    log "INFO" "Todos os testes de linting passaram com sucesso!"
    return 0
  fi
}

# Executa testes unitários com Bats
run_unit_tests() {
  if [ "$SKIP_UNIT" = true ]; then
    log "INFO" "Testes unitários ignorados."
    return 0
  fi

  log "TEST" "Executando testes unitários com Bats..."

  # Verifica se o diretório de testes existe
  if [ ! -d "${TEST_DIR}" ]; then
    log "ERROR" "Diretório de testes não encontrado: ${TEST_DIR}"
    return 1
  fi

  # Decide quais arquivos de teste executar
  local test_files=()

  if [ "$MODULE" = "all" ]; then
    # Todos os arquivos de teste
    test_files=("${TEST_DIR}"/*.bats)
  else
    # Apenas testes do módulo especificado
    if [ -f "${TEST_DIR}/test_${MODULE}.bats" ]; then
      test_files=("${TEST_DIR}/test_${MODULE}.bats")
    else
      log "ERROR" "Arquivo de teste não encontrado para o módulo: ${MODULE}"
      return 1
    fi
  fi

  # Executa os testes
  if [ ${#test_files[@]} -gt 0 ]; then
    if ! bats "${test_files[@]}"; then
      log "ERROR" "Falha nos testes unitários."
      return 1
    else
      log "INFO" "Todos os testes unitários passaram com sucesso!"
      return 0
    fi
  else
    log "WARN" "Nenhum arquivo de teste encontrado."
    return 0
  fi
}

# Executa testes de integração com Docker/Podman
run_integration_tests() {
  if [ "$SKIP_INTEGRATION" = true ]; then
    log "INFO" "Testes de integração ignorados."
    return 0
  fi

  log "TEST" "Executando testes de integração com ${CONTAINER_ENGINE}..."

  local distros=()

  # Decide quais distribuições testar
  if [ "$DISTRO" = "all" ]; then
    distros=("${SUPPORTED_DISTROS[@]}")
  else
    # Encontra a distribuição especificada
    for d in "${SUPPORTED_DISTROS[@]}"; do
      if [[ "$d" == "$DISTRO"* ]]; then
        distros=("$d")
        break
      fi
    done

    if [ ${#distros[@]} -eq 0 ]; then
      log "ERROR" "Distribuição não suportada: ${DISTRO}"
      log "ERROR" "Distribuições suportadas: ubuntu, debian, centos, almalinux"
      return 1
    fi
  fi

  # Testa em cada distribuição
  for distro in "${distros[@]}"; do
    local distro_name
    distro_name=$(echo "$distro" | cut -d: -f1)
    local distro_version
    distro_version=$(echo "$distro" | cut -d: -f2)

    log "TEST" "Testando em ${distro_name} ${distro_version}..."

    # Cria Dockerfile para a distribuição
    local docker_file="${DOCKER_DIR}/${distro_name}-${distro_version}.Dockerfile"
    mkdir -p "${DOCKER_DIR}"

    # Gera Dockerfile baseado na distribuição
    create_dockerfile "$distro" "$docker_file"

    # Constrói imagem de teste
    local image_name="toolkit-test-${distro_name}-${distro_version}"
    log "INFO" "Construindo imagem de teste: ${image_name}..."

    if [ "$CONTAINER_ENGINE" = "docker" ]; then
      if ! docker build -t "$image_name" -f "$docker_file" .; then
        log "ERROR" "Falha ao construir imagem Docker para ${distro_name} ${distro_version}"
        continue
      fi
    else
      if ! podman build -t "$image_name" -f "$docker_file" .; then
        log "ERROR" "Falha ao construir imagem Podman para ${distro_name} ${distro_version}"
        continue
      fi
    fi

    # Executa testes na imagem
    log "INFO" "Executando testes em ${distro_name} ${distro_version}..."

    if [ "$CONTAINER_ENGINE" = "docker" ]; then
      if ! docker run --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro "$image_name"; then
        log "ERROR" "Falha nos testes de integração para ${distro_name} ${distro_version}"
      else
        log "INFO" "Testes de integração passaram com sucesso em ${distro_name} ${distro_version}!"
      fi
    else
      if ! podman run --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro "$image_name"; then
        log "ERROR" "Falha nos testes de integração para ${distro_name} ${distro_version}"
      else
        log "INFO" "Testes de integração passaram com sucesso em ${distro_name} ${distro_version}!"
      fi
    fi
  done

  return 0
}

# Cria Dockerfile para cada distribuição
create_dockerfile() {
  local distro=$1
  local dockerfile=$2
  local distro_name
  distro_name=$(echo "$distro" | cut -d: -f1)

  # Base do Dockerfile
  cat > "$dockerfile" << EOF
FROM $distro

# Adiciona metadados
LABEL maintainer="GRN Group <info@grngroup.net>"
LABEL description="Imagem de teste para Toolkit for Servers - $distro"

# Configuração para systemd
ENV container docker
STOPSIGNAL SIGRTMIN+3

# Diretório de trabalho
WORKDIR /toolkit

# Copia os arquivos do toolkit
COPY install.sh /toolkit/
COPY modules/ /toolkit/modules/
COPY tests/ /toolkit/tests/
EOF

  # Adiciona pacotes específicos baseados na distribuição
  case $distro_name in
    ubuntu|debian)
      cat >> "$dockerfile" << EOF
# Instala dependências
RUN apt-get update && \\
    apt-get install -y --no-install-recommends \\
    curl wget ca-certificates \\
    systemd systemd-sysv \\
    procps kmod \\
    iptables iproute2 \\
    python3 \\
    && rm -rf /var/lib/apt/lists/*

# Configuração para systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \\
    ls | grep -v systemd-tmpfiles-setup | xargs rm -f && \\
    rm -f /lib/systemd/system/multi-user.target.wants/* && \\
    rm -f /etc/systemd/system/*.wants/* && \\
    rm -f /lib/systemd/system/local-fs.target.wants/* && \\
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \\
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \\
    rm -f /lib/systemd/system/basic.target.wants/* && \\
    rm -f /lib/systemd/system/anaconda.target.wants/* && \\
    rm -f /lib/systemd/system/plymouth* && \\
    rm -f /lib/systemd/system/systemd-update-utmp*
EOF
      ;;
    centos|almalinux|rocky)
      cat >> "$dockerfile" << EOF
# Instala dependências
RUN yum -y update && \\
    yum -y install \\
    curl wget ca-certificates \\
    systemd systemd-sysv \\
    procps kmod \\
    iptables iproute \\
    python3 \\
    && yum clean all

# Configuração para systemd
RUN cd /lib/systemd/system/sysinit.target.wants/ && \\
    ls | grep -v systemd-tmpfiles-setup | xargs rm -f && \\
    rm -f /lib/systemd/system/multi-user.target.wants/* && \\
    rm -f /etc/systemd/system/*.wants/* && \\
    rm -f /lib/systemd/system/local-fs.target.wants/* && \\
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \\
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \\
    rm -f /lib/systemd/system/basic.target.wants/* && \\
    rm -f /lib/systemd/system/anaconda.target.wants/*
EOF
      ;;
  esac

  # Script de teste e entrypoint
  cat >> "$dockerfile" << EOF
# Cria script de teste
RUN echo '#!/bin/bash' > /toolkit/run-tests.sh && \\
    echo 'set -e' >> /toolkit/run-tests.sh && \\
    echo 'echo "Iniciando testes para $distro"' >> /toolkit/run-tests.sh && \\
    echo 'chmod +x /toolkit/install.sh' >> /toolkit/run-tests.sh && \\
    echo 'for m in /toolkit/modules/*.sh; do chmod +x \$m; done' >> /toolkit/run-tests.sh && \\
EOF

  # Adiciona testes específicos para cada módulo
  if [ "$MODULE" = "all" ]; then
    cat >> "$dockerfile" << EOF
    echo '# Teste de verificação de sintaxe' >> /toolkit/run-tests.sh && \\
    echo 'bash -n /toolkit/install.sh' >> /toolkit/run-tests.sh && \\
    echo 'for m in /toolkit/modules/*.sh; do bash -n \$m; done' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Teste com a flag --help' >> /toolkit/run-tests.sh && \\
    echo '/toolkit/install.sh --help || exit 1' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Teste de instalação minimal' >> /toolkit/run-tests.sh && \\
    echo 'echo "Testando instalação mínima..."' >> /toolkit/run-tests.sh && \\
    echo '/toolkit/install.sh --minimal || exit 1' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Verifica serviços' >> /toolkit/run-tests.sh && \\
    echo 'systemctl is-active sshd || systemctl is-active ssh || exit 1' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Teste de módulos individualmente' >> /toolkit/run-tests.sh && \\
    echo 'for m in /toolkit/modules/*.sh; do' >> /toolkit/run-tests.sh && \\
    echo '  echo "Testando \$m..."' >> /toolkit/run-tests.sh && \\
    echo '  \$m || exit 1' >> /toolkit/run-tests.sh && \\
    echo 'done' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo 'echo "Todos os testes passaram com sucesso!"' >> /toolkit/run-tests.sh
EOF
  else
    cat >> "$dockerfile" << EOF
    echo '# Teste de verificação de sintaxe' >> /toolkit/run-tests.sh && \\
    echo 'bash -n /toolkit/modules/${MODULE}.sh' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Teste do módulo específico' >> /toolkit/run-tests.sh && \\
    echo 'echo "Testando ${MODULE}..."' >> /toolkit/run-tests.sh && \\
    echo '/toolkit/modules/${MODULE}.sh || exit 1' >> /toolkit/run-tests.sh && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo '# Verifica serviços' >> /toolkit/run-tests.sh && \\
    case "${MODULE}" in \\
      secure_ssh) \\
        echo 'systemctl is-active sshd || systemctl is-active ssh || exit 1' >> /toolkit/run-tests.sh \\
        ;; \\
      setup_firewall) \\
        echo 'systemctl is-active ufw || systemctl is-active firewalld || iptables -L || exit 1' >> /toolkit/run-tests.sh \\
        ;; \\
      setup_fail2ban) \\
        echo 'systemctl is-active fail2ban || exit 1' >> /toolkit/run-tests.sh \\
        ;; \\
      install_docker) \\
        echo 'systemctl is-active docker || exit 1' >> /toolkit/run-tests.sh \\
        ;; \\
    esac && \\
    echo '' >> /toolkit/run-tests.sh && \\
    echo 'echo "Todos os testes passaram com sucesso!"' >> /toolkit/run-tests.sh
EOF
  fi

  # Finaliza o Dockerfile
  cat >> "$dockerfile" << EOF
# Dá permissão de execução ao script de teste
RUN chmod +x /toolkit/run-tests.sh

# Define o entrypoint como systemd para permitir testes com serviços
ENTRYPOINT ["/usr/sbin/init"]

# Comando para executar os testes
CMD ["/toolkit/run-tests.sh"]
EOF
}

# Função principal
main() {
  # Mostra banner
  echo -e "${BLUE}"
  echo "Toolkit for Servers - Suíte de Testes"
  echo -e "${NC}"

  # Processa argumentos
  while [[ $# -gt 0 ]]; do
    case $1 in
      --distro=*)
        DISTRO="${1#*=}"
        shift
        ;;
      --module=*)
        MODULE="${1#*=}"
        shift
        ;;
      --podman)
        CONTAINER_ENGINE="podman"
        shift
        ;;
      --skip-lint)
        SKIP_LINT=true
        shift
        ;;
      --skip-unit)
        SKIP_UNIT=true
        shift
        ;;
      --skip-integration)
        SKIP_INTEGRATION=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        log "ERROR" "Argumento desconhecido: $1"
        show_help
        exit 1
        ;;
    esac
  done

  # Verifica dependências
  check_dependencies

  # Executa testes
  local lint_result=0
  local unit_result=0
  local integration_result=0

  # Linting
  run_lint_tests
  lint_result=$?

  # Testes unitários
  run_unit_tests
  unit_result=$?

  # Testes de integração
  run_integration_tests
  integration_result=$?

  # Resumo
  echo -e "${BLUE}"
  echo "==============================================="
  echo "          Resumo dos Testes"
  echo "==============================================="
  echo -e "${NC}"

  if [ "$SKIP_LINT" = false ]; then
    if [ $lint_result -eq 0 ]; then
      echo -e "${GREEN}✓ Testes de Linting: PASSARAM${NC}"
    else
      echo -e "${RED}✗ Testes de Linting: FALHARAM${NC}"
    fi
  else
    echo -e "${YELLOW}○ Testes de Linting: IGNORADOS${NC}"
  fi

  if [ "$SKIP_UNIT" = false ]; then
    if [ $unit_result -eq 0 ]; then
      echo -e "${GREEN}✓ Testes Unitários: PASSARAM${NC}"
    else
      echo -e "${RED}✗ Testes Unitários: FALHARAM${NC}"
    fi
  else
    echo -e "${YELLOW}○ Testes Unitários: IGNORADOS${NC}"
  fi

  if [ "$SKIP_INTEGRATION" = false ]; then
    if [ $integration_result -eq 0 ]; then
      echo -e "${GREEN}✓ Testes de Integração: PASSARAM${NC}"
    else
      echo -e "${RED}✗ Testes de Integração: FALHARAM${NC}"
    fi
  else
    echo -e "${YELLOW}○ Testes de Integração: IGNORADOS${NC}"
  fi

  echo -e "${BLUE}"
  echo "==============================================="
  echo -e "${NC}"

  # Status de saída
  if [ $lint_result -eq 0 ] && [ $unit_result -eq 0 ] && [ $integration_result -eq 0 ]; then
    log "INFO" "Todos os testes executados passaram com sucesso!"
    return 0
  else
    log "ERROR" "Alguns testes falharam. Veja o resumo acima."
    return 1
  fi
}

# Executa a função principal passando todos os argumentos
main "$@"
