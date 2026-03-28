#!/bin/bash
# =============================================================
# Stage 6 / 6 — Развёртывание guac-stack (первый запуск)
# Запускать: SSH -> PowerShell -> wsl
#            bash ~/AnyWhereDesk/ubuntu/stage6-stack.sh
# Идемпотентен — безопасно запускать повторно
# =============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

step()  { echo -e "\n${CYAN}[$(date +%H:%M:%S)] >> $1${NC}"; }
ok()    { echo -e "  ${GREEN}[OK] $1${NC}"; }
warn()  { echo -e "  ${YELLOW}[!!] $1${NC}"; }
fail()  { echo -e "  ${RED}[XX] $1${NC}"; exit 1; }

# Путь к исходникам (через символическую ссылку из stage3)
SRC=~/AnyWhereDesk/guac-stack
DEST=~/guac-stack

echo ""
echo "==========================================="
echo "  AnyWhereDesk | Stage 6 — Guac Stack"
echo "==========================================="

# ── Проверка Docker ──────────────────────────────────────
step "Проверка Docker..."
if ! docker info &>/dev/null; then
    warn "Docker не запущен — запускаем..."
    sudo service docker start
    sleep 5
    docker info &>/dev/null || fail "Docker не запустился. Запусти stage5-docker.sh"
fi
ok "Docker работает"

# ── Проверка источника ───────────────────────────────────
step "Проверка исходных файлов..."
if [ ! -d "$SRC" ]; then
    fail "Папка $SRC не найдена. Проверь ссылку ~/AnyWhereDesk -> stage3-wsl-configure.ps1"
fi
ok "Источник: $SRC"

# ── Копирование файлов в Linux FS ────────────────────────
# ВАЖНО: Docker работает значительно быстрее с файлами в Linux FS (~/)
# чем с файлами на Windows mount (/mnt/c/...)
step "Копирование файлов в Linux filesystem: $DEST..."
mkdir -p "$DEST"

# Копируем конфиги (не перезаписываем .env если уже существует)
for f in docker-compose.yml Dockerfile.caddy Caddyfile; do
    if [ -f "$SRC/$f" ]; then
        cp "$SRC/$f" "$DEST/$f"
        ok "Скопирован: $f"
    else
        warn "Не найден в источнике: $f (проверь guac-stack/)"
    fi
done

# .env — приоритет: $SRC/.env (боевой) > $DEST/.env (существующий) > $SRC/.env.example
if [ -f "$SRC/.env" ]; then
    cp "$SRC/.env" "$DEST/.env"
    ok ".env скопирован из исходников (guac-stack/.env)"
elif [ ! -f "$DEST/.env" ]; then
    if [ -f "$SRC/.env.example" ]; then
        cp "$SRC/.env.example" "$DEST/.env"
        warn ".env создан из .env.example — ЗАПОЛНИ ПАРОЛИ перед запуском!"
    else
        warn ".env не найден. Создай $DEST/.env вручную (см. .env.example)"
    fi
else
    ok ".env уже существует — не перезаписываем"
fi

# Копируем скрипты
mkdir -p "$DEST/scripts"
for f in status.sh backup.sh update.sh ddns_update.sh; do
    [ -f "$SRC/scripts/$f" ] && cp "$SRC/scripts/$f" "$DEST/scripts/$f" && chmod +x "$DEST/scripts/$f"
done
ok "Скрипты скопированы"

# ── Проверка .env ────────────────────────────────────────
step "Проверка .env..."
if [ ! -f "$DEST/.env" ]; then
    fail ".env не найден: $DEST/.env\nСоздай файл и заполни DB_PASSWORD и DOMAIN"
fi

# Проверяем что пароли не placeholder
DB_PWD=$(grep '^DB_PASSWORD=' "$DEST/.env" | cut -d= -f2- || true)
CF_TOKEN=$(grep '^CLOUDFLARE_API_TOKEN=' "$DEST/.env" | cut -d= -f2- || true)
DOMAIN_VAL=$(grep '^DOMAIN=' "$DEST/.env" | cut -d= -f2- || true)

