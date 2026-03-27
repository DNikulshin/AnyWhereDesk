#!/bin/bash
# Обновление стека Guacamole (образы + пересборка Caddy)
# Запускать: bash ~/guac-stack/scripts/update.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

step() { echo -e "\n${CYAN}[$(date +%H:%M:%S)] >> $1${NC}"; }
ok()   { echo -e "  ${GREEN}[OK] $1${NC}"; }
warn() { echo -e "  ${YELLOW}[!!] $1${NC}"; }

STACK=~/guac-stack
cd "$STACK"

echo ""
echo "==========================================="
echo "  Guacamole Stack Update"
echo "==========================================="

# ── Бэкап перед обновлением ──────────────────────────────
step "Бэкап БД перед обновлением..."
bash "$STACK/scripts/backup.sh" || { warn "Бэкап не удался — обновление прервано"; exit 1; }

# ── Скачиваем новые образы ───────────────────────────────
step "Загрузка новых образов..."
docker compose pull

# ── Пересборка Caddy (на случай обновления плагина) ──────
step "Пересборка Caddy с --no-cache..."
docker compose build --no-cache caddy

# ── Перезапуск ───────────────────────────────────────────
step "Перезапуск стека..."
docker compose up -d --remove-orphans

# ── Очистка старых образов ───────────────────────────────
step "Очистка неиспользуемых образов..."
docker image prune -f

# ── Проверка ─────────────────────────────────────────────
step "Проверка после обновления..."
sleep 20
bash "$STACK/scripts/status.sh"

echo ""
echo "==========================================="
echo -e "  ${GREEN}Обновление завершено${NC}"
echo "==========================================="
