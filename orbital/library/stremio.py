"""Integración con Stremio (centro multimedia)."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from urllib.parse import quote

from ..config import StremioConfig
from .models import LibraryItem


def candidate_paths() -> list[Path]:
    if sys.platform == "win32":
        local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return [
            local / "Programs" / "Stremio" / "stremio-shell-ng.exe",  # Stremio 5
            local / "Programs" / "LNV" / "Stremio-4" / "stremio.exe",  # Stremio 4
        ]
    if sys.platform == "darwin":
        return [Path("/Applications/Stremio.app/Contents/MacOS/Stremio")]
    return [Path("/opt/stremio/stremio"), Path("/usr/bin/stremio")]


def find_stremio(cfg: StremioConfig) -> list[str] | None:
    """Devuelve el comando para abrir Stremio, o None si hay que recurrir al URI stremio://."""
    if cfg.executable:
        return [cfg.executable]
    for path in candidate_paths():
        if path.exists():
            return [str(path)]
    if shutil.which("stremio"):
        return ["stremio"]
    if sys.platform.startswith("linux") and shutil.which("flatpak"):
        return ["flatpak", "run", "com.stremio.Stremio"]
    return None


def search_uri(query: str) -> str:
    return f"stremio:///search?search={quote(query)}"


def items(cfg: StremioConfig) -> list[LibraryItem]:
    argv = find_stremio(cfg)
    return [
        LibraryItem(
            id="media:stremio",
            title="Stremio",
            category="media",
            source="stremio",
            subtitle="Películas y series",
            argv=argv or [],
            uri=None if argv else "stremio://",
        )
    ]
