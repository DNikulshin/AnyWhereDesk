﻿#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 3 / 4 — Настройка пользователя WSL Ubuntu (headless, без GUI)
.DESCRIPTION
    Запускать: SSH -> PowerShell после Stage 2
    Команда:   powershell -ExecutionPolicy Bypass -File stage3-wsl-configure.ps1 -WSLUser dmn

    Создаёт пользователя в WSL, настраивает sudo, устанавливает базовые пакеты,
    создаёт символическую ссылку ~/AnyWhereDesk -> проект на Windows.
    Идемпотентен — безопасно запускать повторно.
.PARAMETER WSLUser
    Имя пользователя в WSL (обычно совпадает с Windows SSH-пользователем)
.PARAMETER WSLPassword
    Пароль WSL-пользователя. Если не передан — запрашивается интерактивно.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$WSLUser,

    [string]$WSLPassword = ""
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = New-Object System.Text.UTF8Encoding $false


function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL { param($m) Write-Host "  [XX] $m" -ForegroundColor Red; throw $m }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Stage 3 — WSL Configure" -ForegroundColor Blue
Write-Host "=============================================" -ForegroundColor Blue

# ── Пароль ──────────────────────────────────────────────
# Запрашиваем интерактивно если не передан (безопаснее чем в командной строке)
if (-not $WSLPassword) {
    $secPwd = Read-Host "Пароль для WSL-пользователя '$WSLUser'" -AsSecureString
    $WSLPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    )
}

# ── Проверка: WSL Ubuntu есть? ───────────────────────────
# Реестр вместо wsl --list (UTF-16 не матчится в PS5.1)
Write-Step "Проверка WSL Ubuntu..."
$lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
$ubuntuEntry = Get-ItemProperty "$lxss\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DistributionName -match '^Ubuntu' } |
    Select-Object -First 1
if (-not $ubuntuEntry) {
    Write-FAIL "Ubuntu не найдена. Сначала запусти: stage2-wsl-install.ps1"
}
Write-OK "Ubuntu найдена: $($ubuntuEntry.DistributionName)"

# ── Создание пользователя ────────────────────────────────
Write-Step "Создание пользователя '$WSLUser' в WSL..."
$createScript = @"
set -e
if id '$WSLUser' &>/dev/null; then
    echo "already_exists"
else
    useradd -m -s /bin/bash '$WSLUser'
    echo "created"
fi
echo '$WSLUser`:$WSLPassword' | chpasswd
usermod -aG sudo '$WSLUser'
"@
$r = $createScript | wsl -d Ubuntu -u root bash
Write-OK "Пользователь: $r"

# ── Установка DefaultUid ─────────────────────────────────
Write-Step "Установка дефолтного пользователя WSL..."
$lxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
$ubuntuEntry = Get-ItemProperty "$lxssPath\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DistributionName -match '^Ubuntu' } |
    Select-Object -First 1

if ($ubuntuEntry) {
    $uid = (wsl -d Ubuntu -u root id -u $WSLUser 2>$null).Trim()
    if ($uid -match '^\d+$') {
        Set-ItemProperty -Path "$lxssPath\$($ubuntuEntry.PSChildName)" `
            -Name DefaultUid -Value ([int]$uid)
        Write-OK "DefaultUid -> $uid ($WSLUser)"
    } else {
        Write-WARN "Не удалось получить UID — DefaultUid не изменён"
    }
} else {
    Write-WARN "Запись Ubuntu в реестре не найдена — DefaultUid не изменён"
}

# ── Sudoers (NOPASSWD для Docker) ────────────────────────
Write-Step "Настройка sudoers (NOPASSWD для Docker)..."
$sudoersScript = @"
SUDOERS_LINE='$WSLUser ALL=(ALL) NOPASSWD: /usr/sbin/service docker start, /usr/bin/docker, /usr/bin/docker compose'
if grep -qF "$WSLUser ALL=(ALL) NOPASSWD" /etc/sudoers 2>/dev/null; then
    echo "already_configured"
else
    echo "`$SUDOERS_LINE" >> /etc/sudoers
    echo "configured"
fi
"@
$r = $sudoersScript | wsl -d Ubuntu -u root bash
Write-OK "sudoers: $r"

# ── Базовые пакеты ───────────────────────────────────────
Write-Step "Обновление apt + базовые пакеты (ca-certificates, curl, netcat)..."
@"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release netcat-openbsd jq 2>/dev/null
"@ | wsl -d Ubuntu -u root bash | Where-Object { $_ -notmatch '^(Get:|Hit:|Reading|Building|Selecting)' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-OK "Базовые пакеты установлены"

# ── Символическая ссылка ~/AnyWhereDesk ─────────────────
Write-Step "Создание ссылки ~/AnyWhereDesk -> проект на Windows..."
# Определяем Windows-путь к проекту
$projectWinPath = Split-Path $PSScriptRoot -Parent
# Конвертируем в WSL-путь: C:\Users\... -> /mnt/c/Users/...
$driveLetter = $projectWinPath.Substring(0, 1).ToLower()
$projectWslPath = "/mnt/$driveLetter/" + ($projectWinPath.Substring(3) -replace '\\', '/')

$linkScript = @"
LINK=~/AnyWhereDesk
TARGET='$projectWslPath'
if [ -L "`$LINK" ] && [ "`$(readlink `$LINK)" = "`$TARGET" ]; then
    echo "already_exists"
elif [ -e "`$LINK" ]; then
    echo "exists_not_link"
else
    ln -s "`$TARGET" "`$LINK"
    echo "created: `$LINK -> `$TARGET"
fi
"@
$r = $linkScript | wsl -d Ubuntu -u $WSLUser bash
Write-OK "Ссылка: $r"

# ── Проверка ─────────────────────────────────────────────
Write-Step "Финальная проверка..."
$whoami = (wsl -d Ubuntu whoami 2>$null).Trim()
Write-OK "Дефолтный пользователь WSL: $whoami"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Stage 3 завершён!" -ForegroundColor Green
Write-Host ""
Write-Host "  Следующий шаг (SSH -> Ubuntu):" -ForegroundColor Green
Write-Host "  Из PowerShell:" -ForegroundColor White
Write-Host "    wsl" -ForegroundColor White
Write-Host "  Затем в Ubuntu:" -ForegroundColor White
Write-Host "    bash ~/AnyWhereDesk/ubuntu/stage5-docker.sh" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Green
