# Likray\start.ps1 -- starts backend, SPA-frontend and SSH tunnels in one shot.
# Idempotent: safe to re-run -- kills the previous instance first.

param([switch]$NoFrontendBuild)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$RepoRoot    = Split-Path $ProjectRoot -Parent
$Backend     = Join-Path $ProjectRoot "backend"
$Frontend    = Join-Path $ProjectRoot "frontend"
$Runtime     = Join-Path $ProjectRoot ".runtime"
$Venv        = Join-Path $RepoRoot   ".venv\Scripts\python.exe"
$ApiClient   = Join-Path $Frontend   "lib\core\api\api_client.dart"
$BuildWeb    = Join-Path $Frontend   "build\web"
$SwFile      = Join-Path $BuildWeb   "flutter_service_worker.js"
$SpaScript   = "C:\temp\spa_server.py"

New-Item -ItemType Directory -Path $Runtime -Force | Out-Null

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "ERROR: $m" -ForegroundColor Red }

# ---------- 0. Sanity ----------
Write-Step "Checking environment"

if (-not (Test-Path $Venv)) {
    Write-Err "Python venv not found: $Venv"
    Write-Err "Create it: py -m venv .venv && .venv\Scripts\pip install -r Likray\backend\requirements.txt"
    exit 1
}
Write-Ok "venv: $Venv"

$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $ssh) {
    Write-Err "ssh.exe not in PATH."
    Write-Err "Install OpenSSH Client: Settings -> Apps -> Optional Features -> Add -> OpenSSH Client."
    exit 1
}
Write-Ok "ssh: $($ssh.Source)"

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter -and (Test-Path "C:\flutter\bin\flutter.bat")) {
    $env:Path = "C:\flutter\bin;$env:Path"
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
}
if (-not $flutter) {
    Write-Err "flutter not found. Unzip SDK to C:\flutter and add C:\flutter\bin to PATH."
    exit 1
}
Write-Ok "flutter: $($flutter.Source)"

if (-not (Test-Path $SpaScript)) {
    Write-Err "$SpaScript missing (SPA fallback server). Put it there."
    exit 1
}

# ---------- 1. Cleanup ----------
Write-Step "Stopping previous instances"

Get-ChildItem -Path $Runtime -Filter "*.pid" -ErrorAction SilentlyContinue | ForEach-Object {
    $pidVal = (Get-Content $_.FullName -ErrorAction SilentlyContinue) -as [int]
    if ($pidVal) { Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue }
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

foreach ($port in 8000, 5000) {
    Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
}

Get-CimInstance Win32_Process -Filter "Name='ssh.exe' OR Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match "localhost\.run|trycloudflare") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Milliseconds 700
Write-Ok "old processes stopped"

# ---------- 2. Backend ----------
Write-Step "Starting backend (uvicorn) on 127.0.0.1:8000"
$backendLog = Join-Path $Runtime "backend.log"
"" | Out-File -FilePath $backendLog -Encoding utf8 -Force
$env:PYTHONIOENCODING = "utf-8"

$backendProc = Start-Process -FilePath $Venv `
    -ArgumentList @("-m","uvicorn","app.main:app","--host","127.0.0.1","--port","8000") `
    -WorkingDirectory $Backend `
    -WindowStyle Hidden `
    -RedirectStandardOutput $backendLog `
    -RedirectStandardError (Join-Path $Runtime "backend.err.log") `
    -PassThru
$backendProc.Id | Out-File (Join-Path $Runtime "backend.pid") -Encoding ascii
Write-Ok "uvicorn PID $($backendProc.Id) (log: .runtime\backend.log)"

$deadline = (Get-Date).AddSeconds(30)
$healthOk = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:8000/api/v1/health" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $healthOk = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 400
}
if (-not $healthOk) {
    Write-Err "Backend did not start in 30s. See .runtime\backend.log"
    exit 1
}
Write-Ok "GET /api/v1/health -> 200"

