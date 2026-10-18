"""Sacar Orbital de ES-DE (una vez): mueve tus ROMs y emuladores a carpetas de Orbital, corrige las rutas que los
emuladores guardaron (actualizaciones y DLC de Ryujinx, la carpeta de xemu, accesos directos…), pasa a Orbital lo que
ES-DE sabía de cada juego (nombre, descripción, fecha, favoritos y sus portadas) y traduce tu historial al nuevo
identificador de cada juego (Orbital los nombra por su ruta).

    python scripts/esde_a_orbital.py            # ensayo: dice qué haría, sin tocar nada
    python scripts/esde_a_orbital.py --hazlo    # lo hace (con Orbital, ES-DE y los emuladores cerrados)

Antes de cambiar un archivo de configuración, guarda una copia en C:\\Orbital\\respaldo-rutas.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

ESDE = Path.home() / "Downloads" / "ES-DE"
NEW = Path("C:/Orbital")
MOVES = {ESDE / "ROMs": NEW / "ROMs", ESDE / "Emulators": NEW / "Emuladores"}
BACKUP = NEW / "respaldo-rutas"
APPDATA = Path(os.environ.get("APPDATA", ""))
LOCAL = Path(os.environ.get("LOCALAPPDATA", ""))
CONFIG_DIRS = [APPDATA / "Ryujinx", APPDATA / "eden" / "config", APPDATA / "xemu", NEW / "Emuladores", ESDE / "Emulators"]
TEXT_EXTS = {".json", ".ini", ".toml", ".cfg", ".cmd", ".bat", ".xml", ".yaml", ".yml", ".ps1", ".vbs"}
MEDIA_KINDS = {"cover": ("covers",), "hero": ("fanart", "screenshots"), "logo": ("marquees",)}


def variants(old: Path, new: Path) -> list[tuple[str, str]]:
    """La misma ruta como la escribe cada programa: C:\\a\\b, C:\\\\a\\\\b (JSON) y C:/a/b."""
    o, n = str(old), str(new)
    return [(o.replace("\\", "\\\\"), n.replace("\\", "\\\\")), (o, n), (o.replace("\\", "/"), n.replace("\\", "/"))]


def fix_paths(dry: bool, log: list[str]) -> None:
    pairs = [p for old, new in MOVES.items() for p in variants(old, new)]
    seen: set[Path] = set()
    for folder in CONFIG_DIRS:
        if not folder.is_dir():
            continue
        for path in folder.rglob("*"):
            if path in seen or not path.is_file() or path.suffix.lower() not in TEXT_EXTS or path.stat().st_size > 2_000_000:
                continue
            if "backup" in str(path).lower():
                continue  # las copias que el emulador guardó, tal cual
            seen.add(path)
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            new_text = text
            for old, new in pairs:
                new_text = re.sub(re.escape(old), new.replace("\\", "\\\\"), new_text, flags=re.IGNORECASE)
            if new_text != text:
                log.append(f"rutas: {path}")
                if not dry:
                    dest = BACKUP / path.drive.strip(":") / path.relative_to(path.anchor)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, dest)
                    path.write_text(new_text, encoding="utf-8")


def fix_shortcuts(dry: bool, log: list[str]) -> None:
    """Los accesos directos de las carpetas de juegos que apuntan a la carpeta vieja de emuladores."""
    roms = NEW / "ROMs" if not dry else ESDE / "ROMs"
    for lnk in roms.rglob("*.lnk"):
        script = (f"$s=(New-Object -ComObject WScript.Shell).CreateShortcut('{lnk}');"
                  f"$t=$s.TargetPath; $w=$s.WorkingDirectory; $o='{ESDE / 'Emulators'}'; $n='{NEW / 'Emuladores'}';"
                  "if ($t -like \"$o*\") { $s.TargetPath = $n + $t.Substring($o.Length); "
                  "if ($w -like \"$o*\") { $s.WorkingDirectory = $n + $w.Substring($o.Length) }; "
                  + ("" if dry else "$s.Save(); ") + "'cambiado ' + $s.TargetPath }")
        out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout.strip()
        if out:
            log.append(f"acceso directo: {lnk.name} → {out.removeprefix('cambiado ')}")


def fix_config(dry: bool, log: list[str]) -> None:
    path = APPDATA / "Orbital" / "config.yaml"
    text = path.read_text(encoding="utf-8")
    new = re.sub(r"(?m)^(esde:\s*\n\s+enabled:\s*)true", r"\1false", text)
    new = re.sub(r"(?m)^(detect:\s*\n\s+enabled:\s*true\s*\n)",
                 r"\1  roms: 'C:\\Orbital\\ROMs'          # tus juegos, una carpeta por consola\n"
                 r"  dirs: ['C:\\Orbital\\Emuladores']   # tus emuladores\n", new)
    if new != text:
        log.append("config.yaml: ES-DE apagado; ROMs en C:\\Orbital\\ROMs; emuladores en C:\\Orbital\\Emuladores")
        if not dry:
            BACKUP.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, BACKUP / "config.yaml")
            path.write_text(new, encoding="utf-8")


def gamelists() -> dict[str, list[dict]]:
    """Lo que ES-DE sabe de cada juego, por consola (su gamelist.xml trae un nodo raíz de más: se envuelve)."""
    out: dict[str, list[dict]] = {}
    base = ESDE / "ES-DE" / "gamelists"
    for folder in base.iterdir() if base.is_dir() else []:
        xml = folder / "gamelist.xml"
        if not xml.exists():
            continue
        raw = re.sub(r"<\?xml[^>]*\?>", "", xml.read_text(encoding="utf-8", errors="replace"))
        try:
            root = ET.fromstring(f"<root>{raw}</root>")
        except ET.ParseError:
            continue
        games = []
        for g in root.iter("game"):
            def get(tag: str, game=g) -> str:
                return (game.findtext(tag) or "").strip()
            path = get("path").removeprefix("./")
            if path:
                games.append({"key": str(Path(path).with_suffix("")).replace("\\", "/"), "name": get("name"), "desc": get("desc"),
                              "released": get("releasedate")[:8], "developer": get("developer"), "genre": get("genre"),
                              "players": get("players"), "favorite": get("favorite") == "true", "hidden": get("hidden") == "true"})
        out[folder.name] = games
    return out


def import_esde(dry: bool, log: list[str], media) -> list[tuple[str, str]]:
    """Fichas y portadas de ES-DE a Orbital (solo lo que Orbital aún no tiene). Devuelve (consola, juego) favoritos."""
    favorites: list[tuple[str, str]] = []
    media_root = ESDE / "ES-DE" / "downloaded_media"
    metas = images = 0
    for system, games in gamelists().items():
        for g in games:
            key = g["key"]
            if g["favorite"]:
                favorites.append((system, key))
            if not media.meta(system, key) and (g["desc"] or g["name"]):
                metas += 1
                if not dry:
                    released = g["released"]
                    media.save_meta(system, key, {k: v for k, v in {
                        "title": g["name"], "description": g["desc"], "developer": g["developer"],
                        "released": f"{released[:4]}-{released[4:6]}-{released[6:8]}" if len(released) == 8 else None,
                        "genres": [s.strip() for s in g["genre"].split(",") if s.strip()] or None, "players": g["players"] or None,
                        "source": "ES-DE"}.items() if v})
            for kind, folders in MEDIA_KINDS.items():
                if media.path(system, key, kind):
                    continue
                src = next((p for f in folders for p in (media_root / system / f).glob(f"{glob_escape(key)}.*")
                            if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp")), None)
                if src:
                    images += 1
                    if not dry:
                        shutil.copy2(src, media.target(system, key, kind, src.suffix.lower()))
    log.append(f"de ES-DE a Orbital: {metas} fichas y {images} portadas/fondos/logos (lo que Orbital no tenía)")
    return favorites


def glob_escape(text: str) -> str:
    return re.sub(r"([\[\]*?])", r"[\1]", text)


def remap_state(old_items: list[dict], new_items: list, favorites: list[tuple[str, str]], dry: bool, log: list[str]) -> None:
    """Tu historial, favoritos, ocultos y emulador elegido, del identificador viejo de cada juego al nuevo."""
    path = APPDATA / "Orbital" / "state.json"
    state = json.loads(path.read_text(encoding="utf-8"))
    by_key = {(i.system, i.media_key): i for i in new_items if i.category == "emulators"}
    mapping: dict[str, object] = {}
    for old in old_items:
        if old.get("category") == "emulators" and (new := by_key.get((old.get("system"), old.get("media_key")))):
            mapping[old["id"]] = new
    moved = 0
    for section in ("history", "prefs", "seen", "inbox"):
        block = state.get(section) or {}
        for old_id in [k for k in block if k in mapping]:
            new = mapping[old_id]
            value = block.pop(old_id)
            if section == "prefs" and isinstance(value, dict) and value.get("runner"):
                old_runner = next((r for o in old_items if o["id"] == old_id for r in o.get("runners") or [] if r["id"] == value["runner"]), None)
                value["runner"] = next((r.id for r in new.runners if old_runner and r.name == old_runner["name"]), None)
                if not value["runner"]:
                    value.pop("runner")
            block[new.id] = value
            moved += 1
    for system, key in favorites:  # el favorito de ES-DE
        if (new := by_key.get((system, key))):
            state.setdefault("prefs", {}).setdefault(new.id, {})["favorite"] = True
    unmatched = [o["title"] for o in old_items if o.get("category") == "emulators" and o["id"] not in mapping]
    log.append(f"historial: {moved} datos pasados a {len(mapping)} juegos" + (f"; sin pareja: {', '.join(unmatched)}" if unmatched else ""))
    if not dry:
        BACKUP.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, BACKUP / "state.json")
        path.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def main() -> None:
    args = argparse.ArgumentParser()
    args.add_argument("--hazlo", action="store_true", help="hacerlo de verdad (sin esto, solo ensayo)")
    dry = not args.parse_args().hazlo
    log: list[str] = []
    old_items = json.loads((LOCAL / "orbital" / "cache" / "library.json").read_text(encoding="utf-8"))
    for old, new in MOVES.items():
        if not old.is_dir():
            sys.exit(f"No encuentro {old}")
        if new.exists():
            sys.exit(f"{new} ya existe: no muevo encima")
        log.append(f"mover: {old} → {new}")
        if not dry:
            new.parent.mkdir(parents=True, exist_ok=True)
            os.rename(old, new)  # mismo disco: un cambio de nombre, al instante
    fix_paths(dry, log)
    fix_shortcuts(dry, log)
    fix_config(dry, log)
    from demo_server import DryLauncher  # lanzador de mentira: no abre nada

    from orbital.catalog import Catalog
    from orbital.config import load_config
    from orbital.library.media import MediaStore

    favorites = import_esde(dry, log, MediaStore())
    if not dry:
        catalog = Catalog(load_config(), DryLauncher())
        catalog.refresh()
        remap_state(old_items, catalog.store.all(), favorites, dry, log)
        consoles = sorted({i.system for i in catalog.store.all() if i.category == "emulators"})
        log.append(f"ahora: {sum(1 for i in catalog.store.all() if i.category == 'emulators')} juegos de emulador en {', '.join(consoles)}"
                   f" (antes: {sum(1 for i in old_items if i.get('category') == 'emulators')})")
    print(("ENSAYO (no cambié nada)\n" if dry else "HECHO\n") + "\n".join(f"  · {line}" for line in log))


if __name__ == "__main__":
    main()
