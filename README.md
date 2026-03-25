# AnywhereDesk – удалённый доступ к рабочему столу через браузер

AnywhereDesk – это само‑хостинговое решение для безопасного доступа к вашему домашнему ПК (Windows) из любого браузера. Проект построен на связке **Apache Guacamole** (web‑шлюз RDP), **PostgreSQL** (хранилище учётных записей и настроек) и **Nginx Proxy Manager** (автоматический SSL и маршрутизация). Всё работает внутри Docker.

## Возможности

- Доступ к Windows через браузер без установки дополнительных клиентов.
- Собственный домен и SSL (Let’s Encrypt) через Nginx Proxy Manager.
- Двухфакторная аутентификация (TOTP) в Guacamole.
- Полный контроль над данными – всё хранится на вашем ПК.
- Возможность подключаться к нескольким ПК (через разные RDP‑профили).

## Требования

- **Домашний ПК**:
  - Windows 11 Pro (или Windows 10/11 Pro/Enterprise). Для Home‑версии потребуется [RDP Wrapper](https://github.com/stascorp/rdpwrap) (не рекомендуется).
  - Docker Desktop с поддержкой WSL2.
  - Наличие учётной записи локального администратора Windows (для RDP).
  - Доступ к настройкам роутера (для проброса портов 80 и 443).
  - (Опционально) собственный домен или бесплатный DDNS (DuckDNS, No‑IP и т.п.).
- **Инструменты разработки (для сборки)**:
  - Git, Docker, Docker Compose.
  - (Опционально) GitHub Actions для CI.

## Быстрый старт (локальное тестирование)

Вы можете протестировать стек на любом ПК с Docker, не открывая порты наружу.

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/yourusername/anywheredesk.git
   cd anywheredesk
Создайте папку init и сгенерируйте схему базы данных:

bash
mkdir -p init
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgresql > init/initdb.sql
Запустите стек:

bash
docker-compose up -d
Откройте в браузере http://localhost:8080/guacamole/ и войдите с учётными данными:

Логин: guacadmin

Пароль: guacadmin

Создайте RDP‑подключение:

Protocol: RDP

Hostname: host.docker.internal (если Docker и Windows на одном ПК) или IP вашего Windows‑ПК

Port: 3389

Username / Password: ваши локальные учётные данные Windows

Security mode: NLA

Ignore server certificate: включите

Нажмите Save и попробуйте подключиться.

Для остановки стека:

bash
docker-compose down
Примечание о сети: стек использует внутреннюю сеть internal, которая создаётся автоматически. Все контейнеры (postgres, guacd, guacamole) общаются внутри этой сети. При необходимости запуска дополнительных контейнеров (например, тестового RDP-сервера) указывайте ту же сеть: --network internal.

Непрерывная интеграция (GitHub Actions)
В репозитории настроен workflow .github/workflows/test-stack.yml. Он автоматически:

Создаёт схему БД.

Запускает весь стек.

Проверяет доступность Guacamole.

Поднимает тестовый RDP‑сервер и проверяет сетевую доступность.

Выполняет API‑тест (создание RDP‑подключения).

Это гарантирует, что после каждого коммита стек остаётся работоспособным. Убедитесь, что все проверки проходят зелёным, прежде чем разворачивать сервис на домашнем ПК.

Развёртывание на домашнем Windows‑ПК
1. Установка Docker Desktop
Скачайте Docker Desktop for Windows.

При установке выберите Use WSL 2.

После установки перезагрузите компьютер. Убедитесь, что Docker запущен (иконка в трее).

2. Подготовка проекта
Скопируйте файлы репозитория в папку на диске C (например, C:\anywheredesk).

Убедитесь, что в папке init лежит файл initdb.sql (сгенерированный через --postgresql).

При необходимости отредактируйте пароли в docker-compose.yml (раздел environment сервиса guacamole и postgres).

3. Настройка статического локального IP
Чтобы роутер всегда направлял порты на ваш ПК, закрепите за ним IP-адрес. Это можно сделать в настройках роутера (по MAC‑адресу) или в Windows:

Параметры → Сеть и Интернет → Ethernet → Изменить параметры адаптера.

ПКМ по активному адаптеру → Свойства → IP версии 4 (TCP/IPv4).

Выберите Использовать следующий IP:

IP: 192.168.1.100 (или любой свободный в вашей подсети)

Маска: 255.255.255.0

Шлюз: IP вашего роутера (обычно 192.168.1.1)

DNS можно оставить автоматически.

4. Настройка домена и DDNS
Для доступа из интернета вам понадобится домен, который будет указывать на ваш внешний IP (он может меняться). Самый простой способ – использовать бесплатный DuckDNS:

Зарегистрируйтесь на duckdns.org и получите токен.

Добавьте в docker-compose.yml новый сервис для обновления IP:

yaml
duckdns:
  image: linuxserver/duckdns
  container_name: duckdns
  environment:
    - SUBDOMAINS=your-subdomain
    - TOKEN=your-token
    - LOG_FILE=false
  restart: unless-stopped
После этого ваш домен будет вида your-subdomain.duckdns.org.

Если у вас есть собственный домен, используйте Cloudflare DNS и контейнер linuxserver/cloudflare-ddns для автоматического обновления A‑записи.

5. Проброс портов на роутере
Зайдите в веб‑интерфейс роутера (обычно http://192.168.1.1). Найдите раздел Port Forwarding (или Виртуальные серверы) и создайте два правила:

Внешний порт	Внутренний порт	Протокол	Внутренний IP
80	80	TCP	192.168.1.100
443	443	TCP	192.168.1.100
Если ваш провайдер блокирует порты 80/443, используйте другие (например, 8080 и 8443) и в Nginx Proxy Manager настройте прокси на эти порты.

6. Запуск стека
В PowerShell (от администратора) перейдите в папку проекта и выполните:

powershell
docker-compose up -d
Проверьте, что все контейнеры запущены:

powershell
docker-compose ps
7. Настройка Nginx Proxy Manager
Откройте браузер и перейдите по адресу http://ваш_локальный_IP:81 (или http://localhost:81). Логин по умолчанию: admin@example.com / changeme.

Сразу смените пароль администратора.

В разделе Proxy Hosts нажмите Add Proxy Host.

Domain Names: введите ваш DDNS-домен (например, your-subdomain.duckdns.org).

Scheme: http

Forward Hostname / IP: guacamole (имя сервиса в compose)

Forward Port: 8080

Перейдите на вкладку SSL:

Включите Force SSL

Request a new SSL Certificate

Укажите email и нажмите Save.

Через несколько секунд сертификат будет выпущен. Теперь ваш Guacamole доступен по https://your-subdomain.duckdns.org/guacamole/.

8. Настройка подключения к Windows
Войдите в Guacamole через браузер.

Нажмите Settings → Connections → New Connection.

Заполните:

Name: Home PC

Protocol: RDP

Hostname: host.docker.internal (этот адрес позволяет контейнеру Guacamole видеть хостовую Windows)

Port: 3389

Username: ваше имя локального администратора Windows

Password: пароль

Security mode: NLA

Ignore server certificate: включите

Resize method: Display Update

Сохраните и нажмите на новое подключение. Должен открыться рабочий стол Windows.

9. Безопасность
Смените пароль по умолчанию для пользователя guacadmin в интерфейсе Guacamole.

Включите двухфакторную аутентификацию (TOTP). Для этого в docker-compose.yml в секции guacamole добавлена переменная EXTENSIONS: auth-totp. После перезапуска стека войдите и отсканируйте QR‑код приложением (Google Authenticator, Authy).

Настройте брандмауэр Windows:

Разрешите входящие подключения только на порты 80 и 443 (для Docker).

Убедитесь, что RDP (порт 3389) доступен только для локальной сети (или полностью заблокирован, если доступ идёт только через Guacamole).

Регулярно обновляйте образы Docker:

powershell
docker-compose pull
docker-compose up -d
Рассмотрите использование VPN вместо проброса портов, если не хотите открывать доступ из интернета напрямую.

Устранение неполадок
Guacamole не запускается (ошибка подключения к БД)
Убедитесь, что в docker-compose.yml используются переменные с префиксом POSTGRESQL_ (например, POSTGRESQL_HOSTNAME, POSTGRESQL_PORT), а не POSTGRES_. Старые имена вызывают ошибку Property "postgresql-port" must be an integer.

Проверьте логи: docker logs guacamole.

Не удаётся войти в Guacamole (guacadmin / guacadmin)
Если вы запускали стек с пустым томом, пользователь должен создаться автоматически. Если нет, сгенерируйте схему заново и пересоздайте стек с удалением тома: docker-compose down -v && docker-compose up -d.

Чёрный экран при RDP‑подключении
Убедитесь, что на Windows включён удалённый рабочий стол и брандмауэр разрешает входящие подключения.

Попробуйте изменить Color depth на 16-bit и Resize method на Display Update.

Если вы подключаетесь к контейнеру с Linux, используйте Security mode = RDP (не NLA).

Порт 3389 недоступен из контейнера Guacamole
Проверьте, что на Windows служба Remote Desktop Services запущена.

Временно отключите брандмауэр Windows для теста.

Если используете host.docker.internal, убедитесь, что в настройках Docker Desktop включена опция Enable host networking (Resources → Network).

Не выпускается SSL‑сертификат в Nginx Proxy Manager
Убедитесь, что порты 80 и 443 проброшены на ваш ПК и доступны из интернета (проверьте через canyouseeme.org).

Домен должен правильно резолвиться на ваш внешний IP (проверьте через nslookup).

Если домен использует Cloudflare, отключите прокси (оранжевое облако) на время выпуска сертификата.

Контейнеры не видят друг друга
Все контейнеры проекта (включая тестовый RDP-сервер) должны находиться в одной сети. По умолчанию это сеть internal. Проверить можно командой docker network inspect internal.

Лицензия
Проект распространяется под лицензией MIT. Используемые компоненты (Apache Guacamole, PostgreSQL, Nginx Proxy Manager) имеют свои лицензии, указанные в их репозиториях.

Поддержка
Если у вас возникли вопросы или вы нашли ошибку, создайте Issue в репозитории GitHub. Мы будем рады помочь.