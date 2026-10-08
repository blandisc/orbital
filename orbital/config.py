"""Carga y validación de la configuración (config.yaml)."""

from __future__ import annotations

import os
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
class DetectConfig:
    """Detección automática de emuladores en Descargas, Escritorio, C:\\Emuladores, etc."""

    enabled: bool = True
    dirs: list[str] = field(default_factory=list)  # carpetas extra donde buscar


@dataclass
class StremioConfig:
    enabled: bool = True
    executable: str | None = None  # None = autodetectar


@dataclass
class AppConfig:
    """Accesos directos extra: un ejecutable o una URL/URI."""

    id: str
    name: str
    target: str
    args: list[str] = field(default_factory=list)
    category: str = "apps"


@dataclass
class Config:
    server: ServerConfig = field(default_factory=ServerConfig)
    ui: UiConfig = field(default_factory=UiConfig)
    steam: SteamConfig = field(default_factory=SteamConfig)
    stremio: StremioConfig = field(default_factory=StremioConfig)
    esde: EsdeConfig = field(default_factory=EsdeConfig)
    detect: DetectConfig = field(default_factory=DetectConfig)
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
    return cfg


def load_config(path: Path | None = None) -> Config:
    path = path or default_config_path()
    if not path.exists():
        cfg = Config(source=path)
    else:
        with path.open("r", encoding="utf-8") as fh:
            cfg = parse_config(yaml.safe_load(fh), source=path)
    if cfg.server.token in ("", "CAMBIA-ESTE-TOKEN"):
        # Sin token propio generamos uno efímero: Alexa queda desconectada hasta fijar uno
        # (orbital alexa setup lo hace por ti).
        cfg.server.token = secrets.token_urlsafe(24)
        cfg.server.token_is_ephemeral = True
    return cfg
