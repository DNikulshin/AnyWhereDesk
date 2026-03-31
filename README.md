# AnyWhereDesk

Удалённый доступ к Windows через браузер — без клиентов, без VPN, с 2FA.

**Стек:** Apache Guacamole · PostgreSQL · Caddy · Docker · WSL2

```
Браузер (любой, любая сеть)
       │ HTTPS
       ▼
  Caddy (SSL / Let's Encrypt)
       │
       ▼
  Guacamole (Web UI + 2FA)
       │ RDP / SSH / VNC
       ▼
  Целевые машины
```

---

## Что внутри

| Компонент | Версия | Роль |
|-----------|--------|------|
| Apache Guacamole | 1.5.5 | Web-клиент удалённого доступа |
| PostgreSQL | 15-alpine | База данных пользователей и подключений |
| Guacd | 1.5.5 | Протокольный демон (RDP / VNC / SSH) |
| Caddy | 2 | Reverse proxy, автоматический SSL |
| TOTP Extension | 1.5.5 | Двухфакторная аутентификация |

**Платформа:** Windows 11 Pro · WSL2 (Ubuntu) · Docker Engine

---

## Требования

- Windows 11 Pro / Enterprise (build ≥ 19041)
- Статический IP или DDNS (домен, указывающий на роутер)
- Проброс портов **80** и **443** на хост-машину
- SSH-доступ к хост-машине (порт 22 или любой другой)

---

## Установка

Развёртывание проходит в 6 этапов. Каждый скрипт идемпотентен — можно запускать повторно.

### Stage 1 — Компоненты Windows
```powershell
# SSH → PowerShell (от Администратора)
powershell -ExecutionPolicy Bypass -File windows\stage1-features.ps1
# После — ПЕРЕЗАГРУЗКА
```
Включает: WSL2, VirtualMachinePlatform, правила файрвола (80/443).

---

### Stage 2 — Установка Ubuntu в WSL2
```powershell
powershell -ExecutionPolicy Bypass -File windows\stage2-wsl-install.ps1
```
Скачивает и устанавливает Ubuntu (headless, без GUI). Занимает 2–5 минут.

---

### Stage 3 — Настройка WSL-пользователя
```powershell
powershell -ExecutionPolicy Bypass -File windows\stage3-wsl-configure.ps1 -WSLUser ВАШ_ПОЛЬЗОВАТЕЛЬ
```
Создаёт пользователя, настраивает sudo, устанавливает базовые пакеты,
создаёт символическую ссылку `~/AnyWhereDesk` → папка проекта на Windows.

---

### Stage 4 — Автозапуск
```powershell
powershell -ExecutionPolicy Bypass -File windows\stage4-autostart.ps1 -WSLUser ВАШ_ПОЛЬЗОВАТЕЛЬ
```
Создаёт задачи в Task Scheduler:
- **WSLKeepAlive** — удерживает WSL в рабочем состоянии
- **GuacamoleAutoStart** — обновляет portproxy и поднимает стек при старте Windows

Также ограничивает RDP (3389) — доступен только через Guacamole.

---

### Stage 5 — Docker Engine в WSL
```bash
# SSH → PowerShell → wsl
bash ~/AnyWhereDesk/ubuntu/stage5-docker.sh
```
Устанавливает Docker Engine в WSL2 Ubuntu.

---

### Stage 6 — Развёртывание стека
```bash
bash ~/AnyWhereDesk/ubuntu/stage6-stack.sh
```
- Копирует файлы в Linux FS (`~/guac-stack`)
- Скачивает TOTP extension
- Генерирует схему PostgreSQL
- Собирает Caddy с Cloudflare DNS-плагином
- Запускает `docker compose up -d`

---

## Конфигурация

Создай `guac-stack/.env` на основе `.env.example`:

```bash
cp guac-stack/.env.example guac-stack/.env
```

```dotenv
# Обязательно
DB_PASSWORD=        # Сложный пароль (мин. 16 символов)
DOMAIN=             # Твой домен: guac.example.com
ACME_EMAIL=         # Email для уведомлений Let's Encrypt

# Опционально — для DNS-01 challenge (Cloudflare)
CLOUDFLARE_API_TOKEN=
```

> **Генерация пароля:**
> ```bash
> openssl rand -base64 24
> ```

### SSL-сертификат

По умолчанию используется **HTTP-01 challenge** — требует открытых портов 80/443.

