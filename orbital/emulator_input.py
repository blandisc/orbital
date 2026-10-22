"""Los controles de los emuladores de Switch, como en una consola: el control con el que abres el juego es el Jugador 1.

Eden y Ryujinx guardan qué control es cada jugador por su identificador (marca y modelo), y Orbital los encontraba en el
orden en que alguien los dejó a mano: en Ryujinx los dos jugadores eran el GameSir (los de la Legion no hacían nada) y en
Eden el GameSir era el Jugador 2 (en un juego de uno, no respondía). Antes de abrir uno, Orbital acomoda los jugadores:
primero el control que usaste por última vez (el que apretó A para abrir), luego los demás encendidos. El mapeo de cada
modelo sale de lo que ya está en tus configuraciones (la global y las de cada juego): un modelo que nunca se configuró no
se inventa (se queda fuera y se anota). Y en todos, A es A, B es B, X es X y Y es Y, como dicen los botones.

Solo se escribe si algo cambia, y la primera vez se guarda una copia del archivo («.antes-de-orbital»).
"""

from __future__ import annotations

import json
import logging
import re
import shutil
from pathlib import Path

log = logging.getLogger(__name__)

Device = tuple[int, int]  # (marca, modelo): VendorId y ProductId del control
NINTENDO = 0x057E  # un Pro Controller ya trae los botones en su lugar de Switch: no se le toca A/B/X/Y
EDEN_PLAYERS = 8  # player_0 … player_7 (el 8 es el modo portátil)
RYUJINX_PLAYERS = 8
BACKUP = ".antes-de-orbital"

# SDL (con el driver XInput): 0 = A, 1 = B, 2 = X, 3 = Y, según lo que dice el botón.
EDEN_LABELS = {"button_a": 0, "button_b": 1, "button_x": 2, "button_y": 3}
RYUJINX_LABELS = {"button_a": "A", "button_b": "B", "button_x": "X", "button_y": "Y"}


def _le(hex4: str) -> int:
    """«ef17» (dos bytes al revés, como los guarda SDL) -> 0x17EF."""
    return int(hex4[2:4] + hex4[0:2], 16)


def _backup(path: Path) -> None:
    copy = path.with_name(path.name + BACKUP)
    if not copy.exists():
        shutil.copy2(path, copy)


def assign(order: list[Device], known: set[Device]) -> list[tuple[Device, int]]:
    """Los jugadores, en orden: cada control con un mapeo conocido y su número entre los iguales (dos GameSir: 0 y 1)."""
    out: list[tuple[Device, int]] = []
    for device in order:
        if device not in known:
            log.info("Control %04X:%04X sin mapeo en el emulador: se queda fuera", *device)
            continue
        out.append((device, sum(1 for d, _ in out if d == device)))
    return out


# --- Eden y la familia de yuzu (qt-config.ini) ------------------------------------------------------------------------
def eden_device(value: str) -> Device | None:
    """«engine:sdl,guid:03000000ef170000eb61000000017801,…» -> (0x17EF, 0x61EB)."""
    match = re.search(r"guid:([0-9a-f]{32})", value)
    if not match:
        return None
    guid = match.group(1)
    return _le(guid[8:12]), _le(guid[16:20])


def _eden_blocks(lines: list[str]) -> dict[int, dict[str, str]]:
    """{jugador: {sufijo: valor}} (sin las líneas «\\default»)."""
    blocks: dict[int, dict[str, str]] = {}
    for line in lines:
        match = re.match(r"player_(\d+)_([^=\\]+)=(.*)$", line)
        if match and int(match.group(1)) < EDEN_PLAYERS:
            blocks.setdefault(int(match.group(1)), {})[match.group(2)] = match.group(3)
    return blocks


def _eden_labels(block: dict[str, str], device: Device) -> dict[str, str]:
    """A es A, B es B… (solo controles XInput: el Pro Controller ya los trae en su lugar)."""
    if device[0] == NINTENDO:
        return block
    out = dict(block)
    for key, button in EDEN_LABELS.items():
        if key in out and "button:" in out[key]:
            out[key] = re.sub(r"button:\d+", f"button:{button}", out[key])
    return out


