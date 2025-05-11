#!/usr/bin/env bash
#
# Funções auxiliares para testes com Bats

# Diretórios de teste
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MODULES_DIR="${REPO_ROOT}/modules"
export FIXTURES_DIR="${REPO_ROOT}/tests/fixtures"

# Função para simular um diretório raiz do sistema
setup_test_root() {
  # Cria um diretório temporário para simular o sistema de arquivos
  export TEST_ROOT="$(mktemp -d)"
  
  # Cria estrutura de diretórios básica
  mkdir -p "${TEST_ROOT}/etc/ssh/sshd_config.d"
  mkdir -p "${TEST_ROOT}/etc/security/limits.d"
  mkdir -p "${TEST_ROOT}/etc/systemd/system"
  mkdir -p "${TEST_ROOT}/var/log"
  mkdir -p "${TEST_ROOT}/usr/local/bin"
  mkdir -p "${TEST_ROOT}/home/testuser/.ssh"
  
  # Define variáveis de ambiente para o teste
  export ORIGINAL_PATH="$PATH"
  export PATH="${TEST_ROOT}/usr/local/bin:$PATH"
  
  # Retorna o caminho do diretório de teste
  echo "$TEST_ROOT"
}

# Função para limpar o ambiente de teste
teardown_test_root() {
  local test_root="$1"
  
  # Restaura o PATH original
  export PATH="$ORIGINAL_PATH"
  
  # Remove o diretório de teste
  rm -rf "$test_root"
}

# Função para criar arquivos de configuração de exemplo
create_sample_config() {
  local test_root="$1"
  local config_type="$2"
  
  case "$config_type" in
    ssh)
      cat > "${test_root}/etc/ssh/sshd_config" << EOF
# Configuração SSH para testes
Port 22
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding yes
EOF
      ;;
    firewall_ufw)
      mkdir -p "${test_root}/etc/ufw"
      cat > "${test_root}/etc/ufw/ufw.conf" << EOF
# Configuração UFW para testes
ENABLED=yes
LOGLEVEL=low
EOF
      ;;
    firewall_firewalld)
      mkdir -p "${test_root}/etc/firewalld"
      cat > "${test_root}/etc/firewalld/firewalld.conf" << EOF
# Configuração FirewallD para testes
DefaultZone=public
EOF
      ;;
    fail2ban)
      mkdir -p "${test_root}/etc/fail2ban"
      cat > "${test_root}/etc/fail2ban/jail.conf" << EOF
# Configuração Fail2Ban para testes
[DEFAULT]
bantime = 600
findtime = 600
maxretry = 5

[sshd]
enabled = true
EOF
      ;;
    sysctl)
      cat > "${test_root}/etc/sysctl.conf" << EOF
# Configuração Sysctl para testes
net.ipv4.tcp_syncookies = 1
vm.swappiness = 60
EOF
      ;;
    *)
      echo "Tipo de configuração desconhecido: $config_type"
      return 1
      ;;
  esac
  
  return 0
}

# Função para simular comandos do sistema
mock_command() {
  local command="$1"
  local exit_status="${2:-0}"
  local output="$3"
  
  # Cria um script para simular o comando
  cat > "${TEST_ROOT}/usr/local/bin/${command}" << EOF
#!/bin/bash
echo "${output}"
exit ${exit_status}
EOF
  
  # Torna o script executável
  chmod +x "${TEST_ROOT}/usr/local/bin/${command}"
}

# Função para simular um arquivo de log
create_sample_log() {
  local test_root="$1"
  local log_file="$2"
  local log_content="$3"
  
  # Cria o diretório pai, se necessário
  mkdir -p "$(dirname "${test_root}${log_file}")"
  
  # Cria o arquivo de log com o conteúdo fornecido
  echo "$log_content" > "${test_root}${log_file}"
}

# Função para simular uma distribuição Linux
mock_os_release() {
  local test_root="$1"
  local distro="$2"
  local version="$3"
  
  # Cria o arquivo os-release
  mkdir -p "${test_root}/etc"
  
  case "$distro" in
    ubuntu)
      cat > "${test_root}/etc/os-release" << EOF
