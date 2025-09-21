#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Проверка, что скрипт запущен с правами root или через sudo
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Проверка дистрибутива и версии
if ! grep -qi "ubuntu" /etc/os-release; then
    error "This script is designed for Ubuntu. Other distributions are not supported."
fi

UBUNTU_VERSION=$(lsb_release -rs)
if [[ ! "$UBUNTU_VERSION" =~ ^(24\.04|22\.04|20\.04) ]]; then
    error "This script supports Ubuntu 20.04, 22.04, or 24.04. Detected version: $UBUNTU_VERSION"
fi

# Проверка наличия необходимых команд
for cmd in curl lsb_release dpkg; do
    if ! command -v $cmd &>/dev/null; then
        error "Required command '$cmd' is not installed. Please install it first."
    fi
done

# Проверка, установлен ли Docker
if command -v docker &>/dev/null && docker version &>/dev/null; then
    log "Docker is already installed. Version: $(docker --version)"
    log "Docker Compose version: $(docker compose version 2>/dev/null || echo 'Not installed')"
    exit 0
fi

# Удаление конфликтующих пакетов
log "Removing conflicting packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y $pkg 2>/dev/null || true
done

# Установка необходимых зависимостей
log "Installing prerequisites..."
apt-get update || error "Failed to update apt cache"
apt-get install -y ca-certificates curl gnupg || error "Failed to install prerequisites"

# Создание директории для ключей
log "Setting up Docker's GPG key..."
install -m 0755 -d /etc/apt/keyrings || error "Failed to create /etc/apt/keyrings"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || error "Failed to download Docker GPG key"
chmod 0644 /etc/apt/keyrings/docker.asc || error "Failed to set permissions for GPG key"

# Добавление репозитория Docker
log "Adding Docker APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  noble stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null || error "Failed to add Docker repository"
apt-get update || error "Failed to update apt cache after adding Docker repository"

# Установка Docker и плагинов
log "Installing Docker packages..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Failed to install Docker packages"

# Очистка кэша APT
log "Cleaning up APT cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Добавление пользователя в группу docker
log "Adding current user to docker group..."
usermod -aG docker ${SUDO_USER:-$USER} || error "Failed to add user to docker group"

# Проверка установки Docker
log "Verifying Docker installation..."
if ! docker run --rm hello-world &>/dev/null; then
    error "Docker installation verification failed. Check 'docker info' or logs for details."
fi
log "Docker is installed and working correctly! Version: $(docker --version)"

# Проверка Docker Compose
log "Verifying Docker Compose installation..."
if ! docker compose version &>/dev/null; then
    error "Docker Compose plugin is not installed correctly."
fi
log "Docker Compose version: $(docker compose version)"

# Уведомление о необходимости перезапуска сессии
log "Docker is installed. To use Docker without sudo, run 'newgrp docker' or log out and log back in."

exit 0
