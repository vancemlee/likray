# Likray\stop.ps1 — кладёт всё что подняла start.ps1.
$ErrorActionPreference = 'Continue'
$Runtime = Join-Path $PSScriptRoot '.runtime'

Write-Host '==> Останавливаю Likray' -ForegroundColor Cyan

# 1. По PID-файлам
if (Test-Path $Runtime) {
    Get-ChildItem $Runtime -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $pidVal = (Get-Content $_.FullName -ErrorAction SilentlyContinue) -as [int]
        if ($pidVal) {
            try {
                Stop-Process -Id $pidVal -Force -ErrorAction Stop
                Write-Host "    killed PID $pidVal ($($_.BaseName))" -ForegroundColor Green
            } catch {
                Write-Host "    PID $pidVal ($($_.BaseName)) уже не запущен" -ForegroundColor Yellow
            }
        }
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# 2. Belt-and-suspenders: что слушает 8000/5000
foreach ($port in 8000, 5000) {
    Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object {
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
            Write-Host "    killed PID $_ on port $port" -ForegroundColor Green
        }
}

# 3. Заблудшие ssh-туннели в localhost.run
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match 'localhost\.run') } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "    killed ssh-туннель PID $($_.ProcessId)" -ForegroundColor Green
    }

Write-Host '==> Готово' -ForegroundColor Green
