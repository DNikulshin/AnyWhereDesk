#!/bin/bash
# Полная проверка здоровья стека Guacamole
# Запускать: bash ~/guac-stack/scripts/status.sh

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK] $1${NC}"; }
warn() { echo -e "  ${YELLOW}[!!] $1${NC}"; }
fail() { echo -e "  ${RED}[XX] $1${NC}"; }

STACK=~/guac-stack

echo ""
echo "==========================================="
echo "  Guacamole Health Check"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

cd "$STACK" 2>/dev/null || { fail "~/guac-stack не найден"; exit 1; }

# ── Контейнеры (FIX#5: правильный парсинг статуса) ──────
echo ""
echo "── Контейнеры ──"
TOTAL=$(docker compose config --services 2>/dev/null | wc -l)
RUNNING=$(docker compose ps --format '{{.State}}' 2>/dev/null | grep -c '^running$' || echo 0)
if [ "$RUNNING" -eq "$TOTAL" ]; then
    ok "Все запущены: $RUNNING/$TOTAL"
else
    warn "Запущено: $RUNNING/$TOTAL"
    docker compose ps 2>/dev/null
fi

# ── PostgreSQL ───────────────────────────────────────────
echo ""
echo "── База данных ──"
if docker exec guac-db pg_isready -U guac_user -d guacamole_db -q 2>/dev/null; then
    ok "PostgreSQL принимает подключения"
else
    fail "PostgreSQL недоступен"
fi

# ── Guacamole HTTP ───────────────────────────────────────
echo ""
echo "── Guacamole HTTP ──"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 5 http://localhost:8080/guacamole/ 2>/dev/null)
case "$HTTP_CODE" in
    200|302) ok "HTTP $HTTP_CODE — отвечает" ;;
    000)     warn "Соединение не установлено (контейнер стартует?)" ;;
    *)       fail "HTTP $HTTP_CODE — неожиданный ответ" ;;
esac

# ── Порты Caddy ──────────────────────────────────────────
echo ""
echo "── Caddy (порты) ──"
for port in 80 443; do
    nc -z localhost "$port" 2>/dev/null && ok "Порт $port открыт" || fail "Порт $port закрыт"
done

# ── SSL-сертификат ───────────────────────────────────────
echo ""
echo "── SSL ──"
DOMAIN=$(grep '^DOMAIN=' "$STACK/.env" 2>/dev/null | cut -d= -f2-)
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "your-domain.com" ]; then
    CERT_EXPIRY=$(echo | openssl s_client -connect "localhost:443" \
        -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$CERT_EXPIRY" ]; then
        ok "Сертификат действует до: $CERT_EXPIRY"
    else
        warn "Сертификат не получен или HTTPS не настроен"
    fi
else
    warn "DOMAIN=your-domain.com (placeholder) — SSL пропущен"
fi

# ── TOTP jar ─────────────────────────────────────────────
echo ""
echo "── TOTP (2FA) ──"
JAR=$(ls "$STACK/extensions/"*.jar 2>/dev/null | head -1)
if [ -n "$JAR" ]; then
    ok "JAR: $(basename "$JAR")"
else
    fail "TOTP jar не найден в extensions/ — 2FA не работает"
fi

# ── Диск ────────────────────────────────────────────────
echo ""
echo "── Дисковое пространство ──"
USED_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
SPACE=$(df -h / | awk 'NR==2 {print $4}')
if [ "$USED_PCT" -lt 80 ]; then
    ok "Свободно: $SPACE (занято ${USED_PCT}%)"
else
    warn "Свободно: $SPACE (занято ${USED_PCT}%) — место заканчивается!"
fi

# ── Последний бэкап ──────────────────────────────────────
echo ""
echo "── Резервные копии ──"
LAST=$(ls -t "$STACK/backups/"*.sql 2>/dev/null | head -1)
if [ -n "$LAST" ]; then
    ok "Последний: $(basename "$LAST")"
else
    warn "Бэкапов не найдено"
fi

echo ""
echo "==========================================="