def arrange_eden(config: Path, order: list[Device]) -> bool:
    """El Jugador 1 es el primer control de `order`, el 2 el siguiente…; los demás jugadores, desconectados."""
    try:
        text = config.read_text(encoding="utf-8")
    except OSError:
        return False
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    try:
        start = lines.index("[Controls]") + 1
    except ValueError:
        return False
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("[")), len(lines))
    section = lines[start:end]
    blocks = _eden_blocks(section)
    profiles: dict[Device, dict[str, str]] = {}
    for n in sorted(blocks):
        device = eden_device(blocks[n].get("button_a", ""))
        if device and device not in profiles:
            profiles[device] = blocks[n]
    players = assign(order, set(profiles))[:EDEN_PLAYERS]
    if not players:
        return False
    want: dict[str, str] = {}
    for n, (device, port) in enumerate(players):
        block = _eden_labels(profiles[device], device)
        for suffix, value in block.items():
            if suffix != "connected":
                want[f"player_{n}_{suffix}"] = re.sub(r"port:\d+", f"port:{port}", value)
        want[f"player_{n}_connected"] = "true"
    for n in range(len(players), EDEN_PLAYERS):
        want[f"player_{n}_connected"] = "false"
    index = {line.split("=", 1)[0]: i for i, line in enumerate(section) if "=" in line}
    changed = False
    for key, value in want.items():
        at = index.get(key)
        if at is None:
            section += [f"{key}\\default=false", f"{key}={value}"]
            changed = True
            continue
        if section[at] != f"{key}={value}":
            section[at] = f"{key}={value}"
            changed = True
        flag = index.get(f"{key}\\default")
        if flag is not None and section[flag] != f"{key}\\default=false":
            section[flag] = f"{key}\\default=false"  # con «default=true» Eden no lee el valor
            changed = True
    if not changed:
        return False
    try:
        _backup(config)
        config.write_text(newline.join(lines[:start] + section + lines[end:]) + newline, encoding="utf-8")
    except OSError as exc:
        log.info("No pude acomodar los controles de %s: %s", config, exc)
        return False
    return True


# --- Ryujinx (Config.json, el global y el de cada juego) --------------------------------------------------------------
def ryujinx_device(entry: dict) -> Device | None:
    """«0-00000003-17ef-0000-eb61-000000007200» -> (0x17EF, 0x61EB). Solo controles (no el teclado)."""
    parts = str(entry.get("id", "")).split("-")
    if entry.get("backend") != "GamepadSDL2" or len(parts) != 6:
        return None
    try:
        return int(parts[2], 16), _le(parts[4])
    except ValueError:
        return None


def _ryujinx_entry(profile: dict, device: Device, port: int, player: int) -> dict:
    entry = json.loads(json.dumps(profile))  # copia profunda
    entry["id"] = f"{port}-{entry['id'].split('-', 1)[1]}"
    entry["player_index"] = f"Player{player + 1}"
    if device[0] != NINTENDO and isinstance(entry.get("right_joycon"), dict):
        entry["right_joycon"].update(RYUJINX_LABELS)
    return entry


def ryujinx_profiles(configs: list[Path]) -> dict[Device, dict]:
    """El mapeo de cada modelo de control, de todas las configuraciones (la global primero)."""
    profiles: dict[Device, dict] = {}
    for config in configs:
        try:
            data = json.loads(config.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        entries = data.get("input_config") if isinstance(data, dict) else None
        for entry in entries if isinstance(entries, list) else []:
            device = ryujinx_device(entry) if isinstance(entry, dict) else None
            if device and device not in profiles:
                profiles[device] = entry
    return profiles


def arrange_ryujinx(config: Path, order: list[Device], profiles: dict[Device, dict]) -> bool:
    try:
        data = json.loads(config.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(data, dict) or not isinstance(data.get("input_config"), list):
        return False
    players = assign(order, set(profiles))[:RYUJINX_PLAYERS]
    if not players:
        return False
    pads = [_ryujinx_entry(profiles[device], device, port, n) for n, (device, port) in enumerate(players)]
    taken = {p["player_index"] for p in pads}
    # Lo que no es un control acomodado aquí (el teclado, el modo portátil) se queda, salvo que use el lugar de uno.
    rest = [e for e in data["input_config"] if isinstance(e, dict) and ryujinx_device(e) is None and e.get("player_index") not in taken]
    wanted = pads + rest
    if wanted == data["input_config"]:
        return False
    data["input_config"] = wanted
    try:
        _backup(config)
        config.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    except OSError as exc:
        log.info("No pude acomodar los controles de %s: %s", config, exc)
        return False
    return True


def arrange_for(argv: list[str], order: list[Device]) -> int:
    """Antes de abrir un emulador de Switch: los jugadores en `order`. Cuántos archivos tocó. Nunca falla."""
    try:
        if not argv or not order:
            return 0
        from .emulator_clock import _configs, emulator_exe

        ryujinx, yuzu = _configs(emulator_exe(argv))
        changed = sum(arrange_eden(p, order) for p in yuzu)
        if ryujinx:
            profiles = ryujinx_profiles(ryujinx)
            changed += sum(arrange_ryujinx(p, order, profiles) for p in ryujinx)
        if changed:
            log.info("Controles: Jugador 1 = %s (y %d más) en %d archivo(s)", "%04X:%04X" % order[0], len(order) - 1, changed)
        return changed
    except Exception:  # noqa: BLE001 - los controles nunca impiden abrir un juego
        log.exception("No pude acomodar los controles del emulador")
        return 0
