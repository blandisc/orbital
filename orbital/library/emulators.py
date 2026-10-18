"""Escaneo de ROMs y construcción del comando de cada emulador."""

from __future__ import annotations

import glob
import hashlib
import logging
import os
import re
import shutil
from pathlib import Path

from ..config import EmulatorConfig
from .esde import EsdeLibrary
from .media import MediaStore, good, image_size
from .models import LibraryItem, Runner, added_at
from .shortcuts import read_lnk, xenia_games

log = logging.getLogger(__name__)

# "Super Mario World (USA) [!]" -> "Super Mario World"
_TAGS = re.compile(r"\s*[\(\[][^\)\]]*[\)\]]")


def clean_title(filename: str) -> str:
    stem = Path(filename).stem.replace("_", " ")
    title = _TAGS.sub("", stem).strip()
    return re.sub(r"\s{2,}", " ", title) or stem


def resolve_executable(emu: EmulatorConfig) -> Path | None:
    """Admite comodines: 'Downloads\\xemu-*\\xemu.exe' o 'Downloads\\**\\Ryujinx.exe'.

    Si hay varias coincidencias (p. ej. dos versiones descargadas) usa la más reciente.
    """
    pattern = emu.executable
    if Path(pattern).is_file():  # «C:\Juegos [2024]\emu.exe» existe tal cual: no es un comodín
        return Path(pattern)
    if any(c in pattern for c in "*?["):
        matches = [Path(p) for p in glob.glob(pattern, recursive=True) if os.path.isfile(p)]
        return max(matches, key=lambda p: p.stat().st_mtime) if matches else None
    found = shutil.which(pattern)
    return Path(found) if found else None


def executable_found(emu: EmulatorConfig) -> bool:
    return resolve_executable(emu) is not None


def build_argv(emu: EmulatorConfig, exe: Path | None, rom: Path) -> list[str]:
    # Reemplazo literal: una llave suelta en un argumento («{"x":1}») ya no tumba el lanzamiento.
    values = {"{rom}": str(rom), "{rom_dir}": str(rom.parent), "{rom_name}": rom.stem, "{rom_file}": rom.name}
    return [str(exe or emu.executable)] + [_fill(arg, values) for arg in emu.args]


def _fill(arg: str, values: dict[str, str]) -> str:
    for key, value in values.items():
        arg = arg.replace(key, value)
    return arg


def _item_id(emu_id: str, rom: Path) -> str:
    digest = hashlib.sha1(str(rom).encode("utf-8")).hexdigest()[:12]
    return f"emu:{emu_id}:{digest}"


def rom_dirs(emu: EmulatorConfig, esde: EsdeLibrary | None) -> list[Path]:
    """Las carpetas de config.yaml; si no hay y el emulador tiene `system`, la de ES-DE."""
    if emu.rom_dirs:
        return [Path(d) for d in emu.rom_dirs]
    if esde and emu.system:
        return [esde.system_dir(emu.system)]
    return []


def runner_name(emu: EmulatorConfig, exe: Path | None) -> str:
    """Nombre corto para la interfaz: "Ryujinx", "Eden", "Dolphin"..."""
    if emu.esde_label:
        return emu.esde_label
    stem = (exe or Path(emu.executable.replace("*", ""))).stem
    return stem if any(c.isupper() for c in stem) else stem.capitalize()


def esde_key(emu: EmulatorConfig) -> str:
    return (emu.esde_label or Path(emu.executable.replace("*", "")).stem).lower()


def split_alternatives(emus: list[EmulatorConfig]) -> list[tuple[EmulatorConfig, list[EmulatorConfig]]]:
    """Varios emuladores para el mismo sistema (Ryujinx + Eden) comparten una sola lista de juegos.

    El primero de config.yaml es el principal; los demás solo se usan si ES-DE los eligió.
    """
    groups: list[tuple[EmulatorConfig, list[EmulatorConfig]]] = []
    primary_by_system: dict[str, tuple[EmulatorConfig, list[EmulatorConfig]]] = {}
    for emu in emus:
        shared = emu.system and not emu.rom_dirs
        if shared and emu.system in primary_by_system:
            primary_by_system[emu.system][1].append(emu)
            continue
        group = (emu, [])
        groups.append(group)
        if shared:
            primary_by_system[emu.system] = group
    return groups


