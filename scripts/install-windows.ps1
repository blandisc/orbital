# Instala Orbital en Windows (Legion Go) y lo configura para arrancar al iniciar sesión.
# Uso (PowerShell): powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 [-NoStartup]
param([switch]$NoStartup)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $repo ".venv"

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando Python 3.12 con winget..."
    winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    # winget no actualiza el PATH de esta sesión: lo recargamos para encontrar py.
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
}

py -3 -m venv $venv
& "$venv\Scripts\python.exe" -m pip install --upgrade pip
& "$venv\Scripts\python.exe" -m pip install -e $repo

$configDir = Join-Path $env:APPDATA "orbital"
$configFile = Join-Path $configDir "config.yaml"
if (-not (Test-Path $configFile)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    # Con Python y no con Get-Content/Set-Content: PowerShell 5.1 lee el archivo como ANSI
    # (rompe los acentos) y escribe UTF-8 con BOM.
    & "$venv\Scripts\python.exe" -c "import secrets, sys, pathlib; src, dst = map(pathlib.Path, sys.argv[1:]); dst.write_text(src.read_text(encoding='utf-8').replace('CAMBIA-ESTE-TOKEN', secrets.token_urlsafe(32)), encoding='utf-8')" (Join-Path $repo "config.example.yaml") $configFile
    Write-Host "Config creada en $configFile (edita las rutas de tus emuladores)."
}

if ($NoStartup) {
    Write-Host "Listo (sin acceso directo de inicio). Pruébalo con: $venv\Scripts\python.exe -m orbital"
    exit 0
}

# Arranca con Windows y también tiene ícono en el escritorio. Si cierras su ventana, Orbital se
# cierra (no se reabre sola); para volver, el ícono.
$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath("Startup"), [Environment]::GetFolderPath("Desktop"))) {
    $lnk = $shell.CreateShortcut((Join-Path $folder "Orbital.lnk"))
    $lnk.TargetPath = "$venv\Scripts\pythonw.exe"
    $lnk.Arguments = "-m orbital"
    $lnk.WorkingDirectory = $repo
    $lnk.IconLocation = "$repo\orbital\web\icons\orbital.ico"
    $lnk.Save()
}
Write-Host "Listo: Orbital arranca con Windows y está en tu escritorio. Al cerrar su ventana, se cierra."