# ---------- helper ----------
function Start-LhrTunnel($localPort, $tag) {
    $log = Join-Path $Runtime "tunnel-$tag.log"
    "" | Out-File -FilePath $log -Encoding utf8 -Force
    # -tt forces a PTY: localhost.run only emits the URL line over a PTY-attached
    # session. Without it the welcome banner shows up but the actual
    # "<id>.lhr.life tunneled..." line is never sent.
    $sshArgs = @(
        "-o","StrictHostKeyChecking=no",
        "-o","UserKnownHostsFile=NUL",
        "-o","ServerAliveInterval=30",
        "-tt",
        "-R","80:localhost:$localPort",
        "nokey@localhost.run"
    )
    $p = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs `
        -WindowStyle Hidden `
        -RedirectStandardOutput $log `
        -RedirectStandardError (Join-Path $Runtime "tunnel-$tag.err.log") `
        -PassThru
    $p.Id | Out-File (Join-Path $Runtime "tunnel-$tag.pid") -Encoding ascii

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        $content = (Get-Content $log -Raw -ErrorAction SilentlyContinue) +
                   (Get-Content (Join-Path $Runtime "tunnel-$tag.err.log") -Raw -ErrorAction SilentlyContinue)
        if ($content -and ($content -match "https://([a-z0-9]+\.lhr\.life)")) {
            return @{ Url = "https://$($matches[1])"; Pid = $p.Id }
        }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# ---------- 3. Backend tunnel ----------
Write-Step "SSH tunnel for backend (localhost.run)"
$beTun = Start-LhrTunnel -localPort 8000 -tag "backend"
if (-not $beTun) {
    Write-Warn "first attempt failed -- retrying once"
    $oldPid = (Get-Content (Join-Path $Runtime "tunnel-backend.pid") -ErrorAction SilentlyContinue) -as [int]
    if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    $beTun = Start-LhrTunnel -localPort 8000 -tag "backend"
}
if (-not $beTun) {
    Write-Err "Backend SSH tunnel did not come up (see .runtime\tunnel-backend.log)."
    exit 1
}
$BackendUrl = $beTun.Url
Write-Ok "backend public: $BackendUrl"

# ---------- 4. Patch api_client.dart ----------
Write-Step "Writing backend URL into the frontend"
$bak = "$ApiClient.bak"
if (-not (Test-Path $bak)) { Copy-Item $ApiClient $bak; Write-Ok ".bak created: $bak" }
$content = Get-Content $ApiClient -Raw -Encoding utf8
$pattern = "const String kApiBaseUrl = '[^']+';"
$replacement = "const String kApiBaseUrl = '$BackendUrl/api/v1';"
$new = [regex]::Replace($content, $pattern, $replacement)
[IO.File]::WriteAllText($ApiClient, $new, [Text.UTF8Encoding]::new($false))
Write-Ok "kApiBaseUrl -> $BackendUrl/api/v1"

# ---------- 5. Build web ----------
# flutter.bat is invoked through cmd /c with output redirected to a file --
# NOT through a PowerShell pipeline. The PowerShell `2>&1 | Out-Null` form
# wraps each native stderr line in a NativeCommandError; combined with
# $ErrorActionPreference = 'Stop' it aborts the script on the first warning.
$buildOk = $false
if (-not $NoFrontendBuild) {
    Write-Step "flutter build web (60-180s)"
    $buildLog    = Join-Path $Runtime "flutter-build.log"
    $buildErrLog = Join-Path $Runtime "flutter-build.err.log"
    "" | Out-File $buildLog -Encoding utf8 -Force
    "" | Out-File $buildErrLog -Encoding utf8 -Force
    # Run flutter.bat directly. Start-Process -Wait blocks the script
    # until exit and returns ExitCode via -PassThru. Native stderr is
    # captured into a file (no PowerShell pipeline involvement),
    # bypassing $ErrorActionPreference = 'Stop'.
    $flutterBat = $flutter.Source
    $proc = Start-Process -FilePath $flutterBat `
        -ArgumentList @("build","web","--pwa-strategy=none") `
        -WorkingDirectory $Frontend `
        -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $buildLog `
        -RedirectStandardError  $buildErrLog
    if ($proc.ExitCode -eq 0) {
        $buildOk = $true
        Write-Ok "build/web updated"
    } else {
        Write-Warn "flutter build exit $($proc.ExitCode) -- see .runtime\flutter-build.log"
    }
} else {
    Write-Warn "skipped flutter build (-NoFrontendBuild)"
}

# Sanity / fallback: bundle MUST contain the current backend hostname.
# If build succeeded -- it always will. If build was skipped or failed,
# we still proceed if the existing bundle happens to reference the same
# backend hostname (rare lucky case after a tunnel restart).
$bundle = Join-Path $BuildWeb "main.dart.js"
$backendHost = ([System.Uri]$BackendUrl).Host
$bundleHasUrl = $false
if (Test-Path $bundle) {
    # Read entire file as text and search via String.Contains.
    # Select-String reads line-by-line and chokes on the 3 MB single-line
    # minified JS, returning false even when the substring is present.
    $bundleText = [IO.File]::ReadAllText($bundle, [Text.Encoding]::UTF8)
    if ($bundleText.Contains($backendHost)) { $bundleHasUrl = $true }
}
if (-not $bundleHasUrl) {
    if ($buildOk) {
        Write-Err "Build succeeded but bundle does not reference $backendHost"
        exit 1
    }
    Write-Err "Bundle does not reference current backend host ($backendHost) and rebuild was skipped/failed."
    Write-Err "Run manually: cd Likray\frontend; flutter build web --pwa-strategy=none"
    exit 1
}
Write-Ok "main.dart.js references current backend host ($backendHost)"

# Kill-switch service worker (build overwrites it each time)
$swCode = @"
// Kill-switch service worker.
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.map((n) => caches.delete(n)));
    await self.registration.unregister();
    const cs = await self.clients.matchAll({ type: 'window' });
    for (const c of cs) { try { c.navigate(c.url); } catch (_) {} }
  })());
});
self.addEventListener('fetch', (event) => event.respondWith(fetch(event.request)));
"@
[IO.File]::WriteAllText($SwFile, $swCode, [Text.UTF8Encoding]::new($false))
Write-Ok "kill-switch service worker installed"

