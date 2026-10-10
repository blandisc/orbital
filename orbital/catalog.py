"""Catálogo unificado: junta todas las fuentes, aplica las preferencias y lanza cualquier elemento."""

from __future__ import annotations

import difflib
import logging
import threading
import time
import unicodedata
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote

from . import system
from .config import Config
from .launcher import Launcher
from .credentials import Credentials
from .library import cinemeta, detect, emulators, esde, steam, stremio, stremio_api
from .library.models import LibraryItem
from .state import State

STREMIO_KEY = "stremio_auth_key"
STREMIO_STALE_SECONDS = 180

log = logging.getLogger(__name__)

CATEGORIES = [
    {"id": "recent", "title": "Jugado recientemente"},
    {"id": "continue", "title": "Seguir viendo"},
    {"id": "favorites", "title": "Favoritos"},
    {"id": "steam", "title": "Steam"},
    {"id": "emulators", "title": "Emuladores"},
    {"id": "media", "title": "Multimedia"},
    {"id": "movies", "title": "Películas populares"},
    {"id": "series", "title": "Series populares"},
    {"id": "apps", "title": "Apps"},
]

# listener(evento) — el servidor lo usa para avisar a la interfaz.
Listener = Callable[[dict], None]


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())


def default_state(config: Config) -> State:
    if config.source is None:
        return State(None)
    return State(config.source.parent / "state.json")


def default_credentials(config: Config) -> Credentials:
    return Credentials(config.source.parent / "secrets.json" if config.source else None)


def stremio_item(w: stremio_api.Watchable) -> LibraryItem:
    season, episode = w.episode
    if episode is not None:
        detail = f"T{season} E{episode}" if season is not None else f"Episodio {episode}"
    else:
        detail = "Película" if w.type == "movie" else "Serie" if w.type == "series" else ""
    return LibraryItem(
        id=f"stremio:{w.id}",
        title=w.name,
        # Solo "Seguir viendo" tiene fila; el resto de la biblioteca sirve para la voz.
        category="continue" if w.in_continue else "stremio",
        source="stremio",
        subtitle=" · ".join(filter(None, ["Stremio", detail])),
        image=w.poster,
        hero=w.background,
        uri=w.deep_link,
        progress=w.progress,
        last_watched=w.last_watched,
    )


