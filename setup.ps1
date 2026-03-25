<#
.SYNOPSIS
    Установка и настройка AnywhereDesk на Windows.
.DESCRIPTION
    Проверяет наличие Docker Desktop, WSL2, генерирует схему БД, запускает контейнеры.
    Запускайте из папки с проектом. Для установки Docker требуется администратор.
.NOTES
    Версия: 1.0
    Автор: AnywhereDesk Team
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# Цветной вывод
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success($Message) {
    Write-ColorOutput Green "[✓] $Message"
}

function Write-ErrorMsg($Message) {
    Write-ColorOutput Red "[✗] $Message"
}

function Write-Info($Message) {
    Write-ColorOutput Cyan "[i] $Message"
}

function Write-WarningMsg($Message) {
    Write-ColorOutput Yellow "[!] $Message"
}

# Проверка прав администратора
function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Проверка и установка Docker Desktop
function Install-DockerDesktop {
    Write-Info "Docker Desktop не найден. Запуск установки..."
    $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-Info "Скачивание Docker Desktop..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Info "Запуск установщика (может потребоваться перезагрузка)..."
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet" -Wait -NoNewWindow
    Write-Info "Установка завершена. Перезагрузите компьютер и запустите скрипт снова."
    exit 0
}

# Проверка и установка WSL2
function Install-WSL2 {
    Write-Info "WSL2 не найден. Устанавливаем через wsl --install..."
    # Требует администратора
    if (-not (Test-Administrator)) {
        Write-ErrorMsg "Для установки WSL2 нужны права администратора. Перезапустите скрипт от имени администратора."
        exit 1
    }
    wsl --install
    Write-Info "Установка WSL2 завершена. Перезагрузите компьютер и запустите скрипт снова."
    exit 0
}

# Проверка доступности порта
function Test-PortAvailability {
    param([int]$Port)
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $tcpClient.Connect('127.0.0.1', $Port)
        $tcpClient.Close()
        return $false # порт занят
    } catch {
        return $true # порт свободен
    }
}

# Основной блок
Write-Info "=== AnywhereDesk Setup ==="
Write-Info "Текущая папка: $PWD"

# 1. Проверка наличия Docker
$dockerExists = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerExists) {
    Write-ErrorMsg "Docker не найден."
    $response = Read-Host "Установить Docker Desktop? (y/N)"
    if ($response -eq 'y') {
        Install-DockerDesktop
    } else {
        Write-ErrorMsg "Установка прервана. Docker обязателен для работы AnywhereDesk."
        exit 1
    }
} else {
    # Проверяем, запущен ли Docker
    $dockerRunning = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Docker установлен, но не запущен. Запустите Docker Desktop и повторите."
        exit 1
    }
    Write-Success "Docker работает."
}

# 2. Проверка WSL2 (если версия Windows 10/11)
$os = Get-WmiObject -Class Win32_OperatingSystem
if ($os.Version -ge 10 -and $os.ProductType -eq 1) {
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "WSL2 не установлен или не включен."
        $response = Read-Host "Установить WSL2? (y/N)"
        if ($response -eq 'y') {
            Install-WSL2
        } else {
            Write-ErrorMsg "Без WSL2 Docker Desktop может работать некорректно. Установите WSL2 вручную или продолжите на свой страх и риск."
            $response = Read-Host "Продолжить? (y/N)"
            if ($response -ne 'y') { exit 1 }
        }
    } else {
        # Проверяем, что версия WSL2
        if ($wslStatus -notmatch "WSL 2") {
            Write-Info "WSL установлен, но не версия 2. Рекомендуется установить WSL2."
        } else {
            Write-Success "WSL2 установлен."
        }
    }
} else {
    Write-Info "Windows Server или более старая версия, WSL2 не требуется."
}

# 3. Проверка наличия файлов проекта
$requiredFiles = @("docker-compose.yml", "init\initdb.sql")
$missingFiles = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
    }
}
if ($missingFiles.Count -gt 0) {
    Write-WarningMsg "Отсутствуют файлы: $missingFiles"
    if (-not (Test-Path "init")) {
        New-Item -ItemType Directory -Path "init" | Out-Null
    }
    if ($missingFiles -contains "init\initdb.sql") {
        Write-Info "Генерируем init/initdb.sql..."
        docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgresql > init\initdb.sql
        if ($LASTEXITCODE -eq 0) {
            Write-Success "initdb.sql создан."
        } else {
            Write-ErrorMsg "Не удалось сгенерировать initdb.sql. Проверьте подключение к интернету и наличие образа guacamole/guacamole."
            exit 1
        }
    }
    if ($missingFiles -contains "docker-compose.yml") {
        Write-ErrorMsg "Файл docker-compose.yml отсутствует. Поместите его в папку проекта и запустите скрипт снова."
        exit 1
    }
} else {
    Write-Success "Все файлы проекта на месте."
}

# 4. Проверка занятости портов
$ports = @(80, 443, 8080)
$blockedPorts = @()
foreach ($port in $ports) {
    if (-not (Test-PortAvailability $port)) {
        $blockedPorts += $port
        Write-WarningMsg "Порт $port занят. Возможно, используется другим приложением."
    }
}
if ($blockedPorts.Count -gt 0) {
    Write-WarningMsg "Заняты порты: $blockedPorts. AnywhereDesk требует порты 80, 443 для HTTPS и 8080 для Guacamole. Освободите их или настройте другие в Nginx Proxy Manager."
    $response = Read-Host "Продолжить? (y/N)"
    if ($response -ne 'y') { exit 1 }
}

# 5. Запуск стека
Write-Info "Запуск контейнеров..."
docker-compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-ErrorMsg "Ошибка при запуске docker-compose. Проверьте логи: docker-compose logs"
    exit 1
}
Write-Success "Контейнеры запущены."

# 6. Проверка доступности Guacamole
Write-Info "Ожидание готовности Guacamole (до 30 сек)..."
for ($i = 0; $i -lt 30; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/guacamole/" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) {
            Write-Success "Guacamole доступен по адресу http://localhost:8080/guacamole/"
            break
        }
    } catch {
        Start-Sleep -Seconds 1
    }
}
if ($i -eq 30) {
    Write-WarningMsg "Guacamole не ответил за 30 секунд. Проверьте логи: docker-compose logs guacamole"
}

# 7. Вывод информации
Write-Info "=== AnywhereDesk успешно установлен ==="
Write-Info "Локальный доступ: http://localhost:8080/guacamole/"
Write-Info "Для удаленного доступа настройте DDNS и проброс портов 80/443 на этом ПК."
Write-Info "Документация: https://github.com/yourusername/anywheredesk/blob/main/README.md"