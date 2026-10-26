"""La hora de los emuladores, la misma que la de la computadora.

Los de Switch guardan su propio reloj: Ryujinx traía la zona «UTC» (enseñaba 6 horas de más en México) y los de la familia
de yuzu (Eden, Sudachi) pueden tener un reloj propio («Custom RTC») o una zona fija. Antes de abrir uno, Orbital deja su
configuración en la zona de esta computadora y sin reloj propio. Solo toca esas llaves, y solo si están mal. Dolphin,
PPSSPP, xemu, RPCS3 y mGBA ya usan la hora de la computadora.
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import re
import sys
from pathlib import Path

log = logging.getLogger(__name__)

# Zona de Windows -> zona IANA (la que entienden los emuladores). Lo que no esté aquí: «Etc/GMT±N» por la diferencia.
WINDOWS_TO_IANA = {
    "Central Standard Time (Mexico)": "America/Mexico_City", "Eastern Standard Time (Mexico)": "America/Cancun",
    "Mountain Standard Time (Mexico)": "America/Mazatlan", "Pacific Standard Time (Mexico)": "America/Tijuana",
    "Central Standard Time": "America/Chicago", "Eastern Standard Time": "America/New_York",
    "Mountain Standard Time": "America/Denver", "US Mountain Standard Time": "America/Phoenix",
    "Pacific Standard Time": "America/Los_Angeles", "Central America Standard Time": "America/Guatemala",
    "SA Pacific Standard Time": "America/Bogota", "SA Western Standard Time": "America/La_Paz",
    "Argentina Standard Time": "America/Buenos_Aires", "Pacific SA Standard Time": "America/Santiago",
    "E. South America Standard Time": "America/Sao_Paulo", "Venezuela Standard Time": "America/Caracas",
    "Romance Standard Time": "Europe/Madrid", "GMT Standard Time": "Europe/London", "UTC": "UTC",
}


def windows_zone() -> str | None:
    if sys.platform != "win32":
        return None
    try:
        import winreg  # type: ignore[import-not-found]

        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\TimeZoneInformation") as key:
            return str(winreg.QueryValueEx(key, "TimeZoneKeyName")[0]).strip("\x00 ")
    except OSError:
        return None


def local_zone(windows: str | None = None) -> str:
    """La zona de esta computadora en nombre IANA («America/Mexico_City»)."""
    name = windows if windows is not None else windows_zone()
    if name and name in WINDOWS_TO_IANA:
        return WINDOWS_TO_IANA[name]
    offset = datetime.datetime.now().astimezone().utcoffset() or datetime.timedelta()
    hours = round(offset.total_seconds() / 3600)
    return "UTC" if hours == 0 else f"Etc/GMT{'+' if hours < 0 else '-'}{abs(hours)}"  # Etc/GMT+6 = UTC−6


def sync_ryujinx(config: Path, zone: str) -> bool:
    """Config.json de Ryujinx: la zona de la computadora, siguiendo su reloj y sin desfase. True si cambió algo."""
    try:
        data = json.loads(config.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(data, dict) or "system_time_zone" not in data:
        return False
    want = {"system_time_zone": zone, "system_time_offset": 0, "match_system_time": True}
    if all(data.get(k) == v for k, v in want.items()):
        return False
    data.update(want)
    try:
        config.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    except OSError as exc:
        log.info("No pude poner la hora de Ryujinx en %s: %s", config, exc)
        return False
    return True


def sync_yuzu(config: Path) -> bool:
    """qt-config.ini de Eden/Sudachi (familia yuzu): sin reloj propio y con la zona automática. True si cambió algo."""
    try:
        text = config.read_text(encoding="utf-8")
    except OSError:
        return False
    fixed = re.sub(r"(?m)^custom_rtc_enabled=true\s*$", "custom_rtc_enabled=false", text)
    fixed = re.sub(r"(?m)^custom_rtc_enabled\\default=false\s*$", "custom_rtc_enabled\\\\default=true", fixed)
    fixed = re.sub(r"(?m)^time_zone_index=(?!0\s*$)\d+\s*$", "time_zone_index=0", fixed)  # 0 = automática
    if fixed == text:
        return False
    try:
        config.write_text(fixed, encoding="utf-8")
    except OSError as exc:
        log.info("No pude poner la hora de %s: %s", config, exc)
        return False
    return True


def _configs(exe: Path) -> tuple[list[Path], list[Path]]:
    """(los Config.json de Ryujinx, los qt-config.ini de la familia yuzu) que usa ese emulador: la carpeta portátil
    junto al ejecutable y la de AppData."""
    name = exe.name.lower()
    appdata = Path(os.environ.get("APPDATA", ""))
    folder = exe.parent
    if "ryujinx" in name:
        roots = [folder / "portable", appdata / "Ryujinx"]
        return [p for r in roots for p in [r / "Config.json", *sorted((r / "games").glob("*/Config.json"))] if p.is_file()], []
    for family in ("eden", "sudachi", "yuzu", "suyu", "citron"):
        if family in name or family in str(folder).lower():
            roots = [folder / "user" / "config", appdata / family / "config"]
            return [], [r / "qt-config.ini" for r in roots if (r / "qt-config.ini").is_file()]
    return [], []


def emulator_exe(argv: list[str]) -> Path:
    """El ejecutable del emulador, aunque se abra con un .cmd propio (launch-eden.cmd: el emulador está junto a él)."""
    exe = Path(argv[0])
    if exe.suffix.lower() == ".cmd":
        exe = exe.with_name(exe.stem.removeprefix("launch-") + ".exe")
    return exe


def sync_for(argv: list[str]) -> int:
    """Antes de abrir un emulador: su hora, la de la computadora. Cuántos archivos tocó. Nunca falla."""
    try:
        if not argv:
            return 0
        exe = emulator_exe(argv)
        ryujinx, yuzu = _configs(exe)
        if not ryujinx and not yuzu:
            return 0
        zone = local_zone()
        changed = sum(sync_ryujinx(p, zone) for p in ryujinx) + sum(sync_yuzu(p) for p in yuzu)
        if changed:
            log.info("Hora de %s: la de la computadora (%s) en %d archivo(s)", exe.stem, zone, changed)
        return changed
    except Exception:  # noqa: BLE001 - la hora nunca impide abrir un juego
        log.exception("No pude revisar la hora del emulador")
        return 0