def pick_art(media: MediaStore | None, esde: EsdeLibrary | None, system: str | None, key: str,
             entry: Path, esde_system: str | None) -> dict[str, str | None]:
    """Portada, fondo y logotipo: primero el arte propio de Orbital; si no hay, el de ES-DE, pero solo
    si sirve (una captura no pasa como portada) y no lo rechazaste."""
    found: dict[str, str | None] = {}
    lookups = {"cover": "cover", "hero": "hero", "logo": "logo"}
    for kind, method in lookups.items():
        own = media.path(system, key, kind) if media and system else None
        if own:
            found[kind] = str(own)
            continue
        theirs = getattr(esde, method)(esde_system, entry) if esde and esde_system else None
        usable = theirs is not None and good(kind, image_size(theirs), system)
        if usable and media and system and (media.is_rejected(system, key, kind, "esde")
                                             or media.looks_rejected(system, key, kind, theirs)):
            usable = False  # la rechazaste (o se ve igual que una que rechazaste)
        found[kind] = str(theirs) if usable else None
    return found


def game_title(esde_name: str | None, entry: Path, own: dict | None) -> str:
    """El nombre de ES-DE si alguien lo escribió; si es solo el del archivo («Call of Duty - Black Ops
    II»), el de la ficha que trajo el scraper («Call of Duty: Black Ops II»)."""
    from_file = clean_title(entry.name)
    if esde_name and esde_name.strip().lower() != from_file.lower():
        return esde_name
    return (own or {}).get("title") or esde_name or from_file


def game_extra(own: dict | None) -> dict:
    """Datos de la ficha para el héroe: descripción, año, géneros, jugadores."""
    if not own:
        return {}
    extra = {k: own[k] for k in ("description", "genres", "developer") if own.get(k)}
    if own.get("released"):
        extra["year"] = own["released"][:4]
    if own.get("players"):
        extra["players"] = own["players"]
    return extra


