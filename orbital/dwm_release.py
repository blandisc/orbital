"""Liberar la memoria de video que Windows (DWM) se queda sin devolver, sin reiniciar la consola.

Con el driver de AMD de la Legion Go, cada ventana Vulkan que se cierra (un emulador de Switch, en ventana o a pantalla
completa) le deja a DWM ~100 MB que no suelta nunca (medido el 2026-10-26: Ryujinx +96 MB y Eden +128 MB por juego,
igual cerrándolo a la fuerza que con la X; ni «Optimizaciones para juegos en ventana» ni reiniciar el driver con
Win+Ctrl+Shift+B la devuelven). Lo único que la regresa es reiniciar DWM: Windows lo vuelve a abrir solo y la pantalla
parpadea un par de segundos. Eso pide administrador, así que se hace con una tarea de Windows que activas una vez (Windows
pregunta en ese momento) y luego Orbital la lanza sin volver a preguntar, solo cuando no estás jugando ni viendo nada.
"""

from __future__ import annotations

import logging
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

log = logging.getLogger(__name__)

TASK = r"\Orbital\Liberar video"
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

# Lo que corre como administrador al activarla: la tarea reinicia DWM con privilegios y nada más.
SETUP_SCRIPT = r"""
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\taskkill.exe" -Argument '/F /IM dwm.exe'
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskPath '\Orbital\' -TaskName 'Liberar video' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"""


def _schtasks(*args: str) -> bool:
    if sys.platform != "win32":
        return False
    try:
        result = subprocess.run(["schtasks", *args], capture_output=True, timeout=15, creationflags=NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.debug("schtasks %s: %s", args, exc)
        return False
    return result.returncode == 0


def available() -> bool:
    """¿Ya está activada (existe la tarea)?"""
    return _schtasks("/query", "/tn", TASK)


# Con DWM así de lleno, los videos se traban: el video se congela un momento, el audio sigue y el video corre para
# alcanzarlo (medido el 2026-10-27 con la misma película y la misma copia: con 12.7 GB, 18 cuadros perdidos en 15 min en
# tres tirones; recién liberado, 0 en 45 min). Es lo mismo que pide la liberación en reposo (health.RELEASE_MB).
FRESH_MB = 3000
BACK_AFTER = 2.5  # s que tarda Windows en volver a dibujar tras reiniciar DWM (la pantalla parpadea en ese rato)


def release_if_full(moment: str = "antes del video", measure=None, sleep=time.sleep) -> bool:
    """En un momento en que el parpadeo no estorba (antes de abrir un video, con la pantalla de carga; al volver de un
    juego, cuando la tele ya va a parpadear al regresar a 4K): si DWM retiene de más, se reinicia ahí. Solo con la tarea
    activada. Devuelve si lo hizo. La fuga es del driver de AMD (32.0.23044.19, del 2026-09-30): ver el informe de la
    investigación en el commit que agregó esto."""
    if measure is None:
        from .health import dwm_gpu_mb as measure
    dwm = measure()
    if not dwm or dwm[0] < FRESH_MB or not available():
        return False
    if not run():
        return False
    log.info("Memoria de video liberada %s (DWM tenía %d MB)", moment, dwm[0])
    sleep(BACK_AFTER)
    return True


def run() -> bool:
    """Reinicia DWM ahora (la pantalla parpadea). Solo si la tarea existe."""
    ok = _schtasks("/run", "/tn", TASK)
    log.info("Liberar memoria de video: %s", "DWM reiniciado" if ok else "no se pudo (¿está activada?)")
    return ok


def setup() -> bool:
    """Crea la tarea. Windows muestra su aviso de permiso; si dices que no, no pasa nada. Devuelve si quedó activada."""
    if sys.platform != "win32":
        return False
    script = Path(tempfile.gettempdir()) / "orbital-liberar-video.ps1"
    script.write_text(SETUP_SCRIPT, encoding="utf-8")
    inner = f"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{script}\""
    command = f"Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '{inner}'"
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", command], capture_output=True, timeout=300,
                       creationflags=NO_WINDOW, env={**os.environ})
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.warning("No pude activar «Liberar memoria de video»: %s", exc)
    finally:
        script.unlink(missing_ok=True)
    ok = available()
    log.info("Liberar memoria de video: %s", "activado" if ok else "no se activó (no se dio el permiso)")
    return ok
