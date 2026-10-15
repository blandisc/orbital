from __future__ import annotations

import pytest

from orbital.catalog import Catalog
from orbital.config import parse_config


@pytest.fixture(autouse=True)
def _no_network_art(monkeypatch, tmp_path):
    """Las pruebas nunca salen a internet a buscar portadas ni tocan el arte real del usuario."""
    monkeypatch.setattr("orbital.library.media.default_root", lambda: tmp_path / "media")
    monkeypatch.setattr(Catalog, "scrape_art", lambda self, background=False: 0)


@pytest.fixture(autouse=True)
def _no_real_hardware(monkeypatch):
    """Ninguna prueba cambia el volumen, el brillo o el modo de energía de la consola de verdad
    (un comando de voz «pon el volumen en 9999» en una prueba lo hacía)."""
    from orbital import quick

    fake = {"level": 50, "muted": False, "brightness": 50, "mode": "balanced"}

    def set_volume(level=None, muted=None):
        if level is not None:
            fake["level"] = max(0, min(100, int(level)))
        if muted is not None:
            fake["muted"] = bool(muted)
        return {"level": fake["level"], "muted": fake["muted"]}

    def set_brightness(level):
        fake["brightness"] = max(0, min(100, int(level)))
        return fake["brightness"]

    monkeypatch.setattr(quick, "volume", lambda: {"level": fake["level"], "muted": fake["muted"]})
    monkeypatch.setattr(quick, "set_volume", set_volume)
    monkeypatch.setattr(quick, "brightness", lambda: fake["brightness"])
    monkeypatch.setattr(quick, "set_brightness", set_brightness)
    monkeypatch.setattr(quick, "power_mode", lambda: fake["mode"])
    monkeypatch.setattr(quick, "set_power_mode", lambda mode: fake.update(mode=mode) or mode)


@pytest.fixture(autouse=True)
def _no_real_machine_actions(monkeypatch):
    """Ninguna prueba apaga el equipo ni toca la música de verdad (cerrar programas y actualizar se
    prueban con sus propios dobles: test_memory, test_updater)."""
    from orbital import music, system

    monkeypatch.setattr(system, "power", lambda action: None)
    monkeypatch.setattr(system, "online", lambda: True)  # sin salir a Internet a preguntar
    monkeypatch.setattr(music, "command", lambda action: False)


@pytest.fixture(autouse=True)
def _no_real_screenshots(monkeypatch):
    """Ninguna prueba toma capturas de tu pantalla de verdad («toma una captura» por voz lo hacía)."""
    from orbital import capture

    monkeypatch.setattr(capture, "_game_bar_screenshot", lambda: None)
    monkeypatch.setattr(capture, "_gdi_screenshot", lambda folder, name: None)


@pytest.fixture(autouse=True)
def _no_real_para_ti(monkeypatch):
    """Ninguna prueba habla con Trakt, TMDB, RAWG o la tienda de Steam de verdad (test_foryou pone sus dobles)."""
    from orbital import foryou
    from orbital.library import rawg, tmdb, trakt

    def offline(url, **kwargs):
        raise OSError(f"Sin conexión (pruebas): {url}")

    for module in (trakt, tmdb, rawg):
        monkeypatch.setattr(module, "http_json", offline)
    monkeypatch.setattr(foryou.ForYou, "logo_dark", lambda self, url: None)


@pytest.fixture(autouse=True)
def _no_real_stremio(monkeypatch):
    """Ninguna prueba habla con Stremio de verdad (un login de prueba salía a internet)."""
    from orbital.library import stremio_api

    def offline(self, method, params):
        raise stremio_api.StremioError("Sin conexión (pruebas)")

    monkeypatch.setattr(stremio_api.StremioAPI, "request", offline)


