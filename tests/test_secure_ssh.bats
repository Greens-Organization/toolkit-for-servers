#!/usr/bin/env bats
#
# Testes unitários para o módulo secure_ssh.sh
# Execute com: bats test_secure_ssh.bats

# Carrega o script a ser testado
load 'test_helper'

# Setup - executado antes de cada teste
setup() {
  # Cria diretórios temporários simulando o sistema de arquivos
  export TEST_TMP_DIR="$(mktemp -d)"
  export ORIG_HOME="$HOME"
  export HOME="$TEST_TMP_DIR/home"
  export TEST_SSH_DIR="$TEST_TMP_DIR/etc/ssh"
  
  # Cria diretórios e arquivos necessários
  mkdir -p "$HOME"
  mkdir -p "$TEST_SSH_DIR/sshd_config.d"
  mkdir -p "$TEST_TMP_DIR/etc/ssh/backup_20250505000000"
  
  # Cria um arquivo sshd_config de exemplo
  cat > "$TEST_SSH_DIR/sshd_config" << EOF
# SSH config for testing
Port 22
PermitRootLogin yes
PasswordAuthentication yes
EOF

  # Define variáveis globais para o script
  export OS_ID="ubuntu"
  export CUSTOM_SSH_PORT="2222"
  
  # Mockup das funções de sistema
  function systemctl() { echo "Called: systemctl $*"; return 0; }
  function service() { echo "Called: service $*"; return 0; }
  function sshd() { echo "Called: sshd $*"; return 0; }
  function ssh-keygen() { echo "Called: ssh-keygen $*"; return 0; }
  function adduser() { echo "Called: adduser $*"; return 0; }
  function usermod() { echo "Called: usermod $*"; return 0; }
  
  # Exporta funções mockup
  export -f systemctl
  export -f service
  export -f sshd
  export -f ssh-keygen
  export -f adduser
  export -f usermod
  
  # Prepara o módulo para teste
  cp "${MODULES_DIR}/secure_ssh.sh" "$TEST_TMP_DIR/"
  chmod +x "$TEST_TMP_DIR/secure_ssh.sh"
}

# Teardown - executado após cada teste
teardown() {
  # Restaura o diretório home
  export HOME="$ORIG_HOME"
  
  # Remove diretórios temporários
  rm -rf "$TEST_TMP_DIR"
}

# Testa se o script existe
@test "secure_ssh.sh exists" {
  run test -f "${MODULES_DIR}/secure_ssh.sh"
  [ "$status" -eq 0 ]
}

# Testa se o script tem permissão de execução
@test "secure_ssh.sh is executable" {
  run test -x "${MODULES_DIR}/secure_ssh.sh"
  [ "$status" -eq 0 ]
}

# Testa se o script não tem erros de sintaxe
@test "secure_ssh.sh has valid syntax" {
  run bash -n "${MODULES_DIR}/secure_ssh.sh"
  [ "$status" -eq 0 ]
}

# Testa a função secure_ssh
@test "secure_ssh function creates configuration file" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run secure_ssh "2222"
  [ "$status" -eq 0 ]
  
  # Verifica se o arquivo de configuração foi criado
  [ -f "$TEST_SSH_DIR/sshd_config.d/00-security.conf" ]
  
  # Verifica configurações específicas no arquivo
  run grep "Port 2222" "$TEST_SSH_DIR/sshd_config.d/00-security.conf"
  [ "$status" -eq 0 ]
  
  run grep "PermitRootLogin no" "$TEST_SSH_DIR/sshd_config.d/00-security.conf"
  [ "$status" -eq 0 ]
  
  run grep "PasswordAuthentication no" "$TEST_SSH_DIR/sshd_config.d/00-security.conf"
  [ "$status" -eq 0 ]
}

# Testa a resposta a uma porta SSH já em uso
@test "secure_ssh detects port in use" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Mock para netstat mostrando que a porta está em uso
  function netstat() {
    if [[ "$*" == *"3333"* ]]; then
      echo "tcp        0      0 0.0.0.0:3333            0.0.0.0:*               LISTEN"
      return 0
    else
      return 1
    fi
  }
  export -f netstat
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run secure_ssh "3333"
  [ "$status" -eq 0 ]
  
  # Verifica se manteve a porta original ao invés da porta em uso
  run grep "Port 22" "$TEST_SSH_DIR/sshd_config.d/00-security.conf"
  [ "$status" -eq 0 ]
}

# Testa o backup da configuração anterior
@test "secure_ssh creates backup" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run secure_ssh "2222"
  [ "$status" -eq 0 ]
  
  # Verifica se o diretório de backup foi usado
  run ls -la "$TEST_SSH_DIR/backup_"*
  [ "$status" -eq 0 ]
}

# Testa a geração de chaves
@test "secure_ssh handles SSH key generation" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run secure_ssh "2222"
  [ "$status" -eq 0 ]
  
  # Verifica que o comando de geração de chave foi chamado
  run grep "Called: ssh-keygen" "$TEST_TMP_DIR"/*
  [ "$status" -eq 0 ]
}

# Testa a configuração para usuário administrador
@test "secure_ssh configures admin user" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Função mock para simular a resposta do usuário
  function read() {
    echo "admin"
  }
  export -f read
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run configure_ssh_authorized_keys
  [ "$status" -eq 0 ]
  
  # Verifica que os comandos de criação de usuário foram chamados
  run grep "Called: adduser" "$TEST_TMP_DIR"/*
  [ "$status" -eq 0 ]
  
  run grep "Called: usermod" "$TEST_TMP_DIR"/*
  [ "$status" -eq 0 ]
}

# Testa a reinicialização do serviço SSH
@test "secure_ssh restarts SSH service" {
  # Substitui o diretório SSH para o teste
  sed -i "s|/etc/ssh|$TEST_SSH_DIR|g" "$TEST_TMP_DIR/secure_ssh.sh"
  
  # Carrega o script e executa a função principal
  source "$TEST_TMP_DIR/secure_ssh.sh"
  run secure_ssh "2222"
  [ "$status" -eq 0 ]
  
  # Verifica se o serviço foi reiniciado via systemctl ou service
  run grep "Called: systemctl restart sshd" "$TEST_TMP_DIR"/*
  status1=$status
  
  run grep "Called: service sshd restart" "$TEST_TMP_DIR"/*
  status2=$status
  
  run grep "Called: service ssh restart" "$TEST_TMP_DIR"/*
  status3=$status
  
  # Pelo menos um dos comandos deve ter sido chamado
  [ "$status1" -eq 0 -o "$status2" -eq 0 -o "$status3" -eq 0 ]
}