def scan(
    emu: EmulatorConfig,
    esde: EsdeLibrary | None = None,
    alternatives: list[EmulatorConfig] | None = None,
    media: MediaStore | None = None,
) -> list[LibraryItem]:
    candidates = [emu, *(alternatives or [])]
    exes = {c.id: resolve_executable(c) for c in candidates}
    for c in candidates:
        if exes[c.id] is None:
            log.warning("No encuentro el ejecutable de %s: %s", c.name, c.executable)
    items: list[LibraryItem] = []
    seen: set[str] = set()  # un juego, una tarjeta (aunque haya .lnk y paquete instalado)
    exts = set(emu.extensions)
    excluded = [e.lower() for e in emu.exclude]
    dirs = rom_dirs(emu, esde)
    if not dirs:
        log.warning("%s no tiene rom_dirs ni system de ES-DE", emu.name)
    emulator_exes = {exe.name.lower() for exe in exes.values() if exe}
    ports = _ports(emu, dirs, emulator_exes, media, esde)
    if emu.system == "ps4":
        return sorted([*_scan_ps4(emu, dirs, candidates, exes, media), *ports], key=lambda i: i.title.lower())
    if emu.system == "ps3":
        return sorted([*_scan_ps3(emu, dirs, candidates, exes, media), *ports], key=lambda i: i.title.lower())
    items += ports
    for root in dirs:
        if not root.is_dir():
            log.warning("Carpeta de ROMs no encontrada para %s: %s", emu.name, root)
            continue
        # Solo enriquecemos con ES-DE si la carpeta es la del sistema en ES-DE.
        system = emu.system if esde and emu.system and root == esde.system_dir(emu.system) else None
        files = root.rglob("*") if emu.recursive else root.iterdir()
        for entry in files:
            if not entry.is_file():
                continue
            rom = entry
            if entry.suffix.lower() == ".lnk":
                # Acceso directo que abre este emulador con un juego ("Call of Duty.lnk" -> Xenia + paquete):
                # se usa el juego al que apunta; el nombre y la portada siguen siendo los del .lnk en ES-DE.
                rom = _shortcut_rom(entry, emulator_exes)
                if rom is None:
                    continue  # no abre un emulador: si abre un programa, es un port (ver _ports)
            elif exts and entry.suffix.lower() not in exts:
                continue
            if any(word in entry.name.lower() for word in excluded):
                continue
            if str(rom).lower() in seen:
                continue
            seen.add(str(rom).lower())
            meta = esde.meta(system, entry) if system else None
            if meta and meta.hidden:
                continue
            runners = [
                Runner(c.id, runner_name(c, exes[c.id]), build_argv(c, exes[c.id], rom), str(exes[c.id].parent) if exes[c.id] else None)
                for c in candidates
                if c is emu or exes[c.id] is not None  # alternativas solo si están instaladas
            ]
            default = emu
            chosen = esde.chosen_emulator(system, entry) if system else None
            if chosen:
                default = next((c for c in candidates if esde_key(c) in chosen.lower()), emu)
            key = entry.relative_to(root).with_suffix("").as_posix()
            art = pick_art(media, esde, emu.system, key, entry, system)
            own = media.meta(emu.system, key) if media and emu.system else None
            items.append(
                LibraryItem(
                    id=_item_id(emu.id, rom),
                    title=game_title(meta.name if meta else None, entry, own),
                    extra={**game_extra(own), "added": added_at(rom)},
                    category="emulators",
                    source=emu.id,
                    subtitle=emu.name,
                    runners=runners,
                    default_runner=default.id,
                    favorite=bool(meta and meta.favorite),
                    art_path=art["cover"],
                    hero_path=art["hero"],
                    logo_path=art["logo"],
                    system=emu.system,
                    media_key=key if emu.system else None,
                )
            )
    # Xbox 360: los juegos instalados dentro de Xenia (Games on Demand / Arcade), aunque no haya nada
    # en la carpeta de ROMs. El nombre sale de la cabecera del paquete.
    exe = exes.get(emu.id)
    if emu.system == "xbox360" and exe is not None:
        for package, name in xenia_games(exe.parent / "content"):
            if str(package).lower() in seen:
                continue
            seen.add(str(package).lower())
            art = pick_art(media, None, emu.system, name, package, None)
            items.append(LibraryItem(
                id=_item_id(emu.id, package), title=name, category="emulators", source=emu.id, subtitle=emu.name,
                runners=[Runner(emu.id, runner_name(emu, exe), build_argv(emu, exe, package), str(exe.parent))],
                default_runner=emu.id, art_path=art["cover"], hero_path=art["hero"], logo_path=art["logo"],
                system=emu.system, media_key=name, extra={"added": added_at(package)}))
    return sorted(items, key=lambda i: i.title.lower())


def _scan_ps4(emu: EmulatorConfig, dirs: list[Path], candidates: list[EmulatorConfig], exes: dict[str, Path | None],
              media: MediaStore | None) -> list[LibraryItem]:
    """PS4: los juegos son carpetas (ver library/ps4.py), de la carpeta de ROMs y de las que ya conoce shadPS4. Sin
    portada propia, la del juego (icon0.png) y su fondo (pic1.png)."""
    from . import ps4

    items: list[LibraryItem] = []
    for game in ps4.find_games([*dirs, *ps4.install_dirs(exes.get(emu.id))]):
        key = game.title_id or game.folder.name
        art = pick_art(media, None, emu.system, key, game.folder, None)
        own = media.meta(emu.system, key) if media and emu.system else None
        runners = [Runner(c.id, runner_name(c, exes[c.id]), build_argv(c, exes[c.id], game.eboot), str(exes[c.id].parent) if exes[c.id] else None)
                   for c in candidates if c is emu or exes[c.id] is not None]
        items.append(LibraryItem(
            id=_item_id(emu.id, game.eboot), title=(own or {}).get("title") or game.title, category="emulators",
            source=emu.id, subtitle=emu.name, runners=runners, default_runner=emu.id,
            art_path=art["cover"] or (str(game.icon) if game.icon else None),
            hero_path=art["hero"] or (str(game.background) if game.background else None), logo_path=art["logo"],
            system=emu.system, media_key=key, extra={**game_extra(own), "added": added_at(game.eboot)}))
    return items


