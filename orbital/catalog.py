"""Catálogo unificado: junta todas las fuentes y lanza cualquier elemento."""

from __future__ import annotations

import difflib
import logging
import threading
import unicodedata
from pathlib import Path
from urllib.parse import quote

from .config import Config
from .launcher import Launcher
from .library import emulators, esde, steam, stremio
from .library.models import LibraryItem

log = logging.getLogger(__name__)

CATEGORIES = [
    {"id": "favorites", "title": "Favoritos"},
    {"id": "steam", "title": "Steam"},
    {"id": "emulators", "title": "Emuladores"},
    {"id": "media", "title": "Multimedia"},
    {"id": "apps", "title": "Apps"},
]


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())


class Catalog:
    def __init__(self, config: Config, launcher: Launcher | None = None) -> None:
        self.config = config
        self.launcher = launcher or Launcher()
        self.steam_root: Path | None = None
        self.esde: esde.EsdeLibrary | None = None
        self._items: dict[str, LibraryItem] = {}
        self._lock = threading.Lock()

    # --- escaneo -------------------------------------------------------------
    def refresh(self) -> int:
        found: list[LibraryItem] = []
        if self.config.steam.enabled:
            self.steam_root = steam.find_steam(self.config.steam.path)
            if self.steam_root:
                found += steam.scan(self.steam_root)
                found.append(
                    LibraryItem(
                        id="steam:bigpicture",
                        title="Steam Big Picture",
                        category="apps",
                        source="steam",
                        subtitle="Tienda y biblioteca completa",
                        uri=steam.big_picture_uri(),
                    )
                )
            else:
                log.info("Steam no encontrado")
        self.esde = esde.find(self.config.esde)
        if self.esde and self.esde.executable:
            found.append(
                LibraryItem(
                    id="app:esde",
                    title="ES-DE",
                    category="apps",
                    source="esde",
                    subtitle="Todos tus sistemas",
                    argv=[str(self.esde.executable)],
                    cwd=str(self.esde.executable.parent),
                )
            )
        for emu in self.config.emulators:
            found += emulators.scan(emu, self.esde)
        if self.config.stremio.enabled:
            found += stremio.items(self.config.stremio)
        for app in self.config.apps:
            is_uri = "://" in app.target
            found.append(
                LibraryItem(
                    id=f"app:{app.id}",
                    title=app.name,
                    category=app.category,
                    source="app",
                    uri=app.target if is_uri else None,
                    argv=[] if is_uri else [app.target, *app.args],
                )
            )
        for item in found:
            if item.art_path:
                item.image = f"/api/art/{quote(item.id, safe=':')}"
        with self._lock:
            self._items = {item.id: item for item in found}
        log.info("Catálogo: %d elementos", len(found))
        return len(found)

    # --- consulta ------------------------------------------------------------
    def items(self) -> list[LibraryItem]:
        with self._lock:
            return list(self._items.values())

    def get(self, item_id: str) -> LibraryItem | None:
        with self._lock:
            return self._items.get(item_id)

    def grouped(self) -> list[dict]:
        items = self.items()
        rows = []
        for cat in CATEGORIES:
            if cat["id"] == "favorites":
                members = [i.public() for i in sorted(items, key=lambda i: i.title.lower()) if i.favorite]
            elif cat["id"] == "emulators":
                # Una fila por sistema, en el orden de config.yaml.
                for emu in self.config.emulators:
                    games = [i.public() for i in items if i.category == "emulators" and i.source == emu.id]
                    if games:
                        rows.append({"id": f"emulators:{emu.id}", "title": emu.name, "items": games})
                continue
            else:
                members = [i.public() for i in items if i.category == cat["id"]]
            if members:
                rows.append({**cat, "items": members})
        return rows

    def find(self, query: str, category: str | None = None) -> LibraryItem | None:
        """Búsqueda difusa por título, pensada para lo que transcribe Alexa."""
        target = normalize(query)
        if not target:
            return None
        candidates = [i for i in self.items() if category is None or i.category == category]
        by_name = {normalize(i.title): i for i in candidates}
        if target in by_name:
            return by_name[target]
        # "zelda" debe encontrar "The Legend of Zelda: Breath of the Wild".
        contains = [i for name, i in by_name.items() if target in name]
        if contains:
            return min(contains, key=lambda i: len(i.title))
        close = difflib.get_close_matches(target, list(by_name), n=1, cutoff=0.6)
        return by_name[close[0]] if close else None

    # --- acciones ------------------------------------------------------------
    def launch(self, item_id: str) -> LibraryItem:
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if item.argv:
            proc = self.launcher.run(item.argv, cwd=item.cwd)
            self.launcher.track(item.id, item.title, proc)
        elif item.uri:
            self.launcher.open_uri(item.uri)
            self.launcher.track(item.id, item.title, None)
        else:
            raise ValueError(f"{item.title} no tiene forma de lanzarse")
        return item

    def search_media(self, query: str) -> str:
        uri = stremio.search_uri(query)
        self.launcher.open_uri(uri)
        self.launcher.track("media:stremio", f"Stremio: {query}", None)
        return uri
