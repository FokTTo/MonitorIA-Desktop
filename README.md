# Monitor IA — Desktop (downloads)

Pacote **sem** `.exe` / `.vbs` / `.cmd` / `.ps1` no ZIP — reduz falsos positivos
do Defender / Chrome Safe Browsing / Smart App Control.

## Instalar

1. Abra a [última release](https://github.com/FokTTo/MonitorIA-Desktop/releases/latest)
2. Descarregue **`MonitorIA_Para_Instalar_2026.09.20.16.zip`**
3. Extraia para `Documentos\MonitorIA` (ou pasta permanente)
4. Abra **COMECE_AQUI.txt** e cole o comando no PowerShell:

```powershell
cd "$env:USERPROFILE\Documents\MonitorIA"
irm https://raw.githubusercontent.com/FokTTo/MonitorIA-Desktop/main/install.ps1 | iex
```

5. O app abre sozinho — crie conta com email

Actualizações seguintes: automáticas ao abrir o atalho «Monitor IA».

## Porque nao ha instalador no ZIP?

Scripts `.vbs`/`.cmd`/`.ps1` e EXEs sem assinatura sao marcados como virus
quando vêm da Internet. O instalador fica em `install.ps1` no GitHub (raw);
colar no PowerShell nao e um ficheiro descarregado.

## Nao use

Pacotes antigos com `MonitorIA.exe` / `1_INSTALAR_AQUI.vbs` / `.cmd`.

Versão actual: **2026.09.20.16**
