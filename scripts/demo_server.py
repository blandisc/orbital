"""Orbital de mentiras para probar la interfaz (pruebas de humo, Playwright, revisar a mano).

Una biblioteca inventada en una carpeta temporal, sin tu config, sin tu estado, sin internet y sin
abrir nada de verdad (el lanzador solo anota). No interfiere con el Orbital real: otro puerto.

    python scripts/demo_server.py [--port 8730]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import demo_foryou  # noqa: E402
import demo_tv  # noqa: E402
import uvicorn  # noqa: E402

from orbital.catalog import Catalog  # noqa: E402
from orbital.config import parse_config  # noqa: E402
from orbital.library import cinemeta, geforcenow, stremio  # noqa: E402
from orbital.server import create_app  # noqa: E402

GAMES = {"367520": "Hollow Knight", "1145360": "Hades", "504230": "Celeste", "632360": "Risk of Rain 2",
         "1086940": "Baldur's Gate 3", "413150": "Stardew Valley", "1313140": "Cult of the Lamb", "440": "Team Fortress 2",
         "2499520": "Be My Horde"}
# Consolas inventadas (sin arte: así se ven los respaldos) para probar el Inicio y Tus consolas.
CONSOLES = {
    "switch": ("Nintendo Switch", ".nsp", ["Mario Party Superstars", "Super Mario Bros Wonder", "Zelda Tears of the Kingdom"]),
    "gc": ("Nintendo GameCube", ".iso", ["Pikmin 2", "Super Smash Bros. Melee"]),
    "gba": ("Game Boy Advance", ".gba", ["Pokemon Emerald", "Kirby Amazing Mirror", "Metroid Fusion"]),
    "psp": ("PlayStation Portable", ".iso", ["Metal Slug Anthology"]),
    "xbox360": ("Xbox 360", ".iso", ["Halo 3", "Gears of War"]),
    "wii": ("Nintendo Wii", ".iso", ["Wii Sports"]),
}
# Portadas de GBA de verdad (el navegador las trae de libretro): son cajas casi cuadradas, no pósters.
LIBRETRO = "https://thumbnails.libretro.com/Nintendo%20-%20Game%20Boy%20Advance/Named_Boxarts/"
GBA_ART = {"Pokemon Emerald": "Pokemon%20-%20Emerald%20Version%20(USA%2C%20Europe).png",
           "Kirby Amazing Mirror": "Kirby%20%26%20The%20Amazing%20Mirror%20(USA).png",
           "Metroid Fusion": "Metroid%20Fusion%20(USA).png"}
# Lo último que "jugaste" (minutos atrás): llena Continuar y el destacado.
PLAYED = {"steam:1145360": 30, "Mario Party Superstars": 240, "Pikmin 2": 1500, "steam:367520": 2900, "Pokemon Emerald": 4000}


class DryLauncher:
    """Como el de verdad, pero no abre nada: recuerda qué "está abierto"."""

    def __init__(self) -> None:
        self.current = None
        self.on_exit = None
        self.on_timeout = None
        self.last_stopped_by_user = False

    def open_uri(self, uri):
        pass

    def run(self, argv, cwd=None):
        return object()

    def track_exe(self, item_id, title, exe, runner=None):
        self.track(item_id, title, None, runner=runner)

    def track(self, item_id, title, process, steam_appid=None, runner=None):
        self.current = {"id": item_id, "title": title, "managed": True, "runner": runner, "started": time.time(),
                        "pid": None}

    def status(self):
        return dict(self.current) if self.current else None

    def stop(self, force=False):
        cur, self.current = self.current, None
        self.last_stopped_by_user = True
        if cur and self.on_exit:
            self.on_exit(cur["id"], cur["title"], time.time() - cur["started"])
        return cur is not None


# Unas fichas de mentiras (sin internet): así el recorrido también pasa por la ficha, los episodios y Fuentes.
DEMO_TITLES = {
    ("series", "tt0386676"): {"name": "The Office", "year": "2005–2013", "imdbRating": "9.0", "genres": ["Comedy"],
                              "description": "Un falso documental sobre la vida diaria en una oficina de papel en Scranton, Pensilvania: Michael Scott, un gerente que se cree el jefe más gracioso del mundo, y los empleados que lo aguantan entre juntas inútiles, bromas a Dwight y el romance que crece despacio en la recepción.",
                              # larga a propósito: la ficha la corta y ofrece «Ver más»
                              "seasons": 2, "episodes": 4, "hero": "hero-generic-3.jpg"},
    ("series", "tt11280740"): {"name": "Severance", "year": "2022–", "imdbRating": "8.7", "genres": ["Drama", "Mystery"],
                               "description": "Mark dirige un equipo cuyos recuerdos del trabajo y de la vida personal fueron separados.",
                               "seasons": 2, "episodes": 3, "upcoming": True, "hero": "hero-switch-2.jpg"},
    ("movie", "tt0816692"): {"name": "Interstellar", "year": "2014", "imdbRating": "8.7", "genres": ["Adventure", "Sci-Fi"],
                             "description": "Con la Tierra muriendo por las plagas y el polvo, un expiloto de la NASA deja a sus hijos para llevar a un grupo de exploradores a través de un agujero de gusano junto a Saturno, en busca de un planeta donde la humanidad pueda empezar de nuevo, sabiendo que cada hora allá son años aquí.",
                             "runtime": "169 min", "hero": "hero-xbox-2.jpg"},
}


def demo_meta(kind: str, meta_id: str) -> dict | None:
    t = DEMO_TITLES.get((kind, meta_id))
    if not t:
        return None
    hero = f"/img/placeholders/{t['hero']}"
    meta = {"id": meta_id, "type": kind, "name": t["name"], "year": t["year"], "releaseInfo": t["year"], "imdbRating": t["imdbRating"],
            "genres": t["genres"], "description": t["description"], "background": hero, "poster": hero, "runtime": t.get("runtime", "")}
    if kind == "series":
        videos = []
        for season in range(1, t["seasons"] + 1):
            for ep in range(1, t["episodes"] + 1):
                future = t.get("upcoming") and season == t["seasons"] and ep == t["episodes"]
                videos.append({"id": f"{meta_id}:{season}:{ep}", "season": season, "episode": ep, "number": ep,
                               "title": f"Episodio {ep}", "name": f"Episodio {ep}", "thumbnail": hero,
                               "released": "2030-01-01T00:00:00.000Z" if future else f"20{10 + season}-0{ep}-01T00:00:00.000Z",
                               "overview": f"Lo que pasa en el episodio {ep} de la temporada {season}."})
        meta["videos"] = videos
    if os.environ.get("ORBITAL_DEMO_LONG") == "1":  # pruebas: la ficha y sus episodios con nombres larguísimos
        meta["name"] += ": La Saga Completa en Versión Extendida del Director"
        for video in meta.get("videos", []):
            video["title"] = video["name"] = f"{video['name']}: El Regreso del Viajero que Nunca Supo Volver a Casa"
    return meta


def demo_cinemeta(self, path: str, base: str | None = None) -> dict:
    """Cinemeta sin internet: las fichas de DEMO_TITLES; búsqueda y catálogo sobre ellas."""
    import re as _re
    from urllib.parse import unquote
    m = _re.match(r"^/meta/(movie|series)/([^/]+)\.json$", path)
    if m:
        meta = demo_meta(m.group(1), unquote(m.group(2)))
        return {"meta": meta} if meta else {}
    m = _re.match(r"^/catalog/(movie|series)/top(?:/search=(.*))?\.json$", path)
    if m:
        query = unquote(m.group(2) or "").lower()
        return {"metas": [demo_meta(k, i) for (k, i), t in DEMO_TITLES.items() if k == m.group(1) and query in t["name"].lower()]}
    return {"metas": []}


def demo_downloads(catalog, tmp: Path) -> None:
    """Descargas sin internet: un archivo de mentiras (25 MB) que «baja» poco a poco, para ver el avance en la tele."""
    import io
    import threading

    fake = tmp / "video-de-muestra.mkv"
    fake.write_bytes(bytes(25 << 20))

    class Slow(io.BufferedReader):
        status = 200
        url = "https://demo/Pelicula.mkv"
        headers = {"Content-Length": str(fake.stat().st_size), "Content-Type": "video/x-matroska"}

        def read(self, size=-1):
            time.sleep(.35)
            return super().read(size)

    catalog.downloads.resolve = lambda job: ("https://demo/Pelicula.mkv", "Pelicula.1080p.mkv")
    catalog.downloads.opener = lambda request, timeout=0: Slow(open(fake, "rb"))
    threading.Thread(target=catalog.downloads._worker, name="descargas-demo", daemon=True).start()


def demo_onedrive(catalog) -> None:
    """Mi media sin cuenta de Microsoft: una carpeta de mentiras ya revisada (con fechas, una serie y uno sin ficha)."""
    now = time.time()
    lib = catalog.onedrive
    class DemoOneDrive:  # el demo no habla con Microsoft
        configured = linked = True

        def stream_url(self, item_id):
            return f"https://demo.onedrive/{item_id}"
    lib.client = DemoOneDrive()
    lib.state.set_setting("onedrive_folder", "Películas")
    files = [("A1", "Dune Part Two (2024) 2160p.mkv", "movie", "tt15239678", "Dune: Parte dos", 2024, None, None, 2),
             ("A2", "Dune (2021) 1080p.mkv", "movie", "tt1160419", "Dune", 2021, None, None, 40),
             ("A3", "Interstellar (2014).mkv", "movie", "tt0816692", "Interstellar", 2014, None, None, 5),
             ("B1", "Severance.S01E01.mkv", "series", "tt11280740", "Severance", None, 1, 1, 20),
             ("B2", "Severance.S01E02.mkv", "series", "tt11280740", "Severance", None, 1, 2, 20),
             ("C1", "Cumpleaños de la abuela 2019.mp4", "movie", None, None, None, None, None, 1)]
    lib.files = [{"id": i, "name": n, "path": f"Películas/{n}", "size": 1, "kind": k, "title": t or n, "added": now - d * 86400,
                  **({"imdb": imdb, "show_title": t, "show_year": y} if imdb else {}),
                  **({"season": se, "episode": ep} if se else {})}
                 for i, n, k, imdb, t, y, se, ep, d in files]
    lib.scanned_at = now
    lib.maybe_rescan = lambda: None
    catalog.foryou.sagas = lambda imdbs: [{"id": 726871, "name": "Dune: colección", "imdbs": [i for i in imdbs if i in ("tt15239678", "tt1160419")]}]


def no_side_effects() -> None:
    """Nada de lo que se pulse en el demo toca este equipo: ni volumen, brillo o energía, ni apagar,
    ni ventanas, ni capturas, ni la música, ni cerrar programas, ni actualizar (git) la carpeta.
    (Un agente cambió el modo de energía de verdad desde el Panel rápido del demo.)"""
    from orbital import capture, companion, memory, music, quick, system, updater
    from orbital.shell import ConsoleShell

    fake = {"level": 60, "muted": False, "brightness": 70, "mode": "balanced"}

    def set_volume(level=None, muted=None):
        if level is not None:
            fake["level"] = max(0, min(100, int(level)))
        if muted is not None:
            fake["muted"] = bool(muted)
        return {"level": fake["level"], "muted": fake["muted"]}

    def set_brightness(level):
        fake["brightness"] = max(0, min(100, int(level)))
        return fake["brightness"]

    quick.volume = lambda: {"level": fake["level"], "muted": fake["muted"]}
    quick.set_volume = set_volume
    quick.brightness = lambda: fake["brightness"]
    quick.set_brightness = set_brightness
    quick.power_mode = lambda: fake["mode"]
    quick.set_power_mode = lambda mode: fake.update(mode=mode) or mode
    system.power = lambda action: print(f"[demo] {action} (no se hizo)")
    capture.take = lambda title="": None
    music.command = lambda action: False
    memory.close = lambda exe, protect_pids=None: 0
    # Los QR (iPhone, escribir desde el celular) no llevan la dirección real del túnel: apuntarían a tu Orbital de verdad.
    companion.pair_info = lambda config, tailscale_url=None: {"ready": True, "host": "demo.orbital.invalid",
                                                              "link": companion.pair_link("https://demo.orbital.invalid", "demo")}
    # Tampoco enseña los programas de este equipo (salían la app de Claude y lo que tengas abierto): unos de mentiras.
    memory.usage = lambda limit=6, protect_pids=None: [
        memory.AppUsage("steam.exe", "Steam", 1300, [], True, "Las descargas siguen cuando lo vuelvas a abrir"),
        memory.AppUsage("Discord.exe", "Discord", 620, [], True),
        memory.AppUsage("msedge.exe", "Edge", 1400, [], False, "De Windows u Orbital: no se cierra")][:limit]
    ConsoleShell.open_windows = lambda self: []
    ConsoleShell.focus_window = lambda self, hwnd: False
    updater.Updater.apply = lambda self, progress=lambda m: None: (False, "En el demo no se actualiza.")


# Lo que en la consola de verdad traen la tienda de Steam o ScreenScraper (la ficha de un juego en Juegos).
GAME_INFO = {
    "Hades": {"description": "Desafía al dios de los muertos mientras te abres paso a golpes fuera del Inframundo en este "
                             "roguelike de acción de los creadores de Bastion y Transistor.",
              "genres": ["Action", "Indie", "RPG"], "developer": "Supergiant Games", "year": "2020", "controller": "full",
              "size": 15_300_000_000},
    "Hollow Knight": {"description": "Forja tu camino en Hollow Knight, una aventura de acción clásica en un vasto mundo "
                                     "interconectado de insectos y héroes.",
                      "genres": ["Action", "Adventure", "Indie"], "developer": "Team Cherry", "year": "2017",
                      "controller": "full", "size": 9_100_000_000},
    "Mario Party Superstars": {"description": "Cinco tableros clásicos de Nintendo 64 y cien minijuegos de toda la serie.",
                               "genres": ["Party"], "developer": "NDcube", "year": "2021", "players": "4"},
}


def build(tmp: Path):
    apps = tmp / "Steam" / "steamapps"
    apps.mkdir(parents=True)
    (apps / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % str(tmp / "Steam").replace("\\", "\\\\"))
    for appid, name in GAMES.items():
        (apps / f"appmanifest_{appid}.acf").write_text(f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n')
    emulators = []
    for system, (name, ext, titles) in CONSOLES.items():
        roms = tmp / "ROMs" / system
        roms.mkdir(parents=True)
        for title in titles:
            (roms / f"{title}{ext}").write_bytes(b"")
        emulators.append({"id": system, "name": name, "system": system, "executable": str(tmp / "emu.exe"),
                          "rom_dirs": [str(roms)], "extensions": [ext]})
    (tmp / "emu.exe").write_bytes(b"")
    config = parse_config({
        "server": {"token": "demo"},
        "emulators": emulators,
        "art": {"scrape": False, "dir": str(tmp / "media")},
        "steam": {"path": str(tmp / "Steam")},
        "stremio": {"executable": ""},
        "esde": {"enabled": False},
        "detect": {"enabled": False},
        "downloads": {"dir": str(tmp / "Descargas")},  # nunca en Videos\Orbital de verdad
        "apps": [{"id": "yt", "name": "YouTube", "target": "https://youtube.com/tv", "category": "media"}],
    })
    # Sin internet ni programas de este equipo.
    no_side_effects()
    cinemeta.Cinemeta._get = demo_cinemeta
    stremio.find_stremio = lambda cfg: None
    geforcenow.install_dir = lambda: None
    geforcenow.read_shortcuts = list
    catalog = Catalog(config, DryLauncher())
    catalog.refresh()
    now = time.time()
    for item in catalog.store.all():
        minutes = PLAYED.get(item.id, PLAYED.get(item.title))
        if minutes:
            catalog.state.record_launch(item.id, now=now - minutes * 60)
    # «Para ti»: horas y un favorito (para «Tu más jugado» y «Tu favorito») y servicios de mentiras.
    refresh = catalog.refresh

    long_names = os.environ.get("ORBITAL_DEMO_LONG") == "1"  # pruebas: nombres larguísimos (¿algo se corta o se encima?)

    def refresh_with_gba_art(*args, **kwargs):  # cada vez que se vuelve a leer la biblioteca
        found = refresh(*args, **kwargs)
        for n, item in enumerate(catalog.store.all()):
            if long_names and n % 3 == 0 and not item.title.endswith("Descargables"):
                item.title = f"{item.title}: Edición Definitiva del Coleccionista con Todos los Contenidos Descargables"
            item.extra.update(GAME_INFO.get(item.title, {}))  # la ficha de un juego: sin Internet, datos de muestra
            if item.system == "gba" and item.title in GBA_ART:
                item.image = LIBRETRO + GBA_ART[item.title]
                item.extra.pop("placeholder_cover", None)
        return found

    catalog.refresh = refresh_with_gba_art
    catalog.refresh()
    catalog.state.record_session("steam:1145360", 48 * 3600)
    catalog.state.record_session("steam:2499520", 5 * 3600)
    catalog.state.record_session("steam:1086940", 62 * 3600)
    catalog.set_prefs("steam:367520", favorite=True)
    demo_foryou.install(catalog)
    demo_downloads(catalog, tmp)
    demo_onedrive(catalog)
    demo_tv.install(catalog, tmp)  # «TV en vivo»: canales y logos de mentiras, sin Internet ni mpv
    demo_sources(catalog)
    return create_app(config, catalog)


def demo_sources(catalog) -> None:
    """«Elegir versión» sin internet: las fuentes REALES que dio Torrentio con Real-Debrid (tests/fixtures/streams) para
    cualquier título (películas: Dune; series: Los Simpson; anime si el id es el de Frieren)."""
    from orbital.library import streams

    fixture = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "streams" / "torrentio_rd_2026-10-20.json"
    titles = {t["video_id"].split(":")[0]: t for t in json.loads(fixture.read_text("utf-8"))["titles"]}

    def stream_sources(kind, video_id, prefs=None):
        title = titles.get(video_id.split(":")[0]) or titles["tt15239678" if kind == "movie" else "tt0096697"]
        found = []
        for i, stream in enumerate(title["streams"]):
            src = streams.parse(stream, "Torrentio", "https://torrentio.strem.fun/manifest.json", i, title["original"])
            src.other_title = not streams.mentions_title(title["titles"], src.release)
            found.append(src)
        return streams.rank(found, prefs or catalog.watch.stream_prefs, kind)

    catalog.watch.stream_sources = stream_sources


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8730)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="orbital-demo-") as tmp:
        # Los diagnósticos del demo (entrada.log, voz.log) en su carpeta temporal, nunca en los de la consola de verdad.
        from orbital import input_log, voice_log

        input_log.default_path = lambda: Path(tmp) / "entrada.log"
        voice_log.default_path = lambda: Path(tmp) / "voz.log"
        uvicorn.run(build(Path(tmp)), host="127.0.0.1", port=args.port, log_level="warning",
                    timeout_graceful_shutdown=2)  # con /api/events abierto no terminaba nunca


if __name__ == "__main__":
    main()
