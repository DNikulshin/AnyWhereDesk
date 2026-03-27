#!/bin/bash
# =============================================================
# Полный сброс стека Guacamole (ДЕСТРУКТИВНАЯ операция)
# Удаляет контейнеры + базу данных. Бэкап создаётся автоматически.
# Запускать: SSH -> PowerShell -> wsl
#            bash ~/AnyWhereDesk/ubuntu/recovery/reset-stack.sh
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
echo -e "  ${RED}AnyWhereDesk | ПОЛНЫЙ СБРОС СТЕКА${NC}"
echo "==========================================="
echo ""
echo -e "  ${RED}!! ВНИМАНИЕ: это удалит базу данных Guacamole !!${NC}"
echo "  Все подключения, пользователи, настройки будут удалены."
echo "  Бэкап БД будет создан АВТОМАТИЧЕСКИ перед сбросом."
echo ""
read -rp "  Продолжить? Введи 'RESET' для подтверждения: " CONFIRM
if [ "$CONFIRM" != "RESET" ]; then
    echo "  Отменено."
    exit 0
fi

cd "$STACK" 2>/dev/null || fail "~/guac-stack не найден"

# ── Бэкап перед сбросом ──────────────────────────────────
step "Создание бэкапа БД перед сбросом..."
if docker exec guac-db pg_isready -U guac_user -d guacamole_db -q 2>/dev/null; then
    BACKUP_FILE="$STACK/backups/pre-reset_$(date +%Y-%m-%d_%H-%M).sql"
    mkdir -p "$STACK/backups"
    docker exec guac-db pg_dump -U guac_user guacamole_db > "$BACKUP_FILE"
    ok "Бэкап: $BACKUP_FILE"
else
    warn "БД недоступна — бэкап пропущен"
fi

# ── Остановка и удаление контейнеров ────────────────────
step "Остановка и удаление контейнеров..."
docker compose down --remove-orphans --volumes 2>/dev/null || true
ok "Контейнеры удалены"

# ── Очистка данных БД ────────────────────────────────────
step "Очистка данных PostgreSQL..."
if [ -d "$STACK/dbdata" ]; then
    rm -rf "$STACK/dbdata"
    ok "dbdata удалён"
fi

# ── Пересоздание схемы ───────────────────────────────────
step "Пересоздание схемы БД..."
rm -f "$STACK/init/initdb.sql"
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql \
    > "$STACK/init/initdb.sql"
ok "Схема пересоздана"

# ── Запуск стека ────────────────────────────────────────
step "Запуск свежего стека..."
docker compose up -d
ok "Стек запущен"

step "Ожидание готовности (45 сек)..."
sleep 45
bash ~/AnyWhereDesk/guac-stack/scripts/status.sh

echo ""
echo "==========================================="
echo -e "  ${GREEN}Сброс завершён. Стек пересоздан.${NC}"
echo ""
echo "  Первый вход: guacadmin / guacadmin"
echo "  СРАЗУ смени пароль!"
echo ""
echo "  Бэкапы сохранены в: ~/guac-stack/backups/"
echo "==========================================="
