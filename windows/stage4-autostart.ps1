#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 4 / 4 — Автозапуск Docker + Guacamole при старте Windows
.DESCRIPTION
    Запускать: SSH -> PowerShell после stage3 и после первого успешного запуска стека
    Команда:   powershell -ExecutionPolicy Bypass -File stage4-autostart.ps1 -WSLUser dmn

    Создаёт bat + vbs скрипты и задачу в Task Scheduler (запуск от SYSTEM при старте ОС).
    Идемпотентен — безопасно запускать повторно.
.PARAMETER WSLUser
    Имя пользователя WSL (для запуска docker compose)
.PARAMETER ScriptsDir
    Папка для bat/vbs файлов (по умолчанию: C:\Scripts\Guacamole)
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$WSLUser,

    [string]$ScriptsDir = "C:\Scripts\Guacamole"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if ($PSVersionTable.PSVersion.Major -lt 7) { chcp 65001 | Out-Null }

function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Stage 4 — Autostart Setup" -ForegroundColor Blue
Write-Host "=============================================" -ForegroundColor Blue

# ── Создаём папку скриптов ───────────────────────────────
Write-Step "Создание папки скриптов: $ScriptsDir"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
Write-OK "Папка готова"

$batFile = Join-Path $ScriptsDir "start-guac.bat"
$vbsFile = Join-Path $ScriptsDir "start-guac.vbs"
$logFile = Join-Path $ScriptsDir "startup.log"

# ── BAT-скрипт (с проверкой Docker перед compose up) ────
Write-Step "Создание bat-скрипта: $batFile"
@"
@echo off
setlocal
set LOGFILE=$logFile
echo [%date% %time%] Starting Guacamole stack >> "%LOGFILE%"

:: 0. Update WSL2 portproxy (WSL IP changes after every reboot)
for /f "tokens=1" %%i in ('wsl -d Ubuntu -- hostname -i 2^>nul') do set WSL_IP=%%i
netsh interface portproxy delete v4tov4 listenport=80  listenaddress=0.0.0.0 > nul 2>&1
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0 > nul 2>&1
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=80  connectaddress=%WSL_IP% connectport=80
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=443 connectaddress=%WSL_IP% connectport=443
echo [%date% %time%] Portproxy updated: %WSL_IP% >> "%LOGFILE%"

:: 1. Start Docker service in WSL
wsl -u root -d Ubuntu service docker start >> "%LOGFILE%" 2>&1
echo [%date% %time%] Docker service started >> "%LOGFILE%"

:: 2. Wait for Docker daemon init
timeout /t 8 /nobreak > nul

:: 3. Check if Docker is ready (max 3 tries)
set TRIES=0
:CHECK_DOCKER
wsl -d Ubuntu docker info > nul 2>&1
if %errorlevel% equ 0 goto DOCKER_READY
set /a TRIES+=1
if %TRIES% geq 3 (
    echo [%date% %time%] ERROR: Docker failed after 3 tries >> "%LOGFILE%"
    exit /b 1
)
echo [%date% %time%] Docker not ready, waiting 10s (try %TRIES%) >> "%LOGFILE%"
timeout /t 10 /nobreak > nul
goto CHECK_DOCKER

:DOCKER_READY
echo [%date% %time%] Docker ready >> "%LOGFILE%"

:: 4. Start stack
wsl -d Ubuntu -u $WSLUser bash -c "cd ~/guac-stack; docker compose up -d" >> "%LOGFILE%" 2>&1
echo [%date% %time%] Stack started >> "%LOGFILE%"
"@ | Set-Content $batFile -Encoding ASCII
Write-OK "bat-скрипт создан"

# ── VBS-обёртка (скрытый запуск bat без окна консоли) ───
Write-Step "Создание vbs-обёртки: $vbsFile"
@"
' Runs bat script silently, no console window
Set WshShell = CreateObject("WScript.Shell")
' 0 = hide window; False = do not wait for completion
WshShell.Run "cmd /c ""$batFile"" >> ""$logFile"" 2>&1", 0, False
Set WshShell = Nothing
"@ | Set-Content $vbsFile -Encoding ASCII
Write-OK "vbs-обёртка создана"

# ── Task Scheduler ───────────────────────────────────────
Write-Step "Настройка задачи в Task Scheduler..."
$taskName = "GuacamoleAutoStart"

# Удаляем старую задачу если есть
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action    = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsFile`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT30S"  # 30 сек после старта — ждём сеть

$settings  = New-ScheduledTaskSettingsSet `
    -RunOnlyIfNetworkAvailable:$false `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null

Write-OK "Задача '$taskName' создана (SYSTEM, AtStartup + 30s delay)"

# ── Проверка ─────────────────────────────────────────────
Write-Step "Проверка задачи..."
$task = Get-ScheduledTask -TaskName $taskName
Write-OK "Задача: $($task.TaskName) | Состояние: $($task.State)"

# ── Тест запуска (опционально) ───────────────────────────
Write-Host ""
Write-Host "  Проверить задачу вручную (не при старте):" -ForegroundColor Gray
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
Write-Host "  Лог: $logFile" -ForegroundColor Gray

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Stage 4 завершён! Автозапуск настроен." -ForegroundColor Green
Write-Host ""
Write-Host "  Тест: перезагрузи Windows, подожди 2 мин," -ForegroundColor Green
Write-Host "  затем SSH в Ubuntu и проверь:" -ForegroundColor Green
Write-Host "    wsl -d Ubuntu bash -c 'cd ~/guac-stack && docker compose ps'" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Green
