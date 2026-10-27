"""Carga y validación de la configuración (config.yaml)."""

from __future__ import annotations

import logging
import os
import re
import secrets
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

DEFAULT_PORT = 8710


@dataclass
class ServerConfig:
    host: str = "127.0.0.1"
    port: int = DEFAULT_PORT
    # Token obligatorio para cualquier petición que no venga de la propia máquina
    # (por ejemplo, la skill de Alexa entrando por un túnel).
    token: str = ""
    # Puerto público SOLO para Alexa (voz + ping, siempre con token). El túnel apunta aquí,
    # nunca al puerto principal. 0 lo desactiva.
    public_port: int = DEFAULT_PORT + 1
    token_is_ephemeral: bool = field(default=False, repr=False)


@dataclass
class UiConfig:
    # "browser": abre el navegador en modo kiosko; "window": usa pywebview; "none": solo servidor.
    mode: str = "browser"
    browser: str | None = None
    language: str = "es"


@dataclass
class SteamConfig:
    enabled: bool = True
    path: str | None = None  # None = autodetectar
    # Al abrir un juego de Steam, Steam se abre antes en segundo plano (sin ventana): el juego abre directo, sin su ventana.
    silent_start: bool = True


@dataclass
class EmulatorConfig:
    id: str
    name: str
    executable: str
    system: str = ""
    args: list[str] = field(default_factory=lambda: ["{rom}"])
    rom_dirs: list[str] = field(default_factory=list)
    extensions: list[str] = field(default_factory=list)
    recursive: bool = True
    # Texto que, si aparece en el nombre del archivo, lo excluye (p. ej. "[UPD]", "[DLC]").
    exclude: list[str] = field(default_factory=list)
    # Texto que identifica a este emulador en ES-DE ("Eden" casa con "Eden (Standalone)").
    # Si se omite se usa el nombre del ejecutable.
    esde_label: str | None = None


@dataclass
class EsdeConfig:
    """ES-DE: de aquí salen la carpeta de ROMs, los nombres, las portadas y los favoritos."""

    enabled: bool = True
    path: str | None = None  # carpeta de datos de ES-DE (la que tiene settings/ y gamelists/)
    executable: str | None = None  # ES-DE.exe; None = autodetectar


@dataclass
class DownloadsConfig:
    dir: str | None = None  # dónde se guardan las descargas (si no: Videos\Orbital)


@dataclass
class DetectConfig:
    """Detección automática de emuladores en Descargas, Escritorio, C:\\Emuladores, etc."""

    enabled: bool = True
    dirs: list[str] = field(default_factory=list)  # carpetas extra donde buscar
    # La carpeta de tus juegos, una subcarpeta por consola (ROMs\switch, ROMs\gc…). Sin ES-DE, de aquí sale la de cada
    # emulador detectado; con ES-DE (si está encendido), la suya.
    roms: str | None = None


@dataclass
class StremioConfig:
    enabled: bool = True
    executable: str | None = None  # None = autodetectar
    # Para elegir la fuente por ti: idioma del audio ("en", "es"…) y resolución ("1080p" o "4K").
    audio: str = "en"
    quality: str = "1080p"
    subtitles: str = "en"  # "" = sin subtítulos
    # "orbital": reproductor propio (mpv) manejado con el mando; "stremio": el de Stremio.
    player: str = "orbital"


@dataclass
class AppConfig:
    """Accesos directos extra: un ejecutable o una URL/URI."""

    id: str
    name: str
    target: str
    args: list[str] = field(default_factory=list)
    category: str = "apps"


@dataclass
class ArtConfig:
    """Arte de los juegos que Orbital consigue por su cuenta (portada, fondo, logotipo)."""
    scrape: bool = True  # buscar en internet lo que falte (libretro, TheGamesDB, Steam)
    dir: str | None = None  # carpeta propia; por defecto %LOCALAPPDATA%\orbital\media


