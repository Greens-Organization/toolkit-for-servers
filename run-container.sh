#!/usr/bin/env bash
#
# Script para executar containers de teste para o Toolkit for Servers
# Uso: ./run-container.sh [ubuntu|debian|almalinux] [--build]
#

set -e

# Cores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker"

# Variáveis
CONTAINER_ENGINE="docker"
BUILD=false
OS_NAME=""
CONTAINER_NAME=""

# Mensagem de ajuda
usage() {
    echo -e "${BLUE}Toolkit for Servers - Execução de Containers de Teste${NC}"
    echo
    echo "Uso: $0 [OS] [OPÇÕES]"
    echo
    echo "Onde [OS] é uma das seguintes distribuições:"
    echo "  ubuntu    - Ubuntu 22.04"
    echo "  debian    - Debian 12"
    echo "  almalinux - AlmaLinux 9"
    echo
    echo "Opções:"
    echo "  --build   - Força a construção da imagem antes de executar"
    echo "  --podman  - Usa Podman em vez de Docker"
    echo "  --help    - Mostra esta mensagem de ajuda"
    echo
    echo "Exemplos:"
    echo "  $0 ubuntu            # Executa container Ubuntu"
    echo "  $0 almalinux --build    # Constrói e executa container AlmaLinux"
    echo
    exit 1
}

# Verifica argumentos
if [ $# -lt 1 ]; then
    usage
fi

# Processa argumentos
for arg in "$@"; do
    case $arg in
        ubuntu|debian|almalinux)
            OS_NAME=$arg
            ;;
        --build)
            BUILD=true
            ;;
        --podman)
            CONTAINER_ENGINE="podman"
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Argumento desconhecido: $arg${NC}"
            usage
            ;;
    esac
done

# Configura variáveis baseadas no sistema operacional
case $OS_NAME in
    ubuntu)
        OS_VERSION="22.04"
        DOCKERFILE="${DOCKER_DIR}/ubuntu-22.04.Dockerfile"
        ;;
    debian)
        OS_VERSION="12"
        DOCKERFILE="${DOCKER_DIR}/debian-12.Dockerfile"
        ;;
    almalinux)
        OS_VERSION="9"
        DOCKERFILE="${DOCKER_DIR}/almalinux-9.Dockerfile"
        ;;
    *)
        echo -e "${RED}Sistema operacional não especificado ou não suportado.${NC}"
        usage
        ;;
esac

# Nome do container
CONTAINER_NAME="toolkit-test-${OS_NAME}-${OS_VERSION}"
IMAGE_NAME="${CONTAINER_NAME}-image"

# Verifica se o Docker/Podman está instalado
if ! command -v $CONTAINER_ENGINE &> /dev/null; then
    echo -e "${RED}$CONTAINER_ENGINE não encontrado. Por favor, instale-o primeiro.${NC}"
    exit 1
fi

# Verifica se o Dockerfile existe
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}Dockerfile não encontrado: $DOCKERFILE${NC}"
    exit 1
fi

# Constrói a imagem se necessário
if [ "$BUILD" = true ] || ! $CONTAINER_ENGINE image ls | grep -q "$IMAGE_NAME"; then
    echo -e "${BLUE}Construindo imagem $IMAGE_NAME...${NC}"
    $CONTAINER_ENGINE build -t "$IMAGE_NAME" -f "$DOCKERFILE" .
fi

# Para e remove container se já existir
if $CONTAINER_ENGINE ps -a | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}Container $CONTAINER_NAME já existe. Parando e removendo...${NC}"
    $CONTAINER_ENGINE stop "$CONTAINER_NAME" 2>/dev/null || true
    $CONTAINER_ENGINE rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Executa o container
echo -e "${GREEN}Iniciando container $CONTAINER_NAME...${NC}"
$CONTAINER_ENGINE run --name "$CONTAINER_NAME" \
    --privileged \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	--tmpfs /tmp \
    -v "${SCRIPT_DIR}/install.sh:/toolkit/install.sh" \
    -v "${SCRIPT_DIR}/modules:/toolkit/modules" \
    -v "${SCRIPT_DIR}/tests:/toolkit/tests" \
    -d "$IMAGE_NAME"

echo -e "${GREEN}Container $CONTAINER_NAME iniciado!${NC}"
echo -e "${BLUE}Use os seguintes comandos para interagir com o container:${NC}"
echo -e "  ${YELLOW}$CONTAINER_ENGINE exec -it $CONTAINER_NAME bash${NC}     # Acessar shell"
echo -e "  ${YELLOW}$CONTAINER_ENGINE stop $CONTAINER_NAME${NC}              # Parar container"
echo -e "  ${YELLOW}$CONTAINER_ENGINE start $CONTAINER_NAME${NC}             # Iniciar container novamente"
echo -e "  ${YELLOW}$CONTAINER_ENGINE rm -f $CONTAINER_NAME${NC}             # Remover container"
echo -e "  ${YELLOW}$CONTAINER_ENGINE logs $CONTAINER_NAME${NC}              # Ver logs"

# Acessa o container
echo -e "${BLUE}Acessando o shell do container...${NC}"
$CONTAINER_ENGINE exec -it "$CONTAINER_NAME" bash
