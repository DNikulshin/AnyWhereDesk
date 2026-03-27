#!/bin/bash
# Резервное копирование БД Guacamole
# Запускать вручную: bash ~/guac-stack/scripts/backup.sh
# Или автоматически из cron (настраивается в stage6-stack.sh)

set -euo pipefail

STACK=~/guac-stack
BACKUP_DIR="$STACK/backups"
FILENAME="guac_db_$(date +%Y-%m-%d_%H-%M).sql"
LOG_FILE="$STACK/backup.log"

# Опциональные уведомления Telegram (заполни в .env)
TG_TOKEN="${TG_TOKEN:-}"
TG_CHAT="${TG_CHAT:-}"

mkdir -p "$BACKUP_DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }

log "Бэкап начат: $FILENAME"

# ── Проверка что БД доступна ─────────────────────────────
if ! docker exec guac-db pg_isready -U guac_user -d guacamole_db -q 2>/dev/null; then
    log "ОШИБКА: PostgreSQL недоступен"
    [ -n "$TG_TOKEN" ] && curl -s \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT}&text=Guacamole backup FAILED: DB unavailable" > /dev/null
    exit 1
fi

# ── Дамп ─────────────────────────────────────────────────
docker exec guac-db pg_dump -U guac_user guacamole_db > "$BACKUP_DIR/$FILENAME"
SIZE=$(du -sh "$BACKUP_DIR/$FILENAME" | cut -f1)
log "OK: $FILENAME ($SIZE)"

# ── Уведомление Telegram ─────────────────────────────────
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
    curl -s "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT}&text=Guacamole backup OK: ${FILENAME} (${SIZE})" > /dev/null
fi

# ── Очистка старых бэкапов (старше 30 дней) ─────────────
DELETED=$(find "$BACKUP_DIR" -name '*.sql' -mtime +30 -print -delete | wc -l)
[ "$DELETED" -gt 0 ] && log "Удалено старых бэкапов: $DELETED"

log "Бэкап завершён"
