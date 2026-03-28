﻿#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Полная диагностика системы — запускать из SSH -> PowerShell
    Команда: powershell -ExecutionPolicy Bypass -File recovery\status.ps1
#>

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = New-Object System.Text.UTF8Encoding $false


function Write-Section { param($m) Write-Host "`n── $m ──" -ForegroundColor Cyan }
function Write-OK       { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN     { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL     { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Диагностика системы" -ForegroundColor Blue
Write-Host "  $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue

# ── Windows ──────────────────────────────────────────────
Write-Section "Windows"
$os = Get-CimInstance Win32_OperatingSystem
Write-OK "ОС: $($os.Caption) Build $($os.BuildNumber)"
Write-OK "Аптайм: $([math]::Round(($os.LocalDateTime - $os.LastBootUpTime).TotalHours, 1)) часов"

# ── WSL ──────────────────────────────────────────────────
Write-Section "WSL"
try {
    $wslStatus = wsl --status 2>&1
    $wslList   = wsl --list --verbose 2>&1
    if ($wslList -match 'Ubuntu') {
        Write-OK "WSL2 работает"
        $wslList | Where-Object { $_ -match 'Ubuntu' } | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-WARN "Ubuntu не найдена в WSL"
    }
} catch {
    Write-FAIL "WSL недоступен: $_"
}

# ── Docker ───────────────────────────────────────────────
Write-Section "Docker"
try {
    $dockerVersion = wsl -d Ubuntu docker version --format '{{.Server.Version}}' 2>$null
    if ($dockerVersion) {
        Write-OK "Docker Engine: $dockerVersion"
        $dockerPs = wsl -d Ubuntu bash -c "cd ~/guac-stack && docker compose ps --format '{{.Name}}: {{.State}}' 2>/dev/null"
        if ($dockerPs) {
            Write-OK "Контейнеры:"
            $dockerPs | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-WARN "Контейнеры не запущены или guac-stack не настроен"
        }
    } else {
        Write-FAIL "Docker не отвечает внутри WSL"
    }
} catch {
    Write-FAIL "Ошибка проверки Docker: $_"
}

# ── Сеть ─────────────────────────────────────────────────
Write-Section "Сеть (порты 80, 443, 3389, 22)"
@(80, 443, 3389, 22) | ForEach-Object {
    $port = $_
    $conn = netstat -an 2>$null | Select-String "0.0.0.0:$port\s+.*LISTENING"
    if ($conn) {
        Write-OK "Порт $port — LISTENING"
    } else {
        Write-WARN "Порт $port — не найден в LISTENING"
    }
}

# ── Брандмауэр ───────────────────────────────────────────
Write-Section "Брандмауэр"
@("Guacamole-HTTP", "Guacamole-HTTPS") | ForEach-Object {
    $rule = Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled) {
        Write-OK "Правило '$_': включено"
    } elseif ($rule) {
        Write-WARN "Правило '$_': существует но отключено"
    } else {
        Write-FAIL "Правило '$_': не найдено"
    }
}

# ── RDP ─────────────────────────────────────────────────
Write-Section "RDP"
$rdp = (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
if ($rdp -eq 0) { Write-OK "RDP включён" } else { Write-WARN "RDP отключён" }

# ── Task Scheduler ───────────────────────────────────────
Write-Section "Task Scheduler (автозапуск)"
$task = Get-ScheduledTask -TaskName "GuacamoleAutoStart" -ErrorAction SilentlyContinue
if ($task) {
    Write-OK "Задача 'GuacamoleAutoStart': $($task.State)"
    $info = Get-ScheduledTaskInfo -TaskName "GuacamoleAutoStart" -ErrorAction SilentlyContinue
    if ($info.LastRunTime -gt [datetime]'2000-01-01') {
        $status = if ($info.LastTaskResult -eq 0) { "OK" } else { "код $($info.LastTaskResult)" }
        Write-OK "Последний запуск: $($info.LastRunTime.ToString('yyyy-MM-dd HH:mm')) — $status"
    }
} else {
    Write-WARN "Задача 'GuacamoleAutoStart' не найдена — запусти stage4-autostart.ps1"
}

# ── Диск ─────────────────────────────────────────────────
Write-Section "Дисковое пространство"
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
    $usedPct = [math]::Round($_.Used / ($_.Used + $_.Free) * 100)
    $color   = if ($usedPct -gt 85) { 'Red' } elseif ($usedPct -gt 70) { 'Yellow' } else { 'Green' }
    Write-Host ("  [{0,3}%] {1}: Свободно {2:N1} GB / {3:N1} GB" -f $usedPct, $_.Name,
        ($_.Free/1GB), (($_.Used+$_.Free)/1GB)) -ForegroundColor $color
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "  Диагностика завершена" -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue
