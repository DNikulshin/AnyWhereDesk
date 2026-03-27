#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 2 / 4 — Установка WSL2 + Ubuntu (headless)
.DESCRIPTION
    Запускать: SSH -> PowerShell ПОСЛЕ перезагрузки из Stage 1
    Команда:   powershell -ExecutionPolicy Bypass -File stage2-wsl-install.ps1

    Идемпотентен — безопасно запускать повторно.
    Если требуется повторная перезагрузка — скрипт сообщит об этом.
.PARAMETER Reboot
    Перезагрузить автоматически если потребуется
#>
param(
    [switch]$Reboot
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if ($PSVersionTable.PSVersion.Major -lt 7) { chcp 65001 | Out-Null }

function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL { param($m) Write-Host "  [XX] $m" -ForegroundColor Red; throw $m }

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Stage 2 — WSL2 + Ubuntu" -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue

# ── Проверка: WSL уже установлен? ───────────────────────
# Используем реестр — wsl --list --quiet возвращает UTF-16,
# что в PS5.1 на русской Windows не матчится через -match
Write-Step "Проверка существующих WSL-дистрибутивов..."
$lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
$ubuntuExists = Get-ItemProperty "$lxss\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DistributionName -match '^Ubuntu' }
if ($ubuntuExists) {
    Write-WARN "Ubuntu уже установлена. Переходи к: stage3-wsl-configure.ps1"
    Write-OK "BasePath: $($ubuntuExists.BasePath)"
    exit 0
}
Write-OK "Ubuntu не найдена — начинаем установку"

# ── Обновление WSL kernel ────────────────────────────────
Write-Step "Обновление WSL kernel..."
wsl --update
Write-OK "WSL kernel обновлён"

# ── WSL2 как версия по умолчанию ────────────────────────
Write-Step "WSL2 как версия по умолчанию..."
wsl --set-default-version 2
Write-OK "WSL2 default установлен"

# ── Установка Ubuntu без запуска (headless) ──────────────
Write-Step "Установка Ubuntu --no-launch (headless, без GUI)..."
Write-Host "  Скачивание образа — может занять 2-5 минут..." -ForegroundColor Gray
wsl --install -d Ubuntu --no-launch
Write-OK "Команда установки выполнена"

# ── Ожидание и проверка ──────────────────────────────────
Write-Step "Ожидание завершения установки (20 сек)..."
Start-Sleep -Seconds 20

$ubuntuExists = Get-ItemProperty "$lxss\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DistributionName -match '^Ubuntu' }
if ($ubuntuExists) {
    Write-OK "Ubuntu успешно установлена"
    Write-OK "BasePath: $($ubuntuExists.BasePath)"
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  Stage 2 завершён!" -ForegroundColor Green
    Write-Host "  Следующий шаг:" -ForegroundColor Green
    Write-Host "  .\stage3-wsl-configure.ps1 -WSLUser dmn" -ForegroundColor White
    Write-Host "===========================================" -ForegroundColor Green
} else {
    Write-WARN "Ubuntu не обнаружена в списке после установки."
    Write-WARN "Вероятно требуется ещё одна перезагрузка."
    Write-Host ""
    if ($Reboot) {
        Write-Host "Перезагрузка через 10 секунд..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Host "Перезагрузись и запусти stage2 снова:" -ForegroundColor Yellow
        Write-Host "  .\stage2-wsl-install.ps1" -ForegroundColor White
        Write-Host "Или с автоперезагрузкой:" -ForegroundColor Yellow
        Write-Host "  .\stage2-wsl-install.ps1 -Reboot" -ForegroundColor White
    }
}