@dataclass
class SessionsConfig:
    """Que nada se quede abierto para siempre."""
    # Minutos que un video puede quedar en pausa antes de cerrarse solo (el avance se guarda en
    # Stremio y sigues donde te quedaste). 0 = nunca.
    video_idle_minutes: int = 15
    # Minutos que un juego puede quedar congelado (saliste con Home) antes de cerrarse solo. Lo no
    # guardado se pierde, por eso es más largo. 0 = nunca.
    game_idle_minutes: int = 60
    # Abrir algo nuevo cierra lo que estaba abierto (como una consola): si no, quedaba olvidado.
    close_previous: bool = True


@dataclass
class ParaTiConfig:
    """«Para ti»: recomendaciones. Cada servicio es opcional; sin su clave, sus listas no aparecen.

    - Trakt (trakt.tv/oauth/applications): tus listas, tendencias y recomendaciones. Tu cuenta se
      conecta desde la consola con un código (no aquí).
    - TMDB (themoviedb.org/settings/api): lo más popular en Netflix, Disney+ y HBO Max, y sinopsis en español.
    - RAWG (rawg.io/apidocs): novedades, lo más popular y lo mejor calificado en juegos.
    - SteamGridDB (steamgriddb.com › Preferences › API): más portadas y fondos para elegir en tus juegos.
    Las claves pueden ir cifradas con tu usuario de Windows («dpapi:…»), como el token de Alexa.
    """
    trakt_client_id: str = ""
    trakt_client_secret: str = ""
    tmdb_key: str = ""
    rawg_key: str = ""
    steamgriddb_key: str = ""
    region: str = "MX"  # país para «lo más popular en…» (código de dos letras)


@dataclass
class TvConfig:
    """La tele (Roku TV): «Alexa, abre mi consola» la prende y la pone en la entrada de Orbital.

    Sin `host` no se toca. `orbital tv setup` la encuentra y escribe esta sección.
    """
    host: str = ""  # su IP en la red local
    serial: str = ""  # para volver a encontrarla si cambia de IP
    mac: str = ""  # para despertarla por Wi-Fi desde el reposo profundo
    input: str = "hdmi1"  # la entrada del Legion Go


@dataclass
class Config:
    server: ServerConfig = field(default_factory=ServerConfig)
    ui: UiConfig = field(default_factory=UiConfig)
    steam: SteamConfig = field(default_factory=SteamConfig)
    stremio: StremioConfig = field(default_factory=StremioConfig)
    esde: EsdeConfig = field(default_factory=EsdeConfig)
    detect: DetectConfig = field(default_factory=DetectConfig)
    downloads: DownloadsConfig = field(default_factory=DownloadsConfig)
    sessions: SessionsConfig = field(default_factory=SessionsConfig)
    art: ArtConfig = field(default_factory=ArtConfig)
    para_ti: ParaTiConfig = field(default_factory=ParaTiConfig)
    tv: TvConfig = field(default_factory=TvConfig)
    emulators: list[EmulatorConfig] = field(default_factory=list)
    apps: list[AppConfig] = field(default_factory=list)
    source: Path | None = None


def expand(path: str) -> str:
    return os.path.expanduser(os.path.expandvars(path))


def _section(cls, data: dict[str, Any] | None):
    data = dict(data or {})
    known = cls.__dataclass_fields__.keys()
    unknown = set(data) - set(known)
    if unknown:
        raise ValueError(f"Claves desconocidas en {cls.__name__}: {', '.join(sorted(unknown))}")
    return cls(**data)


def default_config_path() -> Path:
    env = os.environ.get("ORBITAL_CONFIG")
    if env:
        return Path(env)
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", Path.home()))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return base / "orbital" / "config.yaml"


