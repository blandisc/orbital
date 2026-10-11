"""Catálogo: la biblioteca de Orbital (juegos, apps, películas y series) y la puerta a todo lo demás.

Se divide en piezas que no se llaman entre sí, se comunican por eventos (events.EventBus):
  * Catalog (aquí): escanear fuentes, filas de la interfaz, preferencias y búsqueda por nombre.
  * Sessions (sessions.py): abrir algo, la pantalla de carga y saber cuándo termina.
  * Watch (watch.py): cuenta de Stremio, fuentes y el reproductor de Orbital.
  * focus.py: ventanas y foco (pantalla de carga encima del emulador).
Catalog expone también los métodos de Sessions y Watch que usan el servidor y la voz, para que
ellos solo conozcan una cosa.
"""

from __future__ import annotations

import difflib
import logging
import threading
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote

from . import player
from .config import Config
from .credentials import Credentials
from .events import EventBus
from .focus import (READY_TIMEOUT, bring_app_to_front, bring_game_to_front, game_ready,  # noqa: F401 - compatibilidad
                    is_orbital_window, pin_orbital)
from .launcher import Launcher
from .library import cinemeta, detect, emulators, esde, geforcenow, steam, stremio, stremio_api
from .library.models import LibraryItem
from .sessions import QUICK_EXIT, Sessions  # noqa: F401
from .state import State
from .store import ItemStore
from .text import normalize
from .watch import (STREMIO_KEY, STREMIO_STALE_SECONDS, Watch, enrich_watch_item, source_label,  # noqa: F401
                    stremio_item, time_left, trailer_id)

CONTINUE_LIMIT = 20  # "Seguir viendo": los más recientes
JUMP_LIMIT = 16  # "Continuar" en Inicio
STEAM_STATS_DELAY = 6  # s tras cerrar un juego de Steam, antes de releer sus horas

log = logging.getLogger(__name__)

CATEGORIES = [
    # Inicio: lo último que jugaste o viste, mezclado (como "Jump back in" de Xbox); lo abierto, primero.
    {"id": "jump", "title": "Continuar"},
    {"id": "recent", "title": "Jugado recientemente"},
    {"id": "continue", "title": "Seguir viendo"},
    {"id": "mylist", "title": "Mi lista"},
    {"id": "favorites", "title": "Favoritos"},
    {"id": "steam", "title": "Steam"},
    {"id": "geforcenow", "title": "GeForce NOW"},
    {"id": "emulators", "title": "Emuladores"},
    {"id": "media", "title": "Multimedia"},
    {"id": "movies", "title": "Películas populares"},
    {"id": "series", "title": "Series populares"},
    {"id": "apps", "title": "Apps"},
]

# listener(evento) — el servidor lo usa para avisar a la interfaz.
Listener = Callable[[dict], None]

# Lo que el servidor y la voz piden al catálogo y en realidad hace otra pieza.
_SESSIONS_API = ("launch", "reveal_now", "open_stremio", "play_stremio", "search_media")
_WATCH_API = (
    "refresh_stremio", "dismiss_continue", "refresh_cinemeta", "refresh_stremio_if_stale", "link_stremio",
    "unlink_stremio", "setting", "stream_sources", "best_source", "play_best", "play_source", "resume_position",
    "play_native", "play_title", "play_next_episode", "player_subtitles", "title_details", "set_in_library",
    "play_trailer", "_player_finished", "_save_progress", "_play_episode",
)


def default_state(config: Config) -> State:
    if config.source is None:
        return State(None)
    return State(config.source.parent / "state.json")


def default_credentials(config: Config) -> Credentials:
    return Credentials(config.source.parent / "secrets.json" if config.source else None)


