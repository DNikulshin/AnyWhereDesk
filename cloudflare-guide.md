# Cloudflare API — получение токена

## Вариант 1 (рекомендуется): API Token через браузер

Создай на **телефоне или другом ПК**, затем вставь в `.env`:

1. Открой `cloudflare.com` → войди в аккаунт
2. Верхний правый угол → **My Profile** → **API Tokens**
3. Нажми **Create Token**
4. Шаблон: **Edit zone DNS** → **Use template**
5. Zone Resources: **Include → Specific zone → твой домен**
6. **Continue to summary** → **Create Token**
7. **Скопируй токен** — он показывается **один раз**

Вставь в `.env`:
```
CLOUDFLARE_API_TOKEN=твой_токен_здесь
```

---

## Вариант 2: Global API Key (без создания нового токена)

Если нет доступа к браузеру для создания токена, можно использовать
**Global API Key** — он уже существует и не требует создания.

### Где взять Global API Key

1. `cloudflare.com` → **My Profile** → **API Tokens**
2. В самом низу страницы: **Global API Key** → **View**
3. Введи пароль Cloudflare → скопируй ключ

### Настройка в .env

```env
# Закомментируй CLOUDFLARE_API_TOKEN
# CLOUDFLARE_API_TOKEN=

# Раскомментируй и заполни:
CLOUDFLARE_EMAIL=your@email.com
CLOUDFLARE_API_KEY=твой_global_api_key
```

### Изменение Caddyfile для Global API Key

Открой `~/guac-stack/Caddyfile` и замени блок `{ ... }` в начале:

```caddyfile
{
    email your@email.com
    admin off

    # Закомментируй API Token строку:
    # acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}

    # Раскомментируй Global API Key блок:
    acme_dns cloudflare {
        api_key   {env.CLOUDFLARE_API_KEY}
        api_email {env.CLOUDFLARE_EMAIL}
    }
}
```

После изменения — пересобери Caddy:
```bash
cd ~/guac-stack
docker compose build --no-cache caddy
docker compose up -d caddy
```

---

## Проверка токена через curl (из WSL Ubuntu)

**API Token:**
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ВАШ_ТОКЕН" | python3 -m json.tool
# Должно быть: "status": "active"
```

**Global API Key:**
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user" \
  -H "X-Auth-Email: ВАШ_EMAIL" \
  -H "X-Auth-Key: ВАШ_GLOBAL_KEY" | python3 -m json.tool
# Должно быть: "success": true
```

---

## Получение Zone ID и Record ID (нужно для ddns_update.sh)

```bash
# Замени твой_домен.com и токен на свои значения
CF_TOKEN="ВАШ_ТОКЕН"
DOMAIN="твой_домен.com"

# Zone ID
curl -s "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
  -H "Authorization: Bearer ${CF_TOKEN}" | python3 -c \
  "import sys,json; r=json.load(sys.stdin)['result']; print('Zone ID:', r[0]['id'] if r else 'не найден')"

# Record ID (подставь ZONE_ID из предыдущей команды)
ZONE_ID="ВАШ_ZONE_ID"
curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}" \
  -H "Authorization: Bearer ${CF_TOKEN}" | python3 -c \
  "import sys,json; r=json.load(sys.stdin)['result']; print('Record ID:', r[0]['id'], 'IP:', r[0]['content'] if r else 'не найден')"
```