NAME="Ubuntu"
VERSION="$version"
ID=ubuntu
VERSION_ID="$version"
PRETTY_NAME="Ubuntu $version"
EOF
      ;;
    debian)
      cat > "${test_root}/etc/os-release" << EOF
NAME="Debian GNU/Linux"
VERSION="$version"
ID=debian
VERSION_ID="$version"
PRETTY_NAME="Debian GNU/Linux $version"
EOF
      ;;
    centos)
      cat > "${test_root}/etc/os-release" << EOF
NAME="CentOS Linux"
VERSION="$version"
ID="centos"
VERSION_ID="$version"
PRETTY_NAME="CentOS Linux $version"
EOF
      ;;
    almalinux)
      cat > "${test_root}/etc/os-release" << EOF
NAME="AlmaLinux"
VERSION="$version"
ID="almalinux"
VERSION_ID="$version"
PRETTY_NAME="AlmaLinux $version"
EOF
      ;;
    *)
      echo "Distribuição desconhecida: $distro"
      return 1
      ;;
  esac
  
  return 0
}

# Função para simular hardware
mock_hardware() {
  local test_root="$1"
  local cpu_cores="${2:-4}"
  local memory_gb="${3:-8}"
  local is_ssd="${4:-true}"
  
  # Cria diretórios necessários
  mkdir -p "${test_root}/proc"
  
  # Simula informações de CPU
  mkdir -p "${test_root}/proc/cpuinfo"
  for ((i=0; i<cpu_cores; i++)); do
    echo "processor : $i" >> "${test_root}/proc/cpuinfo"
    echo "model name : Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz" >> "${test_root}/proc/cpuinfo"
    echo "physical id : 0" >> "${test_root}/proc/cpuinfo"
    echo "" >> "${test_root}/proc/cpuinfo"
  done
  
  # Simula informações de memória
  local memory_kb=$((memory_gb * 1024 * 1024))
  cat > "${test_root}/proc/meminfo" << EOF
MemTotal:       ${memory_kb} kB
MemFree:        $((memory_kb / 2)) kB
MemAvailable:   $((memory_kb / 2)) kB
EOF
  
  # Simula informações de armazenamento
  mkdir -p "${test_root}/sys/block/sda"
  if [ "$is_ssd" = true ]; then
    echo "0" > "${test_root}/sys/block/sda/queue/rotational"
  else
    echo "1" > "${test_root}/sys/block/sda/queue/rotational"
  fi
  
  return 0
}

# Função para capturar e analisar a saída dos scripts
assert_output_contains() {
  local output="$1"
  local expected="$2"
  
  if [[ "$output" != *"$expected"* ]]; then
    echo "Falha: Saída não contém '$expected'"
    echo "Saída recebida:"
    echo "$output"
    return 1
  fi
  
  return 0
}

# Função para verificar se um arquivo existe e tem o conteúdo esperado
assert_file_contains() {
  local file="$1"
  local expected="$2"
  
  if [ ! -f "$file" ]; then
    echo "Falha: Arquivo '$file' não existe"
    return 1
  fi
  
  if ! grep -q "$expected" "$file"; then
    echo "Falha: Arquivo '$file' não contém '$expected'"
    echo "Conteúdo do arquivo:"
    cat "$file"
    return 1
  fi
  
  return 0
}

# Função para verificar se uma configuração foi aplicada
assert_config_applied() {
  local test_root="$1"
  local config_type="$2"
  local expected_setting="$3"
  
  case "$config_type" in
    ssh)
      assert_file_contains "${test_root}/etc/ssh/sshd_config.d/00-security.conf" "$expected_setting"
      ;;
    firewall_ufw)
      assert_file_contains "${test_root}/etc/ufw/user.rules" "$expected_setting"
      ;;
    fail2ban)
      assert_file_contains "${test_root}/etc/fail2ban/jail.local" "$expected_setting"
      ;;
    sysctl)
      assert_file_contains "${test_root}/etc/sysctl.d/99-toolkit-performance.conf" "$expected_setting"
      ;;
    *)
      echo "Tipo de configuração desconhecido: $config_type"
      return 1
      ;;
  esac
  
  return 0
}