def _scan_ps3(emu: EmulatorConfig, dirs: list[Path], candidates: list[EmulatorConfig], exes: dict[str, Path | None],
              media: MediaStore | None) -> list[LibraryItem]:
    """PS3: de disco (ROMs/ps3 y la carpeta games de RPCS3), instalados (dev_hdd0/game) y los que RPCS3 ya conoce
    (config/games.yml). Sin portada propia, la del juego (ICON0.PNG) y su fondo (PIC1.PNG)."""
    from . import ps3

    exe = exes.get(emu.id)
    roots = [*dirs, *([exe.parent / "games"] if exe else [])]
    hdd = exe.parent / "dev_hdd0" / "game" if exe else None
    items: list[LibraryItem] = []
    for game in ps3.find_games(roots, hdd, ps3.known_paths(exe)):
        key = game.title_id or game.folder.name
        art = pick_art(media, None, emu.system, key, game.folder, None)
        own = media.meta(emu.system, key) if media and emu.system else None
        runners = [Runner(c.id, runner_name(c, exes[c.id]), build_argv(c, exes[c.id], game.boot), str(exes[c.id].parent) if exes[c.id] else None)
                   for c in candidates if c is emu or exes[c.id] is not None]
        items.append(LibraryItem(
            id=_item_id(emu.id, game.boot), title=(own or {}).get("title") or game.title, category="emulators",
            source=emu.id, subtitle=emu.name, runners=runners, default_runner=emu.id,
            art_path=art["cover"] or (str(game.icon) if game.icon else None),
            hero_path=art["hero"] or (str(game.background) if game.background else None), logo_path=art["logo"],
            system=emu.system, media_key=key, extra={**game_extra(own), "added": added_at(game.boot)}))
    return items


PORT_RUNNER = "pc"


def _ports(emu: EmulatorConfig, dirs: list[Path], emulator_exes: set[str], media: MediaStore | None,
           esde: EsdeLibrary | None) -> list[LibraryItem]:
    """Ports para PC de un juego de consola (God of War III de PS4 con gow3_pc, Ship of Harkinian de N64…): un acceso
    directo en la carpeta de esa consola que abre un programa, no un emulador. Sale en la sección de su consola y se
    abre directo (Orbital sigue al juego aunque lo abra un lanzador que luego se cierra)."""
    items: list[LibraryItem] = []
    for root in dirs:
        try:
            links = sorted(p for p in root.iterdir() if p.suffix.lower() == ".lnk" and p.is_file())
        except OSError:
            continue
        system = emu.system if esde and emu.system and root == esde.system_dir(emu.system) else None
        for lnk in links:
            shortcut = read_lnk(lnk)
            target = Path(shortcut.target) if shortcut and shortcut.target else None
            if target is None or target.suffix.lower() != ".exe" or target.name.lower() in emulator_exes or not target.is_file():
                continue
            meta = esde.meta(system, lnk) if system else None
            if meta and meta.hidden:
                continue
            key = lnk.stem
            art = pick_art(media, esde, emu.system, key, lnk, system)
            own = media.meta(emu.system, key) if media and emu.system else None
            cwd = shortcut.working_dir if shortcut and shortcut.working_dir else str(target.parent)
            items.append(LibraryItem(
                id=_item_id(emu.id, lnk), title=game_title(meta.name if meta else None, lnk, own), category="emulators",
                source=emu.id, subtitle=emu.name, runners=[Runner(PORT_RUNNER, "PC", [str(target), *shortcut.argv()], cwd)],
                default_runner=PORT_RUNNER, favorite=bool(meta and meta.favorite), art_path=art["cover"], hero_path=art["hero"],
                logo_path=art["logo"], system=emu.system, media_key=key if emu.system else None,
                extra={**game_extra(own), "added": added_at(lnk), "port": True}))
    return items


def _shortcut_rom(lnk: Path, emulator_exes: set[str]) -> Path | None:
    """El juego al que apunta un .lnk que abre uno de estos emuladores (su último argumento-ruta)."""
    shortcut = read_lnk(lnk)
    if shortcut is None or Path(shortcut.target).name.lower() not in emulator_exes:
        return None
    paths = [a for a in shortcut.argv() if ("\\" in a or "/" in a) and not a.startswith("-")]
    return Path(paths[-1]) if paths else None
