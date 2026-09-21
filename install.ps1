# Monitor IA — instalador cliente
# Chamado por INSTALAR.cmd  OU  irm .../install.ps1 | iex
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
        throw "winget nao disponivel. Instale Python em https://www.python.org/downloads/ (marque Add to PATH) e volte a correr INSTALAR.cmd."
    }
    & winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --disable-interactivity
    Refresh-Path
    Start-Sleep -Seconds 2
    $py = Find-RealPython
    if (-not $py) {
        throw "Python instalado mas nao encontrado. Feche esta janela, abra de novo o INSTALAR.cmd."
    }
    return $py
}

function New-DesktopShortcut([string]$Root, [string]$PythonExe) {
    $dir = Split-Path -Parent $PythonExe
    $pyw = Join-Path $dir "pythonw.exe"
    if (-not (Test-Path $pyw)) { $pyw = $PythonExe }
    $boot = Join-Path $Root "desktop_app\bootstrap_launch.py"
    if (-not (Test-Path $boot)) { $boot = Join-Path $Root "desktop_app\app.py" }
    $launcher = Join-Path $Root "ABRIR_MONITOR_IA.cmd"
    $icon = Join-Path $Root "desktop_app\assets\MonitorIA.ico"
    # Guarda caminho do Python para o launcher CMD
    $pyFile = Join-Path $Root "artifacts\desktop\python_path.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path $pyFile) | Out-Null
    Set-Content -LiteralPath $pyFile -Value $pyw -Encoding ascii

    # Launcher CMD: encontra Python e abre bootstrap (erros com MessageBox)
    $cmd = @"
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "LOG=%~dp0artifacts\desktop\last_launch.log"
if not exist "%~dp0artifacts\desktop" mkdir "%~dp0artifacts\desktop"
echo %date% %time% ABRIR >> "%LOG%"
set "PY="
if exist "%~dp0artifacts\desktop\python_path.txt" (
  set /p PY=<"%~dp0artifacts\desktop\python_path.txt"
)
if not defined PY set "PY=$pyw"
if not exist "%PY%" set "PY=$PythonExe"
if not exist "%PY%" (
  where pythonw >nul 2>&1 && for /f "delims=" %%i in ('where pythonw') do set "PY=%%i"
)
if not exist "%PY%" (
  where python >nul 2>&1 && for /f "delims=" %%i in ('where python') do set "PY=%%i"
)
if not exist "%PY%" (
  echo Sem Python. Corra INSTALAR.cmd de novo. >> "%LOG%"
  powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Python nao encontrado. Corra INSTALAR.cmd outra vez.','Monitor IA')"
  exit /b 1
)
echo Usando %PY% >> "%LOG%"
start "" /D "%~dp0" "%PY%" "%~dp0desktop_app\bootstrap_launch.py"
exit /b 0
"@
    # Normalizar newlines Windows
    $cmd = $cmd -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($launcher, $cmd, [System.Text.UTF8Encoding]::new($false))

    $wsh = New-Object -ComObject WScript.Shell
    # Ambiente de Trabalho
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnk = Join-Path $desktop "Monitor IA.lnk"
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $launcher
    $sc.WorkingDirectory = $Root
    $sc.WindowStyle = 7
    $sc.Description = "Monitor IA"
    if (Test-Path $icon) { $sc.IconLocation = "$icon,0" }
    $sc.Save()
    Write-Host "Atalho Desktop: $lnk"
    # Menu Iniciar
    try {
        $startDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
        if (Test-Path $startDir) {
            $slnk = Join-Path $startDir "Monitor IA.lnk"
            $sc2 = $wsh.CreateShortcut($slnk)
            $sc2.TargetPath = $launcher
            $sc2.WorkingDirectory = $Root
            $sc2.WindowStyle = 7
            $sc2.Description = "Monitor IA"
            if (Test-Path $icon) { $sc2.IconLocation = "$icon,0" }
            $sc2.Save()
            Write-Host "Atalho Iniciar: $slnk"
        }
    } catch {}
}

function Confirm-Continue {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $docs = [Environment]::GetFolderPath("MyDocuments")
        $destHint = Join-Path $docs "MonitorIA"
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Instalar o Monitor IA agora?`n`n" +
            "O app fica em:`n$destHint`n`n" +
            "Depois pode apagar a pasta extraida (ex.: Area de Trabalho).`n`n" +
            "Pode demorar alguns minutos (Python + bibliotecas).",
            "Monitor IA — Continuar a instalacao",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($r -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host "Instalacao cancelada."
            exit 0
        }
    } catch {
        # sem UI (ex.: ja veio do pause do INSTALAR.cmd) — segue
    }
}

function Move-ToPermanentInstall([string]$Source) {
    $docs = [Environment]::GetFolderPath("MyDocuments")
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE "Documents" }
    $Target = Join-Path $docs "MonitorIA"
    $srcFull = [System.IO.Path]::GetFullPath($Source).TrimEnd('\')
    $dstFull = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
    if ($srcFull -ieq $dstFull) {
        Write-Host "Ja esta na pasta permanente: $dstFull"
        return $dstFull
    }
    Write-Step "A copiar para pasta permanente..."
    Write-Host "Origem:  $srcFull"
    Write-Host "Destino: $dstFull"
    New-Item -ItemType Directory -Force -Path $dstFull | Out-Null
    # Sem /PURGE: preserva users.sqlite / sessao se ja existirem no destino
    & robocopy $srcFull $dstFull /E /XD __pycache__ .git /XF *.pyc /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Falha ao copiar para Documentos\MonitorIA (codigo robocopy=$LASTEXITCODE)."
    }
    $probe = Join-Path $dstFull "desktop_app\app.py"
    if (-not (Test-Path $probe)) {
        throw "Copia incompleta — falta desktop_app\app.py em $dstFull"
    }
    Write-Host "OK — instalacao permanente em Documentos\MonitorIA"
    Write-Host "Pode apagar a pasta temporaria: $srcFull"
    return $dstFull
}

$Source = (Get-Location).Path
$appProbe = Join-Path $Source "desktop_app\app.py"
if (-not (Test-Path $appProbe)) {
    throw "Pasta errada. Extraia o ZIP e corra INSTALAR.cmd DENTRO da pasta (deve existir desktop_app\app.py)."
}

Confirm-Continue

$Root = Move-ToPermanentInstall $Source
Set-Location -LiteralPath $Root

Write-Host "========================================"
Write-Host "  Monitor IA — instalacao"
Write-Host "========================================"
Write-Host "Pasta permanente: $Root"

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

Write-Step "A criar atalho (Desktop + Menu Iniciar)..."
New-DesktopShortcut -Root $Root -PythonExe $realPy

& $realPy -c "from desktop_app.auth import init_db; init_db(); print('OK base local')"

Write-Host ""
Write-Host "Instalacao concluida!" -ForegroundColor Green
Write-Host "Pasta permanente: $Root"
Write-Host "Atalho: Ambiente de Trabalho / Menu Iniciar -> Monitor IA"
Write-Host "Pode apagar a pasta temporaria do ZIP (ex.: Area de Trabalho)."
Write-Host "A abrir o Monitor IA..."
$boot = Join-Path $Root "desktop_app\bootstrap_launch.py"
if (-not (Test-Path $boot)) { $boot = Join-Path $Root "desktop_app\app.py" }
$pyw = Join-Path (Split-Path -Parent $realPy) "pythonw.exe"
if (-not (Test-Path $pyw)) { $pyw = $realPy }
Start-Process -FilePath $pyw -ArgumentList @($boot) -WorkingDirectory $Root
Write-Host ""
