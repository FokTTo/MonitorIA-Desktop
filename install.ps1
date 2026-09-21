# Monitor IA — instalador cliente
# Chamado por INSTALAR.cmd  OU  irm .../install.ps1 | iex
$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Refresh-Path {
    # Recarrega PATH do registo — winget/instaladores mudam Machine/User Path
    # mas o processo actual ainda tem o Path antigo.
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($machine -or $user) {
        $env:Path = @($machine, $user) -join ";"
    }
    # py.exe launcher (Windows) tambem pode estar no Path novo
    $pyLauncherDirs = @(
        "$env:LOCALAPPDATA\Programs\Python\Launcher",
        "$env:ProgramFiles\Python312",
        "$env:ProgramFiles\Python313",
        "$env:ProgramFiles\Python314"
    )
    foreach ($d in $pyLauncherDirs) {
        if ($d -and (Test-Path $d) -and ($env:Path -notlike "*$d*")) {
            $env:Path = "$d;$env:Path"
        }
    }
}

function Find-RealPython {
    Refresh-Path
    $candidates = New-Object System.Collections.Generic.List[string]

    # 1) py launcher (funciona mesmo com Path antigo)
    foreach ($args in @("-3", "-3.14", "-3.13", "-3.12", "")) {
        try {
            if ($args) {
                $p = & py $args -c "import sys; print(sys.executable)" 2>$null
            } else {
                $p = & py -c "import sys; print(sys.executable)" 2>$null
            }
            if ($p) { [void]$candidates.Add($p.Trim()) }
        } catch {}
    }

    # 2) python no Path já refresado
    try {
        $p = & python -c "import sys; print(sys.executable)" 2>$null
        if ($p) { [void]$candidates.Add($p.Trim()) }
    } catch {}
    try {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { [void]$candidates.Add($cmd.Source) }
    } catch {}

    # 3) Caminhos tipicos (winget / python.org / Microsoft Store unpack)
    $fixed = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.12-64\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.13-64\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe",
        "$env:LOCALAPPDATA\Python\bin\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "$env:ProgramFiles\Python314\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe"
    )
    foreach ($c in $fixed) { if ($c) { [void]$candidates.Add($c) } }

    # 4) Pesquisa limitada sob pastas oficiais (cobre versões novas)
    $roots = @(
        "$env:LOCALAPPDATA\Programs\Python",
        "$env:LOCALAPPDATA\Python",
        "$env:ProgramFiles"
    )
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch "WindowsApps|\\Doc\\|\\Test" } |
                Select-Object -First 12 |
                ForEach-Object { [void]$candidates.Add($_.FullName) }
        } catch {}
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c) -and ($c -notmatch "WindowsApps")) {
            return $c
        }
    }
    return $null
}

function Wait-ForPython {
    param([int]$Attempts = 12, [int]$DelaySec = 3)
    for ($i = 1; $i -le $Attempts; $i++) {
        Refresh-Path
        $py = Find-RealPython
        if ($py) { return $py }
        Write-Host "  A procura do Python ($i/$Attempts) — o Path ainda esta a actualizar..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds $DelaySec
    }
    return $null
}

function Install-PythonWinget {
    Write-Step "Python nao encontrado — a instalar via winget (oficial Microsoft)..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget nao disponivel. Instale Python em https://www.python.org/downloads/ (marque Add python.exe to PATH) e volte a correr INSTALAR.cmd (nesta mesma pasta)."
    }
    & winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        Write-Host "  winget exit=$LASTEXITCODE — a tentar encontrar Python na mesma..." -ForegroundColor DarkYellow
    }
    Write-Step "Python instalado — a continuar na mesma janela (sem reabrir CMD)..."
    $py = Wait-ForPython -Attempts 15 -DelaySec 2
    if (-not $py) {
        # Ultima tentativa: instalar tambem o launcher / outra versao
        try {
            & winget install -e --id Python.Launcher --accept-package-agreements --accept-source-agreements --disable-interactivity
        } catch {}
        $py = Wait-ForPython -Attempts 8 -DelaySec 2
    }
    if (-not $py) {
        throw "Python foi instalado mas ainda nao aparece neste processo. Corra INSTALAR.cmd outra vez NESTA pasta (nao precisa de instalar Python de novo)."
    }
    return $py
}

function New-DesktopShortcut([string]$Root, [string]$PythonExe) {
    # SSOT: desktop_app.win_shell.install_shortcuts
    # — pythonw absoluto + bootstrap + IconLocation Bitcoin + AppUserModelID
    # (evita pin da taskbar a apontar para pythonw sem args / ícone genérico)
    $code = @"
from pathlib import Path
from desktop_app.win_shell import install_shortcuts
print(install_shortcuts(Path(r'$Root'), python_exe=Path(r'$PythonExe')))
"@
    & $PythonExe -c $code
    if ($LASTEXITCODE -ne 0) {
        throw "Falha a criar atalho Monitor IA (win_shell.install_shortcuts)."
    }
    Write-Host "Atalho Desktop + Menu Iniciar: Monitor IA (launcher sem args + icone Bitcoin)"
    Write-Host "Para fixar na barra: clique direito no atalho do Ambiente de Trabalho / Menu Iniciar -> Fixar."
    Write-Host "Depois feche o app e reabra pelo pin (nao fixe a partir da janela aberta)."
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