class Catalog:
    def __init__(self, config: Config, launcher: Launcher | None = None, state: State | None = None,
                 credentials: Credentials | None = None, stremio_client: stremio_api.StremioAPI | None = None,
                 cinemeta_client: cinemeta.Cinemeta | None = None) -> None:
        self.config = config
        self.launcher = launcher or Launcher()
        self.state = state or default_state(config)
        self.credentials = credentials or default_credentials(config)
        self.events = EventBus()
        self.store = ItemStore()
        self.steam_root: Path | None = None
        self.esde: esde.EsdeLibrary | None = None
        # Emuladores en uso: los de config.yaml + los detectados automáticamente.
        self.emulators = list(config.emulators)
        self.detected: dict[str, Path] = {}
        self._steam_art = geforcenow.SteamArt()
        self.scanning = False  # primer escaneo en curso (la interfaz sigue en su pantalla de arranque)
        self._refreshing = threading.Lock()  # un escaneo a la vez (arranque + botón "Actualizar")
        self.sessions = Sessions(config, self.state, self.launcher, self.store, self.events,
                                 runner_for=self.runner_for, last_end=lambda: self.watch.player.last_end)
        self.watch = Watch(config, self.state, self.credentials, stremio_client or stremio_api.StremioAPI(),
                           cinemeta_client or cinemeta.Cinemeta(), self.store, self.events, self.sessions,
                           self.launcher)
        self.events.subscribe(self._on_event)

    # --- piezas y compatibilidad ----------------------------------------------------------------
    def __getattr__(self, name: str):
        # Solo se llama si el atributo no existe aquí: delega lo que hacen Sessions y Watch.
        if name in _SESSIONS_API:
            return getattr(self.sessions, name)
        if name in _WATCH_API:
            return getattr(self.watch, name)
        raise AttributeError(name)

    @property
    def listeners(self) -> list[Listener]:
        return self.events.listeners

    def notify(self, event: dict) -> None:
        self.events.publish(event)

    @property
    def player(self):
        return self.watch.player

    @player.setter
    def player(self, value) -> None:
        self.watch.player = value

    kiosk = property(lambda self: self.sessions.kiosk, lambda self, v: setattr(self.sessions, "kiosk", v))
    before_launch = property(lambda self: self.sessions.before_launch,
                             lambda self, v: setattr(self.sessions, "before_launch", v))
    revealing = property(lambda self: self.sessions.revealing,
                         lambda self, v: setattr(self.sessions, "revealing", v))
    streams = property(lambda self: self.watch.streams)
    cinemeta = property(lambda self: self.watch.cinemeta)
    stremio_client = property(lambda self: self.watch.stremio_client)
    stremio_error = property(lambda self: self.watch.stremio_error)
    stremio_linked = property(lambda self: self.watch.stremio_linked)
    stream_prefs = property(lambda self: self.watch.stream_prefs)
    subtitles_lang = property(lambda self: self.watch.subtitles_lang)
    native_player = property(lambda self: self.watch.native_player)

    def _on_event(self, event: dict) -> None:
        """Al cerrarse algo: Stremio refresca Seguir viendo; Steam relee sus horas (las guarda unos
        segundos después de cerrar el juego)."""
        if event.get("type") != "closed":
            return
        if event.get("id") == "media:stremio":
            self.watch.refresh_stremio(background=True)
        elif str(event.get("id", "")).startswith("steam:"):
            threading.Timer(STEAM_STATS_DELAY, self.refresh_steam_stats).start()

    # --- escaneo -------------------------------------------------------------
    def refresh(self) -> int:
        """Vuelve a buscar todo. Si ya hay un escaneo en curso, espera a que termine y usa ese."""
        if not self._refreshing.acquire(blocking=False):
            with self._refreshing:
                return len(self.store.all())
        try:
            return self._refresh()
        finally:
            self._refreshing.release()

    def _refresh(self) -> int:
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
            try:
                found += emulators.scan(emu, self.esde, alternatives)
            except Exception:  # noqa: BLE001 - un emulador con problemas no debe dejar a Orbital sin arrancar
                log.exception("No pude leer los juegos de %s", emu.name)
        if self.config.stremio.enabled:
            found += stremio.items(self.config.stremio)
        gfn_app = geforcenow.app_item()
        if gfn_app:
            found.append(gfn_app)
            found += geforcenow.items(self._steam_art)
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
        found += self.watch.stremio_items
        found += self.watch.cinemeta_items
        for item in found:
            url = f"/api/art/{quote(item.id, safe=':')}"
            if item.art_path:
                item.image = url
            if item.hero_path:
                item.hero = url + "?kind=hero"
        self.store.replace(found)
        log.info("Catálogo: %d elementos", len(found))
        self.watch.refresh_stremio(background=True)
        if not self.watch.cinemeta_items:
            self.watch.refresh_cinemeta(background=True)
        return len(found)

    def stremio_library(self) -> list[LibraryItem]:
        return [i for i in self.items() if i.source == "stremio"]

    # --- consulta ------------------------------------------------------------
    def items(self, include_hidden: bool = False) -> list[LibraryItem]:
        items = self.store.all()
        if include_hidden:
            return items
        return [i for i in items if not self.state.prefs(i.id).get("hidden")]

    def get(self, item_id: str) -> LibraryItem | None:
        return self.store.get(item_id)

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
        data["last_played"] = item.last_watched if item.source == "stremio" else self.last_played(item)
        # Steam lleva sus propias horas (también lo jugado fuera de Orbital): la mayor de las dos.
        data["playtime"] = max(history.get("playtime", 0), item.extra.get("steam_playtime", 0))
        return data

    def last_played(self, item: LibraryItem) -> float | None:
        """La última vez que se jugó: lo que registró Orbital o, en Steam, lo que registró Steam."""
        last = max(self.state.history(item.id).get("last_played") or 0, item.extra.get("steam_last_played") or 0)
        return last or None

    def grouped(self) -> list[dict]:
        items = self.items()
        by_id = {i.id: i for i in items}
        alpha = sorted(items, key=lambda i: i.title.lower())
        rows = []
        running = self.launcher.status()
        running_id = running["id"] if running else None
        for cat in CATEGORIES:
            if cat["id"] == "jump":
                games = [(self.last_played(i) or 0, i) for i in items if i.source not in ("stremio", "cinemeta")]
                videos = [(i.last_watched or 0, i) for i in items if i.category == "continue"]
                recent = sorted((p for p in games + videos if p[0]), key=lambda p: p[0], reverse=True)
                members = [i for _, i in recent][:JUMP_LIMIT]
                if running_id and running_id in by_id:  # lo abierto va primero (Home o A para volver)
                    members = [by_id[running_id], *[i for i in members if i.id != running_id]][:JUMP_LIMIT]
                if members:
                    rows.append({**cat, "items": [{**self.describe(i), **({"live": True} if i.id == running_id else {})}
                                                  for i in members]})
                continue
            if cat["id"] == "recent":
                # Juegos y apps (también lo jugado en Steam fuera de Orbital); lo que se ve va en
                # "Seguir viendo".
                played = sorted(((self.last_played(i) or 0, i.id, i) for i in items
                                 if i.source not in ("stremio", "cinemeta")), reverse=True)
                members = [i for last, _, i in played if last][:15]
            elif cat["id"] == "continue":
                # Stremio guarda todo lo que alguna vez empezaste (años): lo reciente, no 134 títulos.
                members = sorted((i for i in items if i.category == "continue"),
                                 key=lambda i: i.last_watched or 0, reverse=True)[:CONTINUE_LIMIT]
            elif cat["id"] == "mylist":  # tu biblioteca de Stremio, lo último primero
                members = sorted((i for i in items if i.source == "stremio" and i.extra.get("in_library")),
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
             exclude_source: str | tuple[str, ...] | None = None) -> LibraryItem | None:
        """Búsqueda difusa por título, pensada para lo que transcribe Alexa."""
        target = normalize(query)
        if not target:
            return None
        candidates = [i for i in self.items()
                      if (category is None or i.category == category)
                      and (source is None or i.source == source)
                      and (exclude_source is None or i.source not in
                           ((exclude_source,) if isinstance(exclude_source, str) else exclude_source))]
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

    def refresh_steam_stats(self) -> None:
        """Relee las horas y la última vez de Steam (barato: no reescanea la biblioteca)."""
        if self.steam_root is None:
            return
        stats = steam.user_stats(self.steam_root)

        def apply(item: LibraryItem) -> None:
            got = stats.get(str(item.steam_appid), {})
            item.extra["steam_last_played"] = got.get("last_played", 0)
            item.extra["steam_playtime"] = got.get("playtime", 0)
        self.store.update(apply, where=lambda i: i.source == "steam" and i.steam_appid is not None)
        self.notify({"type": "library-changed"})

    def setup_status(self) -> dict:
        """Qué encontró Orbital (para "Tu consola", la pantalla de primer uso)."""
        items = self.items()
        games = [i for i in items if i.source not in ("stremio", "cinemeta", "search") and i.category not in ("apps", "media")]
        systems: dict[str, int] = {}
        for i in items:
            if i.category == "emulators":
                emu = next((e for e in self.emulators if e.id == i.source), None)
                systems[emu.name if emu else i.source] = systems.get(emu.name if emu else i.source, 0) + 1
        return {
            "games": len(games),
            "steam": sum(1 for i in items if i.source == "steam") if self.steam_root else None,
            "emulators": systems,
            "esde": self.esde is not None,
            "stremio": self.stremio_linked,
            "player": player.find_mpv() is not None,
            "alexa": bool(self.config.server.token) and not self.config.server.token_is_ephemeral,
        }
