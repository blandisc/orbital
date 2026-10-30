"""Los controles de los emuladores de Switch, como en una consola: el control con el que abres el juego es el Jugador 1.

Eden y Ryujinx guardan qué control es cada jugador por su identificador (marca y modelo), y Orbital los encontraba en el
orden en que alguien los dejó a mano: en Ryujinx los dos jugadores eran el GameSir (los de la Legion no hacían nada) y en
Eden el GameSir era el Jugador 2 (en un juego de uno, no respondía). Antes de abrir uno, Orbital acomoda los jugadores:
primero el control que usaste por última vez (el que apretó A para abrir), luego los demás encendidos (ver players.py).
El mapeo de cada modelo sale de lo que ya está en tus configuraciones (la global y las de cada juego); un control tipo
Xbox que nunca se configuró usa el mapeo de otro control tipo Xbox (todos reportan los mismos botones), con su propio
identificador: antes se quedaba fuera y no respondía. Y en todos, A es A, B es B, X es X y Y es Y, como dicen los botones.

Dolphin (GameCube y Wii) asigna cada puerto a un lugar de XInput: el puerto 1 es el lugar del Jugador 1, y los puertos
siguientes los de los demás, así que un control que conectas a media partida entra solo en el puerto que sigue.

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


def _le4(value: int) -> str:
    """0x17EF -> «ef17» (los dos bytes al revés, como van en el identificador de SDL)."""
    return f"{value & 0xFF:02x}{value >> 8 & 0xFF:02x}"


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


def eden_guid_for(template_guid: str, device: Device, version: int | None = None) -> str:
    """El identificador de SDL de otro control con la misma forma: cambian la marca, el modelo y (si se sabe) la versión
    del producto (la Legion reporta 0x0100 y su identificador lleva «0001» en ese lugar)."""
    guid = template_guid[:8] + _le4(device[0]) + template_guid[12:16] + _le4(device[1]) + template_guid[20:]
    return guid if version is None else guid[:24] + _le4(version) + guid[28:]


def _eden_synth(profiles: dict[Device, dict[str, str]], device: Device, version: int | None = None) -> dict[str, str] | None:
    """El mapeo de un control tipo Xbox que nunca se configuró: el de otro control tipo Xbox, con su identificador."""
    if device[0] == NINTENDO:
        return None
    template = next((block for dev, block in profiles.items() if dev[0] != NINTENDO), None)
    match = re.search(r"guid:([0-9a-f]{32})", template.get("button_a", "")) if template else None
    if template is None or match is None:
        return None
    guid = eden_guid_for(match.group(1), device, version)
    log.info("Control %04X:%04X sin mapeo en Eden: uso el de otro control tipo Xbox", *device)
    return {key: value.replace(match.group(1), guid) for key, value in template.items()}


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


def arrange_eden(config: Path, order: list[Device], versions: dict[Device, int] | None = None) -> bool:
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
    for device in order:
        synth = _eden_synth(profiles, device, (versions or {}).get(device)) if device not in profiles else None
        if synth:
            profiles[device] = synth
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


def ryujinx_synth(profiles: dict[Device, dict], device: Device) -> dict | None:
    """Como en Eden: un control tipo Xbox sin mapeo usa el de otro, con su propio identificador."""
    if device[0] == NINTENDO:
        return None
    template = next((entry for dev, entry in profiles.items() if dev[0] != NINTENDO), None)
    parts = str(template.get("id", "")).split("-") if template else []
    if template is None or len(parts) != 6:
        return None
    entry = json.loads(json.dumps(template))
    entry["id"] = "-".join([parts[0], parts[1], f"{device[0]:04x}", parts[3], _le4(device[1]), parts[5]])
    entry["name"] = f"Control {device[0]:04X}:{device[1]:04X}"
    log.info("Control %04X:%04X sin mapeo en Ryujinx: uso el de otro control tipo Xbox", *device)
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
    profiles = dict(profiles)
    for device in order:
        synth = ryujinx_synth(profiles, device) if device not in profiles else None
        if synth:
            profiles[device] = synth
    players = assign(order, set(profiles))[:RYUJINX_PLAYERS]
    if not players:
        return False
    # Los controles que Ryujinx ya conoce pero están apagados, con su lugar apartado después de los encendidos: Ryujinx
    # vuelve a leer la lista cuando se conecta un control, así que si enciendes el GameSir a media partida, entra solo
    # como el siguiente jugador. Mientras está apagado, para el juego no existe (Ryujinx salta lo que no está).
    spare = [(device, 0) for device in profiles if device not in order]
    players += spare[:RYUJINX_PLAYERS - len(players)]
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


# --- Dolphin (GameCube y Wii: GCPadNew.ini, WiimoteNew.ini y Dolphin.ini) ------------------------------------------------
DOLPHIN_PORTS = 4
SI_STANDARD = "6"  # SIDevice: control estándar de GameCube


def dolphin_config_dir(exe: Path) -> Path | None:
    """La carpeta Config de Dolphin: la portátil (User\\Config junto al .exe) o la de Documentos."""
    import os

    for candidate in (exe.parent / "User" / "Config",
                      Path(os.environ.get("USERPROFILE", "~")).expanduser() / "Documents" / "Dolphin Emulator" / "Config",
                      Path(os.environ.get("APPDATA", "")) / "Dolphin Emulator" / "Config"):
        if (candidate / "Dolphin.ini").exists() or (candidate / "GCPadNew.ini").exists():
            return candidate
    return None


def _ini_set(text: str, section: str, key: str, value: str) -> str:
    """Pone `key = value` en esa sección (si existe); lo demás, intacto."""
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    try:
        start = lines.index(f"[{section}]") + 1
    except ValueError:
        return text
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(start, end):
        if lines[i].split("=", 1)[0].strip() == key:
            lines[i] = f"{key} = {value}"
            break
    else:
        lines.insert(end, f"{key} = {value}")
    return newline.join(lines) + (newline if text.endswith("\n") else "")


def _ini_get(text: str, section: str, key: str) -> str | None:
    lines = text.splitlines()
    try:
        start = lines.index(f"[{section}]") + 1
    except ValueError:
        return None
    for line in lines[start:]:
        if line.startswith("["):
            break
        name, _, value = line.partition("=")
        if name.strip() == key:
            return value.strip()
    return None


def dolphin_borderless(config_dir: Path) -> bool:
    """Pantalla completa SIN bordes en Dolphin (GFX.ini › [Settings] BorderlessFullscreen). La exclusiva de Direct3D 11 es
    dueña de la pantalla: con Home, el juego congelado no la soltaba y en la tele seguía su cuadro quieto aunque Orbital
    tuviera el foco (y los botones iban a un Orbital invisible; visto en la tele el 2026-10-30, al segundo Home). Sin
    bordes, Windows sigue componiendo y Orbital sale encima al instante. Solo cambia el archivo si hace falta."""
    path = config_dir / "GFX.ini"
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
    except OSError:
        return False
    if _ini_get(text, "Settings", "BorderlessFullscreen") == "True":
        return False
    if "[Settings]" not in text.splitlines():
        text = (text.rstrip("\r\n") + "\n\n" if text.strip() else "") + "[Settings]\n"
    try:
        if path.exists():
            _backup(path)
        path.write_text(_ini_set(text, "Settings", "BorderlessFullscreen", "True"), encoding="utf-8")
    except OSError:
        return False
    return True


def dolphin_ports(slots: list[int]) -> list[int]:
    """El lugar de XInput de cada puerto: primero los jugadores en orden, luego los lugares libres (para quien llegue)."""
    return (list(slots) + [s for s in range(DOLPHIN_PORTS) if s not in slots])[:DOLPHIN_PORTS]


def arrange_dolphin(config_dir: Path, slots: list[int]) -> int:
    """Puerto 1 = el Jugador 1, etc. Solo toca los puertos que ya usan XInput (no un DualShock por Bluetooth ni el
    teclado), y a los puertos con jugador que estaban vacíos se les conecta un control de GameCube. Cuántos archivos
    cambió."""
    if not slots:
        return 0
    ports = dolphin_ports(slots)
    changed = 0
    for name, section in (("GCPadNew.ini", "GCPad{n}"), ("WiimoteNew.ini", "Wiimote{n}")):
        path = config_dir / name
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        new = text
        for n, slot in enumerate(ports, start=1):
            current = _ini_get(new, section.format(n=n), "Device")
            if current is not None and current.startswith("XInput/"):
                new = _ini_set(new, section.format(n=n), "Device", f"XInput/{slot}/Gamepad")
        if new != text:
            _backup(path)
            path.write_text(new, encoding="utf-8")
            changed += 1
    main = config_dir / "Dolphin.ini"
    try:
        text = main.read_text(encoding="utf-8")
    except OSError:
        return changed
    new = text
    for n in range(min(len(slots), DOLPHIN_PORTS)):
        if _ini_get(new, "Core", f"SIDevice{n}") == "0":  # un puerto vacío con un jugador: se le conecta un control
            new = _ini_set(new, "Core", f"SIDevice{n}", SI_STANDARD)
    if new != text:
        _backup(main)
        main.write_text(new, encoding="utf-8")
        changed += 1
    return changed


def arrange_for(argv: list[str], order: list[Device], slots: list[int] | None = None,
                versions: dict[Device, int] | None = None) -> int:
    """Antes de abrir un emulador: los jugadores en `order` (marca y modelo) y `slots` (sus lugares de XInput, para
    Dolphin). Cuántos archivos tocó. Nunca falla."""
    try:
        if not argv:
            return 0
        from .emulator_clock import _configs, emulator_exe

        exe = emulator_exe(argv)
        if exe is not None and exe.name.lower() == "dolphin.exe":
            folder = dolphin_config_dir(exe)
            if folder and dolphin_borderless(folder):
                log.info("Dolphin: pantalla completa sin bordes (la exclusiva tapaba a Orbital al volver con Home)")
            changed = arrange_dolphin(folder, slots or []) if folder and order else 0
            if changed:
                log.info("Controles de Dolphin: puerto 1 = mando %d (%d archivo(s))", (slots or [0])[0] + 1, changed)
            return changed
        if not order:
            return 0
        ryujinx, yuzu = _configs(exe)
        changed = sum(arrange_eden(p, order, versions) for p in yuzu)
        if ryujinx:
            # También de sus respaldos: si un control se quedó fuera de la configuración (estaba apagado la última vez),
            # su perfil sigue ahí y se le puede apartar el lugar (los de ahora mandan: van primero).
            backups = [b for p in ryujinx for b in sorted(p.parent.glob(p.name + ".*"), reverse=True) if b.is_file()]
            profiles = ryujinx_profiles(ryujinx + backups)
            changed += sum(arrange_ryujinx(p, order, profiles) for p in ryujinx)
        if changed:
            log.info("Controles: Jugador 1 = %s (y %d más) en %d archivo(s)", "%04X:%04X" % order[0], len(order) - 1, changed)
        return changed
    except Exception:  # noqa: BLE001 - los controles nunca impiden abrir un juego
        log.exception("No pude acomodar los controles del emulador")
        return 0