def parse_config(raw: dict[str, Any] | None, source: Path | None = None) -> Config:
    raw = raw or {}
    cfg = Config(
        server=_section(ServerConfig, raw.get("server")),
        ui=_section(UiConfig, raw.get("ui")),
        steam=_section(SteamConfig, raw.get("steam")),
        stremio=_section(StremioConfig, raw.get("stremio")),
        esde=_section(EsdeConfig, raw.get("esde")),
        detect=_section(DetectConfig, raw.get("detect")),
        downloads=_section(DownloadsConfig, raw.get("downloads")),
        sessions=_section(SessionsConfig, raw.get("sessions")),
        art=_section(ArtConfig, raw.get("art")),
        para_ti=_section(ParaTiConfig, raw.get("para_ti")),
        tv=_section(TvConfig, raw.get("tv")),
        emulators=[_section(EmulatorConfig, e) for e in raw.get("emulators") or []],
        apps=[_section(AppConfig, a) for a in raw.get("apps") or []],
        source=source,
    )
    ids = [e.id for e in cfg.emulators] + [a.id for a in cfg.apps]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise ValueError(f"IDs duplicados en la configuración: {', '.join(sorted(dupes))}")
    for emu in cfg.emulators:
        # Permite %USERPROFILE%, %APPDATA%, ~ ... en las rutas.
        emu.executable = expand(emu.executable)
        emu.rom_dirs = [expand(d) for d in emu.rom_dirs]
        emu.extensions = [e.lower() if e.startswith(".") else f".{e.lower()}" for e in emu.extensions]
    if cfg.ui.mode not in {"browser", "window", "none"}:
        raise ValueError("ui.mode debe ser 'browser', 'window' o 'none'")
    region = str(cfg.para_ti.region or "").strip().upper()
    if len(region) != 2 or not region.isalpha():
        raise ValueError("para_ti.region debe ser un país de dos letras (por ejemplo MX)")
    cfg.para_ti.region = region
    cfg.tv.host = str(cfg.tv.host or "").strip()
    cfg.tv.input = str(cfg.tv.input or "").strip().lower().removeprefix("tvinput.")
    if not re.fullmatch(r"hdmi\d|av\d|dtv", cfg.tv.input):
        raise ValueError("tv.input debe ser una entrada de la tele: hdmi1, hdmi2, hdmi3, av1 o dtv")
    for key in ("trakt_client_id", "trakt_client_secret", "tmdb_key", "rawg_key", "steamgriddb_key"):
        setattr(cfg.para_ti, key, str(getattr(cfg.para_ti, key) or "").strip())
    return cfg


def load_config(path: Path | None = None) -> Config:
    path = path or default_config_path()
    if not path.exists():
        cfg = Config(source=path)
    else:
        with path.open("r", encoding="utf-8") as fh:
            cfg = parse_config(yaml.safe_load(fh), source=path)
    if cfg.server.token.startswith("dpapi:"):  # guardado cifrado con tu usuario de Windows
        from .dpapi import reveal

        try:
            cfg.server.token = reveal(cfg.server.token)
        except ValueError as exc:
            logging.getLogger(__name__).warning("%s: Alexa queda desconectada hasta `orbital alexa setup`", exc)
            cfg.server.token = ""
    for key in ("trakt_client_id", "trakt_client_secret", "tmdb_key", "rawg_key", "steamgriddb_key"):
        value = getattr(cfg.para_ti, key)
        if value.startswith("dpapi:"):
            from .dpapi import reveal

            try:
                setattr(cfg.para_ti, key, reveal(value))
            except ValueError as exc:
                logging.getLogger(__name__).warning("para_ti.%s: %s", key, exc)
                setattr(cfg.para_ti, key, "")
    if cfg.server.token in ("", "CAMBIA-ESTE-TOKEN"):
        # Sin token propio generamos uno efímero: Alexa queda desconectada hasta fijar uno
        # (orbital alexa setup lo hace por ti).
        cfg.server.token = secrets.token_urlsafe(24)
        cfg.server.token_is_ephemeral = True
    return cfg
