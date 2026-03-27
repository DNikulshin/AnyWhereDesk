#!/bin/bash
# DDNS — автообновление A-записи в Cloudflare при смене внешнего IP
# Добавляется в cron: */5 * * * * bash ~/guac-stack/scripts/ddns_update.sh
#
# Используется Cloudflare API (поддерживает API Token и Global API Key)
# Настрой переменные ниже или читай из .env

set -euo pipefail

STACK=~/guac-stack
LOG="$STACK/ddns.log"

# ── Читаем переменные из .env ────────────────────────────
if [ -f "$STACK/.env" ]; then
    export $(grep -v '^#' "$STACK/.env" | xargs) 2>/dev/null || true
fi

DOMAIN="${DOMAIN:-}"
CF_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CF_EMAIL="${CLOUDFLARE_EMAIL:-}"
CF_KEY="${CLOUDFLARE_API_KEY:-}"

# ── Проверка конфигурации ────────────────────────────────
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "your-domain.com" ]; then
    echo "$(date): DDNS: DOMAIN не настроен — пропуск" >> "$LOG"
    exit 0
fi

# Определяем метод аутентификации
if [ -n "$CF_TOKEN" ]; then
    AUTH_HEADER="Authorization: Bearer ${CF_TOKEN}"
elif [ -n "$CF_EMAIL" ] && [ -n "$CF_KEY" ]; then
    AUTH_HEADER="X-Auth-Key: ${CF_KEY}"
    EMAIL_HEADER="X-Auth-Email: ${CF_EMAIL}"
else
    echo "$(date): DDNS: Cloudflare API не настроен — пропуск" >> "$LOG"
    exit 0
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# ── Текущий внешний IP ───────────────────────────────────
CURRENT_IP=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
if [ -z "$CURRENT_IP" ]; then
    log "DDNS: не удалось получить внешний IP"
    exit 0
fi

# ── Zone ID ─────────────────────────────────────────────
get_zone_id() {
    local BASE_DOMAIN
    BASE_DOMAIN=$(echo "$DOMAIN" | awk -F'.' '{print $(NF-1)"."$NF}')

    if [ -n "$CF_TOKEN" ]; then
        curl -s --max-time 10 \
            "https://api.cloudflare.com/client/v4/zones?name=${BASE_DOMAIN}" \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            -H "Content-Type: application/json" | python3 -c \
            "import sys,json; data=json.load(sys.stdin); print(data['result'][0]['id'] if data['result'] else '')"
    else
        curl -s --max-time 10 \
            "https://api.cloudflare.com/client/v4/zones?name=${BASE_DOMAIN}" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_KEY}" \
            -H "Content-Type: application/json" | python3 -c \
            "import sys,json; data=json.load(sys.stdin); print(data['result'][0]['id'] if data['result'] else '')"
    fi
}

# ── Record ID и текущий DNS IP ───────────────────────────
get_record() {
    local ZONE_ID="$1"
    if [ -n "$CF_TOKEN" ]; then
        curl -s --max-time 10 \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}" \
            -H "Authorization: Bearer ${CF_TOKEN}" | python3 -c \
            "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id']+'|'+r[0]['content'] if r else '|')"
    else
        curl -s --max-time 10 \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}" \
            -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_KEY}" | python3 -c \
            "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id']+'|'+r[0]['content'] if r else '|')"
    fi
}

# ── Обновление записи ────────────────────────────────────
update_record() {
    local ZONE_ID="$1" RECORD_ID="$2"
    local DATA="{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${CURRENT_IP}\",\"ttl\":60}"
    if [ -n "$CF_TOKEN" ]; then
        curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            -H "Content-Type: application/json" --data "$DATA" > /dev/null
    else
        curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
            -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_KEY}" \
            -H "Content-Type: application/json" --data "$DATA" > /dev/null
    fi
}

# ── Основная логика ──────────────────────────────────────
ZONE_ID=$(get_zone_id)
if [ -z "$ZONE_ID" ]; then
    log "DDNS: Zone ID не найден для $DOMAIN"
    exit 1
fi

RECORD_INFO=$(get_record "$ZONE_ID")
RECORD_ID="${RECORD_INFO%|*}"
DNS_IP="${RECORD_INFO#*|}"

if [ "$CURRENT_IP" = "$DNS_IP" ]; then
    # Без изменений — не пишем в лог (чтобы не захламлять)
    exit 0
fi

log "DDNS: IP изменился $DNS_IP -> $CURRENT_IP. Обновляем..."
update_record "$ZONE_ID" "$RECORD_ID"
log "DDNS: DNS обновлён -> $CURRENT_IP"