# ---------- 6. SPA server ----------
Write-Step "Starting SPA server on 127.0.0.1:5000"
$spaLog = Join-Path $Runtime "spa.log"
"" | Out-File $spaLog -Encoding utf8 -Force
$spaProc = Start-Process -FilePath $Venv `
    -ArgumentList @($SpaScript, "5000", $BuildWeb) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $spaLog `
    -RedirectStandardError (Join-Path $Runtime "spa.err.log") `
    -PassThru
$spaProc.Id | Out-File (Join-Path $Runtime "spa.pid") -Encoding ascii

$deadline = (Get-Date).AddSeconds(15)
$spaOk = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:5000/" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $spaOk = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 300
}
if (-not $spaOk) { Write-Err "SPA did not start"; exit 1 }
Write-Ok "SPA server PID $($spaProc.Id)"

# ---------- 7. Frontend tunnel ----------
Write-Step "SSH tunnel for frontend (localhost.run)"
$feTun = Start-LhrTunnel -localPort 5000 -tag "frontend"
if (-not $feTun) {
    Write-Warn "first attempt failed -- retrying once"
    $oldPid = (Get-Content (Join-Path $Runtime "tunnel-frontend.pid") -ErrorAction SilentlyContinue) -as [int]
    if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    $feTun = Start-LhrTunnel -localPort 5000 -tag "frontend"
}
if (-not $feTun) {
    Write-Err "Frontend SSH tunnel did not come up (see .runtime\tunnel-frontend.log)."
    exit 1
}
$FrontendUrl = $feTun.Url
Write-Ok "frontend public: $FrontendUrl"

# ---------- 8. Final ----------
$FrontendUrl | Out-File (Join-Path $Runtime "frontend-url.txt") -Encoding ascii
$BackendUrl  | Out-File (Join-Path $Runtime "backend-url.txt")  -Encoding ascii

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "Public URL :  $FrontendUrl/admin/login" -ForegroundColor Green
Write-Host "Login      :  admin / <your password>" -ForegroundColor Green
Write-Host "Local      :  http://localhost:5000" -ForegroundColor Green
Write-Host "Backend doc:  $BackendUrl/docs" -ForegroundColor Green
Write-Host "Stop all   :  .\stop.ps1" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