class FakeLauncher:
    def __init__(self):
        self.opened: list[str] = []
        self.ran: list[list[str]] = []
        self.current = None
        self.on_exit = None
        self.steam_appids: list[int | None] = []
        self.last_stopped_by_user = False
        self.last_was_already_open = False

    def open_uri(self, uri):
        self.opened.append(uri)

    def run(self, argv, cwd=None):
        self.ran.append(argv)
        return object()  # basta con que no sea None: cuenta como proceso propio

    def track_exe(self, item_id, title, exe, runner=None):
        self.current = {"id": item_id, "title": title, "managed": True, "runner": runner, "exe": exe}

    def track(self, item_id, title, process, steam_appid=None, runner=None):
        self.steam_appids.append(steam_appid)
        self.current = {"id": item_id, "title": title, "managed": process is not None, "runner": runner}

    def status(self):
        return self.current

    def finish(self, seconds):
        """Simula que el juego en curso se cerró tras `seconds` segundos."""
        cur, self.current = self.current, None
        self.on_exit(cur["id"], cur["title"], seconds)

    def stop(self, force=False):
        was = self.current is not None and self.current["managed"]
        self.current = None
        return was


def write_steam(root, games):
    apps = root / "steamapps"
    apps.mkdir(parents=True)
    (apps / "libraryfolders.vdf").write_text(
        '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' % str(root).replace("\\", "\\\\")
    )
    for appid, name in games.items():
        (apps / f"appmanifest_{appid}.acf").write_text(
            f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n}}\n'
        )


@pytest.fixture
def library(tmp_path):
    steam_root = tmp_path / "Steam"
    write_steam(steam_root, {
        "367520": "Hollow Knight",
        "1145360": "Hades",
        "1493710": "Proton Experimental",
    })
    roms = tmp_path / "roms"
    (roms / "sub").mkdir(parents=True)
    (roms / "Super Mario World (USA).sfc").write_bytes(b"")
    (roms / "sub" / "Chrono_Trigger [!].smc").write_bytes(b"")
    (roms / "notes.txt").write_text("x")
    cfg = parse_config({
        "server": {"token": "secreto"},
        "steam": {"path": str(steam_root)},
        "stremio": {"executable": "stremio-test"},
        "esde": {"enabled": False},
        "detect": {"enabled": False},
        "emulators": [{
            "id": "snes", "name": "Super Nintendo", "executable": "retroarch",
            "args": ["-L", "snes9x", "{rom}"], "rom_dirs": [str(roms)], "extensions": ["sfc", ".SMC"],
        }],
        "apps": [{"id": "yt", "name": "YouTube", "target": "https://youtube.com/tv", "category": "media"}],
    })
    catalog = Catalog(cfg, FakeLauncher())
    catalog.refresh()
    return catalog


@pytest.fixture(autouse=True)
def offline_cinemeta(monkeypatch):
    """Las pruebas nunca van a internet: el catálogo público de Stremio responde vacío."""
    from orbital.library import cinemeta

    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path: {"metas": []})
    from orbital import watch

    monkeypatch.setattr(watch, "RETRY_SECONDS", 0)


@pytest.fixture(autouse=True)
def no_installed_stremio(monkeypatch):
    """Que las pruebas no dependan de si Stremio está instalado en esta máquina (abren el URI)."""
    from orbital.library import stremio

    monkeypatch.setattr(stremio, "find_stremio", lambda cfg: [cfg.executable] if cfg.executable else None)


@pytest.fixture(autouse=True)
def no_geforcenow(monkeypatch):
    """Que las pruebas no lean la instalación ni los accesos directos reales de GeForce NOW."""
    from orbital.library import geforcenow

    monkeypatch.setattr(geforcenow, "install_dir", lambda: None)
    monkeypatch.setattr(geforcenow, "read_shortcuts", list)


@pytest.fixture(autouse=True)
def no_installed_mpv(monkeypatch):
    """Que las pruebas no usen el mpv real (puede haber uno instalado en LOCALAPPDATA)."""
    from orbital import player

    monkeypatch.setattr(player, "find_mpv", lambda: None)


@pytest.fixture(autouse=True)
def no_focus_threads(monkeypatch):
    """Que las pruebas no dejen hilos esperando ventanas reales de juegos."""
    from orbital import focus, sessions

    monkeypatch.setattr(focus, "bring_game_to_front", lambda *args, **kwargs: False)
    # Ni fijar "siempre encima" una ventana real de Orbital que esté abierta mientras corren.
    monkeypatch.setattr(sessions.Sessions, "pin", staticmethod(lambda: None))


@pytest.fixture
def make_client(library):
    """Cliente HTTP de la app, como si viniera del propio equipo."""
    from fastapi.testclient import TestClient

    from orbital.server import create_app

    def make(client=("127.0.0.1", 5000)):
        return TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=client)
    return make