if [ -z "$DB_PWD" ] || [ "$DB_PWD" = "ЗАМЕНИТЕ_НА_СЛОЖНЫЙ_ПАРОЛЬ" ]; then
    fail "DB_PASSWORD не заполнен в .env"
fi
if [ -z "$CF_TOKEN" ]; then
    warn "CLOUDFLARE_API_TOKEN не задан — SSL через HTTP-01 (нужны открытые порты 80/443)"
else
    ok "CLOUDFLARE_API_TOKEN: установлен (DNS-01 challenge)"
fi
if [ -z "$DOMAIN_VAL" ] || [ "$DOMAIN_VAL" = "your-domain.com" ]; then
    warn "DOMAIN=your-domain.com (placeholder) — SSL не будет работать до замены"
fi

ok "DB_PASSWORD: установлен"
ok "DOMAIN: $DOMAIN_VAL"

# ── Создание директорий стека ────────────────────────────
step "Создание директорий стека..."
mkdir -p "$DEST"/{init,dbdata,caddy/data,caddy/config,recordings,shared_files,backups,extensions}
ok "Директории созданы"

# ── Скачивание TOTP jar ──────────────────────────────────
step "Проверка TOTP расширения..."
GUAC_VERSION="1.5.5"
JAR_FILE="$DEST/extensions/guacamole-auth-totp-${GUAC_VERSION}.jar"

if [ -f "$JAR_FILE" ]; then
    ok "TOTP jar уже существует: $JAR_FILE"
else
    warn "Скачивание TOTP jar (версия $GUAC_VERSION)..."
    TOTP_URLS=(
        "https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-auth-totp-${GUAC_VERSION}.tar.gz"
        "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-auth-totp-${GUAC_VERSION}.tar.gz"
    )
    TOTP_OK=false
    for url in "${TOTP_URLS[@]}"; do
        if curl -fsSL "$url" \
            | tar xz --wildcards --strip-components=1 -C "$DEST/extensions/" '*/guacamole-auth-totp-*.jar' 2>/dev/null; then
            ok "TOTP jar скачан из: $url"
            TOTP_OK=true
            break
        fi
    done
    if [ "$TOTP_OK" = false ]; then
        warn "Не удалось скачать TOTP jar — 2FA не будет работать"
        warn "Скачай вручную: https://guacamole.apache.org/releases/${GUAC_VERSION}/"
    fi
fi

# ── Генерация схемы БД ───────────────────────────────────
step "Генерация схемы PostgreSQL..."
if [ ! -f "$DEST/init/initdb.sql" ]; then
    echo "  Генерация из образа guacamole/guacamole..."
    docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql \
        > "$DEST/init/initdb.sql"
    ok "Схема создана: init/initdb.sql"
else
    ok "Схема уже существует — пропускаем"
fi

# ── Сборка Caddy с Cloudflare плагином ──────────────────
step "Сборка Caddy с Cloudflare DNS-challenge плагином..."
warn "Первая сборка займёт 2-4 минуты..."
cd "$DEST"
docker compose build caddy
ok "Caddy собран"

# ── Запуск стека ────────────────────────────────────────
step "Запуск стека (docker compose up -d)..."
docker compose up -d
ok "Стек запущен"

# ── Ожидание готовности ──────────────────────────────────
step "Ожидание готовности контейнеров (45 сек)..."
echo "  Postgres инициализирует схему — это нормально занимает 20-40 сек"
sleep 45

# ── Финальная проверка ───────────────────────────────────
step "Проверка состояния стека..."
bash "$DEST/scripts/status.sh"

echo ""
echo "==========================================="
echo -e "  ${GREEN}Stage 6 завершён!${NC}"
echo ""
echo "  Первый вход:"
echo "    http://localhost:8080/guacamole/"
echo "    Логин: guacadmin / guacadmin"
echo "    СРАЗУ смени пароль в Settings -> Users"
echo ""
echo "  После настройки DNS — запусти автозапуск:"
echo "    (PowerShell) .\windows\stage4-autostart.ps1 -WSLUser $USER"
echo "==========================================="
