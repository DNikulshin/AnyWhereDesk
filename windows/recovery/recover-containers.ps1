#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Восстановление контейнеров Guacamole — запускать из SSH -> PowerShell
    Сценарии: контейнеры упали, Docker завис, стек не поднялся после ребута
    Команда: powershell -ExecutionPolicy Bypass -File recovery\recover-containers.ps1
#>
param(
    [string]$WSLUser = "dmn"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
if ($PSVersionTable.PSVersion.Major -lt 7) { chcp 65001 | Out-Null }

function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Восстановление контейнеров" -ForegroundColor Blue
Write-Host "=============================================" -ForegroundColor Blue

# ── Шаг 1: Проверка WSL ──────────────────────────────────
Write-Step "Проверка WSL Ubuntu..."
try {
    $wslTest = wsl -d Ubuntu echo "ok" 2>$null
    if ($wslTest -ne "ok") { throw "WSL не отвечает" }
    Write-OK "WSL Ubuntu доступен"
} catch {
    Write-FAIL "WSL Ubuntu недоступен. Сначала запусти: recovery\recover-wsl.ps1"
    exit 1
}

# ── Шаг 2: Проверка Docker ───────────────────────────────
Write-Step "Проверка Docker daemon..."
$dockerOk = wsl -d Ubuntu bash -c "docker info > /dev/null 2>&1 && echo ok" 2>$null
if ($dockerOk -ne "ok") {
    Write-WARN "Docker не запущен — запускаем..."
    wsl -u root -d Ubuntu service docker start | Out-Null
    Start-Sleep -Seconds 8

    $dockerOk = wsl -d Ubuntu bash -c "docker info > /dev/null 2>&1 && echo ok" 2>$null
    if ($dockerOk -ne "ok") {
        Write-FAIL "Docker не запустился. Проверь WSL: recovery\recover-wsl.ps1"
        exit 1
    }
    Write-OK "Docker запущен"
} else {
    Write-OK "Docker работает"
}

# ── Шаг 3: Статус контейнеров до восстановления ─────────
Write-Step "Текущий статус контейнеров..."
$psOutput = wsl -d Ubuntu bash -c "cd ~/guac-stack && docker compose ps 2>/dev/null" 2>$null
if ($psOutput) {
    $psOutput | ForEach-Object { Write-Host "  $_" }
} else {
    Write-WARN "guac-stack не найден или не запускался"
}

# ── Шаг 4: Перезапуск стека ──────────────────────────────
Write-Step "Перезапуск стека (docker compose up -d)..."
$result = wsl -d Ubuntu -u $WSLUser bash -c @"
cd ~/guac-stack 2>/dev/null || { echo 'ERROR: ~/guac-stack не найден'; exit 1; }
docker compose up -d 2>&1
"@ 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-OK "docker compose up -d выполнен"
} else {
    Write-WARN "Возможны ошибки при запуске:"
    $result | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

# ── Шаг 5: Ожидание и проверка ──────────────────────────
Write-Step "Ожидание запуска контейнеров (30 сек)..."
Start-Sleep -Seconds 30

$psResult = wsl -d Ubuntu bash -c @"
cd ~/guac-stack 2>/dev/null || exit 1
TOTAL=\$(docker compose config --services | wc -l)
RUNNING=\$(docker compose ps --format '{{.State}}' 2>/dev/null | grep -c '^running$')
echo "\$RUNNING/\$TOTAL"
docker compose ps
"@ 2>$null

$psResult | ForEach-Object { Write-Host "  $_" }

# ── Шаг 6: Проверка HTTP ────────────────────────────────
Write-Step "Проверка Guacamole HTTP (localhost:8080)..."
$httpCode = wsl -d Ubuntu bash -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/guacamole/ 2>/dev/null" 2>$null
if ($httpCode -match "^(200|302)$") {
    Write-OK "Guacamole отвечает: HTTP $httpCode"
} else {
    Write-WARN "Guacamole HTTP: $httpCode (если недавно запустился — подожди ещё 30 сек)"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Восстановление завершено" -ForegroundColor Green
Write-Host "  Подробный статус: recovery\status.ps1" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Green
