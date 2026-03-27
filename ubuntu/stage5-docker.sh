#!/bin/bash
# =============================================================
# Stage 5 / 6 — Установка Docker Engine в WSL Ubuntu (headless)
# Запускать: SSH -> PowerShell -> wsl
#            bash ~/AnyWhereDesk/ubuntu/stage5-docker.sh
# Идемпотентен — безопасно запускать повторно
# =============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

step()  { echo -e "\n${CYAN}[$(date +%H:%M:%S)] >> $1${NC}"; }
ok()    { echo -e "  ${GREEN}[OK] $1${NC}"; }
warn()  { echo -e "  ${YELLOW}[!!] $1${NC}"; }
fail()  { echo -e "  ${RED}[XX] $1${NC}"; exit 1; }

echo ""
echo "==========================================="
echo "  AnyWhereDesk | Stage 5 — Docker Engine"
echo "==========================================="

# ── Проверка: Docker уже установлен? ────────────────────
step "Проверка Docker..."
if command -v docker &>/dev/null && docker --version &>/dev/null; then
    ok "Docker уже установлен: $(docker --version)"
    if docker compose version &>/dev/null; then
        ok "Docker Compose: $(docker compose version)"
    fi
    warn "Если нужна переустановка — удали вручную: sudo apt remove docker-ce docker-ce-cli"
    echo ""
    echo "  Следующий шаг: bash ~/AnyWhereDesk/ubuntu/stage6-stack.sh"
    exit 0
fi
ok "Docker не найден — начинаем установку"

# ── Обновление пакетов ───────────────────────────────────
step "Обновление apt..."
sudo apt-get update -qq
ok "apt обновлён"

# ── Зависимости ─────────────────────────────────────────
step "Установка зависимостей..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl gnupg lsb-release
ok "Зависимости установлены"

# ── GPG ключ Docker ──────────────────────────────────────
step "Добавление GPG-ключа Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    ok "GPG-ключ добавлен"
else
    warn "GPG-ключ уже существует"
fi

# ── Репозиторий Docker ───────────────────────────────────
step "Добавление репозитория Docker..."
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    ok "Репозиторий добавлен"
else
    warn "Репозиторий уже существует"
fi

# ── Установка Docker Engine ──────────────────────────────
step "Установка Docker Engine + Compose plugin..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
ok "Docker Engine установлен"

# ── Добавление пользователя в группу docker ─────────────
step "Добавление $(whoami) в группу docker..."
if groups | grep -q docker; then
    warn "Пользователь уже в группе docker"
else
    sudo usermod -aG docker "$USER"
    ok "Пользователь добавлен в группу docker"
fi

# ── Запуск Docker ────────────────────────────────────────
step "Запуск Docker daemon..."
sudo service docker start
sleep 3

# Применяем группу без перелогина (newgrp создаёт subshell — используем sg)
if ! docker info &>/dev/null; then
    warn "Docker не отвечает без sudo. Применяем группу..."
    sudo docker info &>/dev/null && ok "Docker работает (через sudo)"
else
    ok "Docker работает"
fi

# ── Версии ───────────────────────────────────────────────
step "Проверка версий..."
ok "Docker: $(docker --version 2>/dev/null || sudo docker --version)"
ok "Compose: $(docker compose version 2>/dev/null || sudo docker compose version)"

# ── Тест ────────────────────────────────────────────────
step "Быстрый тест (hello-world)..."
if sudo docker run --rm hello-world 2>&1 | grep -q "Hello from Docker!"; then
    ok "hello-world: успешно"
else
    warn "hello-world не прошёл — возможно нет доступа к Docker Hub"
fi

echo ""
echo "==========================================="
echo -e "  ${GREEN}Stage 5 завершён! Docker установлен.${NC}"
echo ""
echo "  ВАЖНО: для применения группы docker"
echo "  без sudo — выйди и зайди снова в WSL:"
echo "    exit  (из wsl)"
echo "    wsl   (снова)"
echo ""
echo "  Следующий шаг:"
echo "    bash ~/AnyWhereDesk/ubuntu/stage6-stack.sh"
echo "==========================================="
