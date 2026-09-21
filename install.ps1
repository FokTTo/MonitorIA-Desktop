# Monitor IA — instalador cliente (correr via: irm .../install.ps1 | iex)
# Nao descarregue este ficheiro para disco se o AV reclamar — cole o one-liner do COMECE_AQUI.txt
$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Find-RealPython {
    Refresh-Path
    $candidates = @()
    try {
        $p = & python -c "import sys; print(sys.executable)" 2>$null
        if ($p) { $candidates += $p.Trim() }
    } catch {}
    $candidates += @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.12-64\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.13-64\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe",
        "$env:LOCALAPPDATA\Python\bin\python.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c) -and ($c -notmatch "WindowsApps")) {
            return $c
        }
    }
    return $null
}

function Install-PythonWinget {
    Write-Step "Python nao encontrado — a instalar via winget (oficial Microsoft)..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget nao disponivel. Instale Python em https://www.python.org/downloads/ (marque Add to PATH) e volte a correr o comando."
    }
    & winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --disable-interactivity
    Refresh-Path
    Start-Sleep -Seconds 2
    $py = Find-RealPython
    if (-not $py) {
        throw "Python instalado mas nao encontrado. Feche o PowerShell, abra outro e volte a colar o comando."
    }
    return $py
}

function New-DesktopShortcut([string]$Root, [string]$PythonExe) {
    $dir = Split-Path -Parent $PythonExe
    $pyw = Join-Path $dir "pythonw.exe"
    if (-not (Test-Path $pyw)) { $pyw = $PythonExe }
    $appPy = Join-Path $Root "desktop_app\app.py"
    $icon = Join-Path $Root "desktop_app\assets\MonitorIA.ico"
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnk = Join-Path $desktop "Monitor IA.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $pyw
    $sc.Arguments = "`"$appPy`""
    $sc.WorkingDirectory = $Root
    $sc.WindowStyle = 1
    $sc.Description = "Monitor IA"
    if (Test-Path $icon) { $sc.IconLocation = "$icon,0" }
    $sc.Save()
    Write-Host "Atalho: $lnk"
}

$Root = (Get-Location).Path
$appProbe = Join-Path $Root "desktop_app\app.py"
if (-not (Test-Path $appProbe)) {
    throw "Pasta errada. cd para a pasta extraida do Monitor IA (deve existir desktop_app\app.py) e volte a colar o comando."
}

Write-Host "========================================"
Write-Host "  Monitor IA — instalacao"
Write-Host "========================================"
Write-Host "Pasta: $Root"

try {
    Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
} catch {}

$realPy = Find-RealPython
if (-not $realPy) {
    $realPy = Install-PythonWinget
}
Write-Step "Python OK: $realPy"

Write-Step "A instalar bibliotecas..."
& $realPy -m pip install -q --upgrade pip
$req = Join-Path $Root "requirements-desktop.txt"
& $realPy -m pip install -q -r $req

New-Item -ItemType Directory -Force -Path (Join-Path $Root "artifacts\desktop") | Out-Null

$iconScript = Join-Path $Root "scripts\make_desktop_icon.py"
if (Test-Path $iconScript) {
    & $realPy $iconScript
}

Write-Step "A criar atalho (so .lnk — sem .vbs)..."
New-DesktopShortcut -Root $Root -PythonExe $realPy

& $realPy -c "from desktop_app.auth import init_db; init_db(); print('OK base local')"

Write-Host ""
Write-Host "Instalacao concluida!" -ForegroundColor Green
Write-Host "A abrir o Monitor IA..."
Start-Process -FilePath $realPy -ArgumentList @((Join-Path $Root "desktop_app\app.py")) -WorkingDirectory $Root
Write-Host ""
