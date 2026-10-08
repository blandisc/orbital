# Instala Orbital en Windows (Legion Go) y lo configura para arrancar al iniciar sesión.
# Uso (PowerShell): powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $repo ".venv"

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando Python 3.12 con winget..."
    winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
}

py -3 -m venv $venv
& "$venv\Scripts\python.exe" -m pip install --upgrade pip
& "$venv\Scripts\python.exe" -m pip install -e $repo

$configDir = Join-Path $env:APPDATA "orbital"
$configFile = Join-Path $configDir "config.yaml"
if (-not (Test-Path $configFile)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $token = & "$venv\Scripts\python.exe" -c "import secrets; print(secrets.token_urlsafe(32))"
    (Get-Content (Join-Path $repo "config.example.yaml")) -replace "CAMBIA-ESTE-TOKEN", $token |
        Set-Content -Encoding UTF8 $configFile
    Write-Host "Config creada en $configFile (edita las rutas de tus emuladores)."
}

# Acceso directo en la carpeta Inicio para que arranque con Windows.
$startup = [Environment]::GetFolderPath("Startup")
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path $startup "Orbital.lnk"))
$lnk.TargetPath = "$venv\Scripts\pythonw.exe"
$lnk.Arguments = "-m orbital"
$lnk.WorkingDirectory = $repo
$lnk.Save()
Write-Host "Listo. Orbital arrancará al iniciar sesión. Pruébalo ahora con: $venv\Scripts\python.exe -m orbital"
