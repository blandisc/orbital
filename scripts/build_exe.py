"""Empaqueta Orbital como Orbital.exe (carpeta dist/Orbital), sin depender de Python ni de git instalados.

    pip install pyinstaller
    python scripts/build_exe.py

Lleva dentro Python, sus librerías, la interfaz y el reproductor (mpv, si está en %LOCALAPPDATA%\\orbital\\mpv): la
carpeta se copia a cualquier Windows 11 (Edge ya viene con Windows). Tu configuración sigue en %APPDATA%\\Orbital, así
que una copia nueva usa tus ajustes de siempre. Junto al programa queda «Instalar Orbital.cmd»: lo copia a
%LOCALAPPDATA%\\Programs\\Orbital y lo pone en el inicio de Windows.

Ojo: esa copia no se actualiza con «Actualizar Orbital» (eso usa git); para actualizarla se vuelve a empaquetar.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist" / "Orbital"

INSTALL_CMD = r"""@echo off
rem Instala Orbital (esta carpeta) en %LOCALAPPDATA%\Programs\Orbital y lo abre al iniciar Windows.
setlocal
set "DEST=%LOCALAPPDATA%\Programs\Orbital"
echo Copiando Orbital a %DEST% ...
robocopy "%~dp0." "%DEST%" /E /NFL /NDL /NJH /NJS /XF "Instalar Orbital.cmd" >nul
if %ERRORLEVEL% GEQ 8 (echo No pude copiar Orbital. & pause & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Orbital.lnk');" ^
  "$s.TargetPath='%DEST%\Orbital.exe'; $s.WorkingDirectory='%DEST%'; $s.IconLocation='%DEST%\Orbital.exe,0'; $s.Save()"
echo Listo: Orbital se abre al iniciar Windows. Abriendolo ahora...
start "" "%DEST%\Orbital.exe"
"""


def main() -> None:
    import PyInstaller.__main__

    entry = ROOT / "build" / "orbital_entry.py"
    entry.parent.mkdir(exist_ok=True)
    entry.write_text("from orbital.__main__ import main\n\nmain()\n", encoding="utf-8")
    sep = ";" if sys.platform == "win32" else ":"
    PyInstaller.__main__.run([
        str(entry), "--name", "Orbital", "--noconfirm", "--clean", "--windowed",
        "--icon", str(ROOT / "orbital" / "web" / "icons" / "orbital.ico"),
        "--paths", str(ROOT),
        "--add-data", f"{ROOT / 'orbital' / 'web'}{sep}orbital/web",
        "--add-data", f"{ROOT / 'orbital' / 'remote_input_page.html'}{sep}orbital",
        "--add-data", f"{ROOT / 'alexa'}{sep}alexa",
        "--collect-submodules", "orbital",
        "--collect-submodules", "uvicorn",
        "--collect-submodules", "winrt",  # «Ahora suena» (los controles de medios de Windows)
        "--distpath", str(ROOT / "dist"), "--workpath", str(ROOT / "build" / "pyinstaller"),
        "--specpath", str(ROOT / "build"),
    ])
    # El reproductor, dentro: Orbital.exe lo busca en su propia carpeta (playback.find_mpv).
    mpv = Path(os.environ.get("LOCALAPPDATA", "")) / "orbital" / "mpv"
    if (mpv / "mpv.exe").exists():
        shutil.copytree(mpv, DIST / "mpv", dirs_exist_ok=True)
        print("Con el reproductor (mpv) adentro")
    else:
        print("Aviso: no encontré mpv en %LOCALAPPDATA%\\orbital\\mpv; Orbital.exe usará el del sistema si lo hay")
    (DIST / "Instalar Orbital.cmd").write_text(INSTALL_CMD.replace("\n", "\r\n"), encoding="utf-8")
    print("Listo:", DIST / "Orbital.exe")


if __name__ == "__main__":
    main()
