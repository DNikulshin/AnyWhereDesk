#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Восстановление WSL — запускать из SSH -> PowerShell
    Сценарии: WSL завис, не стартует, kernel устарел, LxssManager не работает
    Команда: powershell -ExecutionPolicy Bypass -File recovery\recover-wsl.ps1
#>
param(
    [switch]$Force  # Принудительный полный сброс без подтверждений
)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = New-Object System.Text.UTF8Encoding $false


function Write-Step { param($m) Write-Host "`n[$(Get-Date -f 'HH:mm:ss')] >> $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-FAIL { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Blue
Write-Host "  AnyWhereDesk | Восстановление WSL" -ForegroundColor Blue
Write-Host "=============================================" -ForegroundColor Blue

# ── Шаг 1: Диагностика ──────────────────────────────────
Write-Step "Диагностика текущего состояния..."

$wslRunning = $false
try {
    $testResult = wsl -d Ubuntu echo "test" 2>$null
    if ($testResult -eq "test") {
        Write-OK "WSL Ubuntu отвечает нормально — восстановление не требуется"
        Write-WARN "Если ты видишь проблему — запусти: recovery\status.ps1"
        exit 0
    }
} catch { }
Write-WARN "WSL Ubuntu не отвечает — начинаем восстановление"

# ── Шаг 2: Завершение зависших процессов ────────────────
Write-Step "Остановка зависших WSL-процессов..."
try {
    wsl --shutdown
    Write-OK "wsl --shutdown выполнен"
    Start-Sleep -Seconds 5
} catch {
    Write-WARN "wsl --shutdown: $_"
}

# ── Шаг 3: Перезапуск LxssManager ────────────────────────
Write-Step "Перезапуск службы LxssManager..."
try {
    Restart-Service LxssManager -Force -ErrorAction Stop
    Write-OK "LxssManager перезапущен"
    Start-Sleep -Seconds 3
} catch {
    Write-WARN "LxssManager: $_"
}

# ── Шаг 4: Проверка после базового восстановления ────────
Write-Step "Проверка WSL после перезапуска службы..."
try {
    $testResult = wsl -d Ubuntu echo "test" 2>$null
    if ($testResult -eq "test") {
        Write-OK "WSL Ubuntu восстановлен (базовый сброс помог)"
        Write-Host ""
        Write-Host "  Перезапусти Docker и стек:" -ForegroundColor White
        Write-Host "  wsl -d Ubuntu bash -c 'sudo service docker start && cd ~/guac-stack && docker compose up -d'" -ForegroundColor White
        exit 0
    }
} catch { }
Write-WARN "Базовый сброс не помог — пробуем обновление kernel..."

# ── Шаг 5: Обновление WSL kernel ────────────────────────
Write-Step "Обновление WSL kernel..."
try {
    wsl --update
    Write-OK "WSL kernel обновлён"
    Restart-Service LxssManager -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
} catch {
    Write-WARN "Обновление kernel: $_"
}

# ── Шаг 6: Повторная проверка ────────────────────────────
Write-Step "Повторная проверка после обновления kernel..."
try {
    $testResult = wsl -d Ubuntu echo "test" 2>$null
    if ($testResult -eq "test") {
        Write-OK "WSL Ubuntu восстановлен после обновления kernel"
        exit 0
    }
} catch { }
Write-WARN "Kernel-обновление не помогло — пробуем полный сброс WSL..."

# ── Шаг 7: Полный сброс WSL (ДЕСТРУКТИВНО — спрашиваем) ─
Write-Host ""
Write-Host "  !! ВНИМАНИЕ: полный сброс WSL уничтожит все данные Ubuntu !!" -ForegroundColor Red
Write-Host "  Данные guac-stack на Windows (/mnt/c/...) сохранятся." -ForegroundColor Yellow
Write-Host "  Потребуется повторный запуск stage2 + stage3 + stage5 + stage6" -ForegroundColor Yellow

if (-not $Force) {
    $confirm = Read-Host "`n  Выполнить полный сброс? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "  Сброс отменён. Следующие варианты:" -ForegroundColor Yellow
        Write-Host "    1. Перезагрузи Windows: Restart-Computer -Force" -ForegroundColor White
        Write-Host "    2. Проверь компоненты: stage1-features.ps1 (идемпотентен)" -ForegroundColor White
        exit 1
    }
}

Write-Step "Полный сброс WSL..."
try {
    wsl --unregister Ubuntu
    Write-OK "Ubuntu удалена из WSL"
} catch {
    Write-WARN "Ошибка unregister: $_"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host "  WSL сброшен. Необходимо:" -ForegroundColor Yellow
Write-Host "  1. stage2-wsl-install.ps1   (установка Ubuntu)" -ForegroundColor White
Write-Host "  2. stage3-wsl-configure.ps1 (настройка пользователя)" -ForegroundColor White
Write-Host "  3. SSH в Ubuntu: stage5-docker.sh" -ForegroundColor White
Write-Host "  4. SSH в Ubuntu: stage6-stack.sh" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Yellow
