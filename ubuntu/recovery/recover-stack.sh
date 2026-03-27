#!/bin/bash
# =============================================================
# Восстановление стека Guacamole (контейнеры упали)
# Запускать: SSH -> PowerShell -> wsl
#            bash ~/AnyWhereDesk/ubuntu/recovery/recover-stack.sh
# =============================================================
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

step() { echo -e "\n${CYAN}[$(date +%H:%M:%S)] >> $1${NC}"; }
ok()   { echo -e "  ${GREEN}[OK] $1${NC}"; }
warn() { echo -e "  ${YELLOW}[!!] $1${NC}"; }
fail() { echo -e "  ${RED}[XX] $1${NC}"; exit 1; }

STACK=~/guac-stack

echo ""
echo "==========================================="
echo "  AnyWhereDesk | Восстановление стека"
echo "==========================================="

# ── Docker ───────────────────────────────────────────────
step "Проверка Docker daemon..."
if ! docker info &>/dev/null; then
    warn "Docker не запущен — запускаем..."
    sudo service docker start
    sleep 8
    docker info &>/dev/null || fail "Docker не запустился. Проверь WSL."
fi
ok "Docker работает"

# ── Статус до восстановления ─────────────────────────────
step "Статус до восстановления..."
cd "$STACK" 2>/dev/null || fail "~/guac-stack не найден. Запусти stage6-stack.sh"
docker compose ps 2>/dev/null || warn "Не удалось получить статус"

# ── Попытка 1: простой up -d ────────────────────────────
step "Попытка 1: docker compose up -d..."
if docker compose up -d 2>&1; then
    sleep 20
    RUNNING=$(docker compose ps --format '{{.State}}' 2>/dev/null | grep -c '^running$' || echo 0)
    TOTAL=$(docker compose config --services | wc -l)
    if [ "$RUNNING" -eq "$TOTAL" ]; then
        ok "Все контейнеры запущены: $RUNNING/$TOTAL"
        bash ~/AnyWhereDesk/guac-stack/scripts/status.sh
        exit 0
    fi
    warn "Запущено $RUNNING/$TOTAL"
fi

# ── Попытка 2: down + up ─────────────────────────────────
step "Попытка 2: docker compose down && up -d..."
docker compose down --remove-orphans 2>/dev/null || true
sleep 5
docker compose up -d 2>&1
sleep 30

RUNNING=$(docker compose ps --format '{{.State}}' 2>/dev/null | grep -c '^running$' || echo 0)
TOTAL=$(docker compose config --services | wc -l)

if [ "$RUNNING" -eq "$TOTAL" ]; then
    ok "Стек восстановлен: $RUNNING/$TOTAL"
    bash ~/AnyWhereDesk/guac-stack/scripts/status.sh
    exit 0
fi

warn "Запущено $RUNNING/$TOTAL — проверяем логи проблемных контейнеров..."

# ── Диагностика упавших контейнеров ─────────────────────
step "Логи упавших контейнеров..."
docker compose ps --format '{{.Name}} {{.State}}' 2>/dev/null | while read name state; do
    if [ "$state" != "running" ]; then
        echo ""
        echo "  ── Логи $name (последние 20 строк) ──"
        docker compose logs --tail=20 "$name" 2>/dev/null || true
    fi
done

echo ""
echo "==========================================="
echo -e "  ${YELLOW}Автовосстановление не помогло.${NC}"
echo ""
echo "  Следующие шаги диагностики:"
echo "    1. Проблема с БД:    docker compose logs guac-db"
echo "    2. Проблема с Caddy: docker compose logs caddy"
echo "    3. Сброс стека:      bash ~/AnyWhereDesk/ubuntu/recovery/reset-stack.sh"
echo "    4. Восстановление БД из бэкапа:"
echo "       ls ~/guac-stack/backups/"
echo "==========================================="