class Catalog:
    def __init__(self, config: Config, launcher: Launcher | None = None, state: State | None = None,
                 credentials: Credentials | None = None, stremio_client: stremio_api.StremioAPI | None = None,
                 cinemeta_client: cinemeta.Cinemeta | None = None) -> None:
        self.config = config
        self.launcher = launcher or Launcher()
        self.launcher.on_exit = self._session_ended
        self.kiosk = None  # KioskWindow si Orbital abrió la interfaz (la reabre al cerrar un juego)
        self.state = state or default_state(config)
        self.steam_root: Path | None = None
        self.esde: esde.EsdeLibrary | None = None
        # Emuladores en uso: los de config.yaml + los detectados automáticamente.
        self.emulators = list(config.emulators)
        self.detected: dict[str, Path] = {}
        self.credentials = credentials or default_credentials(config)
        self.stremio_client = stremio_client or stremio_api.StremioAPI()
        self.stremio_error: str | None = None
        self._stremio_items: list[LibraryItem] = []
        self._stremio_fetched = 0.0
        self._stremio_busy = threading.Lock()
        self.cinemeta = cinemeta_client or cinemeta.Cinemeta()
        self._cinemeta_items: list[LibraryItem] = []
        self.listeners: list[Listener] = []
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
        self.emulators = list(self.config.emulators)
        self.detected = {}
        if self.config.detect.enabled:
            dirs = detect.default_search_dirs(self.config.detect.dirs, self.esde.executable if self.esde else None)
            result = detect.detect(dirs, skip_ids={e.id for e in self.config.emulators})
            self.emulators = detect.merge(self.config.emulators, result.emulators)
            self.detected = result.found
        for emu, alternatives in emulators.split_alternatives(self.emulators):
            found += emulators.scan(emu, self.esde, alternatives)
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
        found += self._stremio_items
        found += self._cinemeta_items
        for item in found:
            url = f"/api/art/{quote(item.id, safe=':')}"
            if item.art_path:
                item.image = url
            if item.hero_path:
                item.hero = url + "?kind=hero"
        with self._lock:
            self._items = {item.id: item for item in found}
        log.info("Catálogo: %d elementos", len(found))
        self.refresh_stremio(background=True)
        if not self._cinemeta_items:
            self.refresh_cinemeta(background=True)
        return len(found)

    # --- Stremio -------------------------------------------------------------
    @property
    def stremio_linked(self) -> bool:
        return bool(self.credentials.get(STREMIO_KEY))

    def refresh_stremio(self, background: bool = False) -> bool:
        """Descarga la biblioteca de Stremio. En segundo plano no bloquea a quien llama."""
        if not self.config.stremio.enabled or not self.stremio_linked:
            return False
        if background:
            threading.Thread(target=self.refresh_stremio, daemon=True).start()
            return True
        if not self._stremio_busy.acquire(blocking=False):
            return False  # ya hay una descarga en curso
        try:
            raw = self.stremio_client.library(self.credentials.get(STREMIO_KEY))
            items = [stremio_item(w) for w in stremio_api.parse_library(raw)]
            self.stremio_error = None
        except stremio_api.StremioError as exc:
            log.warning("Stremio: %s", exc)
            self.stremio_error = str(exc)
            return False
        finally:
            self._stremio_fetched = time.time()
            self._stremio_busy.release()
        with self._lock:
            self._items = {k: v for k, v in self._items.items() if v.source != "stremio"}
            self._items.update({i.id: i for i in items})
        changed = [i.id for i in items] != [i.id for i in self._stremio_items] or any(
            a.progress != b.progress for a, b in zip(items, self._stremio_items))
        self._stremio_items = items
        if changed:
            self._notify({"type": "library-changed"})
        return True

    def refresh_cinemeta(self, background: bool = False) -> bool:
        """Películas y series populares (catálogo público de Stremio; no necesita cuenta)."""
        if not self.config.stremio.enabled:
            return False
        if background:
            threading.Thread(target=self.refresh_cinemeta, daemon=True).start()
            return True
        try:
            items = [*cinemeta.catalog_items("movie", self.cinemeta.catalog("movie")),
                     *cinemeta.catalog_items("series", self.cinemeta.catalog("series"))]
        except cinemeta.CinemetaError as exc:
            log.warning("Populares de Stremio: %s", exc)
            return False
        with self._lock:
            self._items = {k: v for k, v in self._items.items() if v.source != "cinemeta"}
            self._items.update({i.id: i for i in items})
        self._cinemeta_items = items
        self._notify({"type": "library-changed"})
        return True

    def refresh_stremio_if_stale(self) -> None:
        if time.time() - self._stremio_fetched > STREMIO_STALE_SECONDS:
            self.refresh_stremio(background=True)

    def link_stremio(self, auth_key: str) -> int:
        """Guarda la clave de sesión y comprueba que funciona. Devuelve cuántos títulos hay."""
        raw = self.stremio_client.library(auth_key)  # lanza StremioError si la clave no sirve
        self.credentials.set(STREMIO_KEY, auth_key)
        self.refresh_stremio()
        return len(raw)

    def unlink_stremio(self) -> None:
        self.credentials.set(STREMIO_KEY, None)
        with self._lock:
            self._items = {k: v for k, v in self._items.items() if v.source != "stremio"}
        self._stremio_items = []

    def stremio_library(self) -> list[LibraryItem]:
        return [i for i in self.items() if i.source == "stremio"]

    # --- consulta ------------------------------------------------------------
    def items(self, include_hidden: bool = False) -> list[LibraryItem]:
        with self._lock:
            items = list(self._items.values())
        if include_hidden:
            return items
        return [i for i in items if not self.state.prefs(i.id).get("hidden")]

    def get(self, item_id: str) -> LibraryItem | None:
        with self._lock:
            return self._items.get(item_id)

    def is_favorite(self, item: LibraryItem) -> bool:
        # La preferencia de Orbital manda sobre el favorito de ES-DE.
        return self.state.prefs(item.id).get("favorite", item.favorite)

    def runner_for(self, item: LibraryItem, runner_id: str | None = None):
        return item.runner(runner_id or self.state.prefs(item.id).get("runner"))

    def describe(self, item: LibraryItem) -> dict:
        data = item.public()
        data["favorite"] = self.is_favorite(item)
        if item.runners:
            data["runner"] = self.runner_for(item).id
        history = self.state.history(item.id)
        # En Stremio manda su propia fecha (abrir la ficha no significa haberlo visto).
        data["last_played"] = item.last_watched if item.source == "stremio" else history.get("last_played")
        data["playtime"] = history.get("playtime", 0)
        return data

    def grouped(self) -> list[dict]:
        items = self.items()
        by_id = {i.id: i for i in items}
        alpha = sorted(items, key=lambda i: i.title.lower())
        rows = []
        for cat in CATEGORIES:
            if cat["id"] == "recent":
                # Juegos y apps; lo que se ve en Stremio va en "Seguir viendo".
                members = [by_id[i] for i in self.state.recent() if i in by_id and by_id[i].source != "stremio"]
            elif cat["id"] == "continue":
                members = sorted((i for i in items if i.category == "continue"),
                                 key=lambda i: i.last_watched or 0, reverse=True)
            elif cat["id"] == "favorites":
                members = [i for i in alpha if self.is_favorite(i)]
            elif cat["id"] == "emulators":
                # Una fila por sistema, en el orden de config.yaml.
                for emu in self.emulators:
                    games = [i for i in items if i.category == "emulators" and i.source == emu.id]
                    if games:
                        rows.append({"id": f"emulators:{emu.id}", "title": emu.name,
                                     "items": [self.describe(i) for i in games]})
                continue
            else:
                members = [i for i in items if i.category == cat["id"]]
            if members:
                rows.append({**cat, "items": [self.describe(i) for i in members]})
        return rows

    def grouped_items(self, row_id: str) -> list[LibraryItem]:
        """Elementos de una fila, en el mismo orden que la interfaz."""
        row = next((r for r in self.grouped() if r["id"] == row_id), None)
        return [self.get(i["id"]) for i in row["items"]] if row else []

    def hidden_count(self) -> int:
        return sum(1 for i in self.items(include_hidden=True) if self.state.prefs(i.id).get("hidden"))

    def find(self, query: str, category: str | None = None, *, source: str | None = None,
             exclude_source: str | None = None) -> LibraryItem | None:
        """Búsqueda difusa por título, pensada para lo que transcribe Alexa."""
        target = normalize(query)
        if not target:
            return None
        candidates = [i for i in self.items()
                      if (category is None or i.category == category)
                      and (source is None or i.source == source)
                      and (exclude_source is None or i.source != exclude_source)]
        by_name = {normalize(i.title): i for i in candidates}
        if target in by_name:
            return by_name[target]
        # "zelda" debe encontrar "The Legend of Zelda: Breath of the Wild".
        contains = [i for name, i in by_name.items() if target in name]
        if contains:
            return min(contains, key=lambda i: len(i.title))
        close = difflib.get_close_matches(target, list(by_name), n=1, cutoff=0.6)
        return by_name[close[0]] if close else None

    # --- preferencias --------------------------------------------------------
    def set_prefs(self, item_id: str, *, favorite: bool | None = None, hidden: bool | None = None,
                  runner: str | None = None, clear_runner: bool = False) -> dict:
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if favorite is not None:
            self.state.set_pref(item_id, "favorite", favorite)
        if hidden is not None:
            self.state.set_pref(item_id, "hidden", True if hidden else None)
        if runner is not None:
            if runner not in {r.id for r in item.runners}:
                raise ValueError(f"{item.title} no tiene el emulador {runner}")
            self.state.set_pref(item_id, "runner", None if runner == item.default_runner else runner)
        if clear_runner:
            self.state.set_pref(item_id, "runner", None)
        return self.describe(item)

    # --- acciones ------------------------------------------------------------
    def launch(self, item_id: str, runner_id: str | None = None) -> LibraryItem:
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if item.source in ("stremio", "cinemeta") or item.id == "media:stremio":
            self.open_stremio(item.uri if item.id != "media:stremio" else None, item.title)
            self.state.record_launch(item.id)
            return item
        runner = self.runner_for(item, runner_id)
        if runner:
            proc = self.launcher.run(runner.argv, cwd=runner.cwd)
            self.launcher.track(item.id, item.title, proc, runner=runner.name)
        elif item.argv:
            proc = self.launcher.run(item.argv, cwd=item.cwd)
            self.launcher.track(item.id, item.title, proc)
        elif item.uri:
            self.launcher.open_uri(item.uri)
            self.launcher.track(item.id, item.title, None, steam_appid=item.steam_appid)
        else:
            raise ValueError(f"{item.title} no tiene forma de lanzarse")
        self.state.record_launch(item.id)
        return item

    def open_stremio(self, uri: str | None, title: str) -> None:
        """Abre Stremio (opcionalmente en un enlace) y lo vigila por su ejecutable: si ya estaba
        abierto, el proceso que lanzamos le pasa el enlace y termina al instante."""
        argv = stremio.find_stremio(self.config.stremio)
        if argv:
            self.launcher.run([*argv, uri] if uri else argv)
            self.launcher.track_exe("media:stremio", title, Path(argv[0]).name, runner="Stremio")
        else:
            self.launcher.open_uri(uri or "stremio://")
            self.launcher.track("media:stremio", title, None)

    def play_stremio(self, kind: str, meta_id: str, video_id: str | None, title: str) -> str:
        """Reproduce directo (autoPlay) una película o un episodio elegido en Orbital."""
        uri = cinemeta.play_link(kind, meta_id, video_id)
        self.open_stremio(uri, title)
        return uri

    def search_media(self, query: str) -> str:
        uri = stremio.search_uri(query)
        self.open_stremio(uri, f"Stremio: {query}")
        return uri

    def _session_ended(self, item_id: str, title: str, seconds: float) -> None:
        """El juego o emulador se cerró: guarda el tiempo y vuelve a Orbital."""
        self.state.record_session(item_id, seconds)
        if self.kiosk is not None and not self.kiosk.exited_by_user:
            self.kiosk.open()  # al frente o, si alguien cerró la ventana, otra vez abierta
        else:
            system.bring_to_front()
        if item_id == "media:stremio":
            self.refresh_stremio(background=True)  # el progreso de "Seguir viendo" cambió
        self._notify({"type": "closed", "id": item_id, "title": title, "seconds": int(seconds)})

    def _notify(self, event: dict) -> None:
        for listener in list(self.listeners):
            listener(event)