Для **DNS-01 challenge** (работает за NAT, не требует порта 80) — добавь `CLOUDFLARE_API_TOKEN` в `.env` и раскомментируй строку в `Caddyfile`:
```
acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
```
Подробно: [cloudflare-guide.md](cloudflare-guide.md)

---

## Первый вход

После развёртывания открой в браузере:
```
https://ВАШ_ДОМЕН/guacamole/
```

| Поле | Значение |
|------|----------|
| Логин | `guacadmin` |
| Пароль | `guacadmin` |

**Сразу после входа:**
1. Settings → Users → guacadmin → смени пароль или отключи
2. Создай своего пользователя
3. Включи TOTP: Settings → Users → ваш пользователь → TOTP

---

## Добавление подключения (RDP)

Settings → Connections → New Connection

| Параметр | Значение |
|----------|----------|
| Protocol | RDP |
| Hostname | IP целевой машины |
| Port | 3389 |
| Username | Имя пользователя Windows |
| Password | Пароль |
| Color depth | True color (32-bit) |
| Resize method | Display update |

---

## Обслуживание

### Статус стека
```bash
bash ~/guac-stack/scripts/status.sh
```

### Бэкап БД
```bash
bash ~/guac-stack/scripts/backup.sh
```
Бэкапы хранятся в `~/guac-stack/backups/`, удаляются через 30 дней.

### Обновление
```bash
bash ~/guac-stack/scripts/update.sh
```
Автоматически делает бэкап перед обновлением.

### DDNS (динамический IP)
```bash
# Добавить в cron:
*/5 * * * * bash ~/guac-stack/scripts/ddns_update.sh
```
Обновляет A-запись через Cloudflare API при смене внешнего IP.

---

## Восстановление

### Контейнеры не запустились
```bash
# В WSL
bash ~/guac-stack/ubuntu/recovery/recover-stack.sh

# Или из PowerShell
powershell -File windows\recovery\recover-containers.ps1 -WSLUser ВАШ_ПОЛЬЗОВАТЕЛЬ
```

### WSL не запускается
```powershell
powershell -File windows\recovery\recover-wsl.ps1
```
7-шаговое восстановление: от мягкого рестарта до полного сброса.

### Полный сброс (с сохранением бэкапа)
```bash
bash ~/guac-stack/ubuntu/recovery/reset-stack.sh
```
Запросит подтверждение `RESET`, создаст бэкап БД, пересоздаст стек.

### Диагностика из PowerShell
```powershell
powershell -File windows\recovery\status.ps1
```

---

## Безопасность

- **SSL/TLS** — Let's Encrypt, автопродление
- **2FA** — TOTP (Google Authenticator, Authy и др.)
- **RDP** — доступен только из Docker-сети (не из интернета напрямую)
- **Guacamole** — слушает только на `127.0.0.1:8080` (за Caddy)
- **HSTS** — `max-age=31536000; includeSubDomains`
- **Секреты** — `.env` исключён из git

---

## Структура проекта

```
AnyWhereDesk/
├── guac-stack/                  # Docker Compose стек
│   ├── docker-compose.yml
│   ├── Dockerfile.caddy         # Caddy + Cloudflare DNS плагин
│   ├── Caddyfile                # Reverse proxy конфиг
│   ├── .env.example
│   └── scripts/
│       ├── status.sh            # Проверка состояния
│       ├── backup.sh            # Бэкап PostgreSQL
│       ├── update.sh            # Обновление образов
│       └── ddns_update.sh       # Cloudflare DDNS
│
├── ubuntu/                      # Скрипты для WSL2
│   ├── stage5-docker.sh         # Установка Docker
│   ├── stage6-stack.sh          # Первый запуск стека
│   └── recovery/
│       ├── recover-stack.sh
│       └── reset-stack.sh
│
├── windows/                     # PowerShell скрипты
│   ├── stage1-features.ps1      # Компоненты Windows
│   ├── stage2-wsl-install.ps1   # Установка Ubuntu WSL2
│   ├── stage3-wsl-configure.ps1 # Настройка пользователя
│   ├── stage4-autostart.ps1     # Автозапуск + безопасность
│   └── recovery/
│       ├── recover-containers.ps1
│       ├── recover-wsl.ps1
│       └── status.ps1
│
└── cloudflare-guide.md          # Настройка Cloudflare API
```

---

## Лицензия

MIT
