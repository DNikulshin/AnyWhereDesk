﻿#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Stage 1 / 4 — Включение компонентов Windows для WSL2 + Docker
.DESCRIPTION
    Запускать: SSH -> PowerShell (от Администратора)
    Команда:   powershell -ExecutionPolicy Bypass -File stage1-features.ps1 [-Reboot]
    После:     ПЕРЕЗАГРУЗКА, затем stage2-wsl-install.ps1

    Идемпотентен — безопасно запускать повторно.
.PARAMETER Reboot
    Перезагрузить автоматически после включения компонентов
#>
param(
    [switch]$Reboot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = New-Object System.Text.UTF8Encoding $false


function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL { param($m) Write-Host "  [XX] $m" -ForegroundColor Red; throw $m }

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Stage 1 — Windows Features" -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue

# ── Проверка версии Windows ──────────────────────────────
Write-Step "Проверка ОС..."
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Write-FAIL "Требуется Windows 10 2004+ / Windows 11 (текущая сборка: $build)"
}
Write-OK "Windows build: $build — поддерживается"

# ── Проверка: уже выполнено? ─────────────────────────────
Write-Step "Проверка текущего состояния компонентов..."

$wslOk = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue).State -eq 'Enabled'
$vmpOk = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue).State -eq 'Enabled'

if ($wslOk -and $vmpOk) {
    Write-WARN "WSL и VirtualMachinePlatform уже включены."
    Write-WARN "Если Ubuntu ещё не установлена — переходи к: stage2-wsl-install.ps1"
    exit 0
}

# ── Включение WSL ────────────────────────────────────────
Write-Step "Включение Microsoft-Windows-Subsystem-Linux..."
if (-not $wslOk) {
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    Write-OK "WSL включён"
} else {
    Write-WARN "WSL уже был включён"
}

# ── Включение VirtualMachinePlatform ────────────────────
Write-Step "Включение VirtualMachinePlatform..."
if (-not $vmpOk) {
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    Write-OK "VirtualMachinePlatform включён"
} else {
    Write-WARN "VirtualMachinePlatform уже был включён"
}

# ── Hyper-V (опционально — недоступен на Windows Home) ───
Write-Step "Включение Hyper-V (опционально)..."
try {
    $hvOk = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue).State -eq 'Enabled'
    if (-not $hvOk) {
        dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart 2>$null | Out-Null
        Write-OK "Hyper-V включён"
    } else {
        Write-WARN "Hyper-V уже был включён"
    }
} catch {
    Write-WARN "Hyper-V недоступен (возможно Windows Home) — не критично для WSL2"
}

# ── Правила брандмауэра (80, 443) ────────────────────────
Write-Step "Правила брандмауэра (TCP 80, 443)..."
@(
    @{ Port = 80;  Name = "Guacamole-HTTP"  },
    @{ Port = 443; Name = "Guacamole-HTTPS" }
) | ForEach-Object {
    $rule = Get-NetFirewallRule -DisplayName $_.Name -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName $_.Name -Direction Inbound -Protocol TCP `
            -LocalPort $_.Port -Action Allow `
            -Profile @('Domain','Private','Public') | Out-Null
        Write-OK "Правило '$($_.Name)' (TCP $($_.Port)) создано"
    } else {
        Write-WARN "Правило '$($_.Name)' уже существует"
    }
}

# ── RDP ─────────────────────────────────────────────────
Write-Step "Проверка RDP..."
$rdp = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
if ($rdp -ne 0) {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name fDenyTSConnections -Value 0
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
    Write-OK "RDP включён"
} else {
    Write-WARN "RDP уже был включён"
}

# ── Итог ────────────────────────────────────────────────
Write-Host ""
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host "  ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА" -ForegroundColor Yellow
Write-Host "  После ребута: stage2-wsl-install.ps1" -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow

if ($Reboot) {
    Write-Host "Перезагрузка через 10 секунд..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Write-Host ""
    Write-Host "Запусти вручную:" -ForegroundColor White
    Write-Host "  Restart-Computer -Force" -ForegroundColor White
    Write-Host "Или сразу с перезагрузкой:" -ForegroundColor White
    Write-Host "  .\stage1-features.ps1 -Reboot" -ForegroundColor White
}
