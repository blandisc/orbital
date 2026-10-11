"""Catálogo unificado: junta todas las fuentes, aplica las preferencias y lanza cualquier elemento."""

from __future__ import annotations

import difflib
import logging
import sys
import threading
import time
import unicodedata
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

from . import player, system
from .config import Config
from .launcher import Launcher
from .credentials import Credentials
from .library import cinemeta, detect, emulators, esde, geforcenow, steam, stremio, stremio_api, streams
from .library.models import LibraryItem
from .state import State

STREMIO_KEY = "stremio_auth_key"
STREMIO_STALE_SECONDS = 180
CONTINUE_LIMIT = 20  # "Seguir viendo": los más recientes
JUMP_LIMIT = 16  # "Continuar" en Inicio
STEAM_STATS_DELAY = 6  # s tras cerrar un juego de Steam, antes de releer sus horas
QUICK_EXIT = 15  # s: un juego que se cierra antes, solo, seguramente no pudo abrir

log = logging.getLogger(__name__)

CATEGORIES = [
    # Inicio: lo último que jugaste o viste, mezclado (como "Jump back in" de Xbox); lo abierto, primero.
    {"id": "jump", "title": "Continuar"},
    {"id": "recent", "title": "Jugado recientemente"},
    {"id": "continue", "title": "Seguir viendo"},
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


def source_label(source: streams.Source, long: bool = False) -> str:
    """"1080p · Al instante" / "4K HDR · Torrentio": de dónde viene lo que ves, en pocas palabras."""
    quality = " ".join(p for p in (source.resolution or "SD", *source.hdr[:1]) if p)
    parts = [quality, "Al instante" if source.cached else source.addon]
    if long:
        parts.append(" + ".join(streams.LANG_NAMES.get(l, l) for l in source.languages[:2]))
        if source.size:
            parts.append(f"{source.size / 1e9:.1f} GB")
    return " · ".join(p for p in parts if p)


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


def bring_app_to_front(exe: str, timeout: float = 10.0, fullscreen: bool = False) -> bool:
    """Espera la ventana de `exe` y la trae al frente (Windows). Con `fullscreen`, además la pone
    en pantalla completa (F11) si aún no lo está: F11 alterna, por eso primero se mide."""
    if sys.platform != "win32":
        return False
    from . import windows

    deadline = time.time() + timeout
    time.sleep(.8)  # que alcance a navegar al enlace antes de mostrarse
    while time.time() < deadline:
        hwnd = windows.main_window(windows.pids_by_exe(exe))
        if hwnd and windows.focus(hwnd):
            if fullscreen:
                time.sleep(1.5)  # que el reproductor termine de abrir
                if windows.foreground() == hwnd and not windows.is_fullscreen(hwnd):
                    from .gamepad import VK_F11, send_key
                    send_key(VK_F11)
            return True
        time.sleep(.4)
    return False


ORBITAL_BROWSERS = {"msedge.exe", "chrome.exe", "chromium.exe"}


READY_TIMEOUT = 25.0  # s máximos con la pantalla de carga de Orbital encima
READY_SETTLE = .6  # s tras detectar el juego: que pinte sus primeros cuadros
FADE_TO_BLACK = .75  # s de la salida de la pantalla de carga (el "salto" al juego) antes del fundido


def _words(text: str) -> set[str]:
    return {w for w in normalize(text).split() if len(w) >= 3}


def game_ready(windows: list[tuple[str, bool]], title: str, runner: str | None = None) -> bool:
    """¿Ya está el juego (no la lista del emulador ni su ventana de carga)? Lo está si alguna ventana
    ocupa toda la pantalla o su título nombra al juego ("Eden | Mario Party Superstars")."""
    wanted = _words(title) - _words(runner or "")
    for win_title, fullscreen in windows:
        if fullscreen:
            return True
        found = _words(win_title)
        if wanted and len(wanted & found) >= max(1, round(len(wanted) * .6)):
            return True
    return False


def is_orbital_window(win, hwnd: int) -> bool:
    return bool(hwnd) and "Orbital" in win.title(hwnd) and win.exe_name(win.pid_of(hwnd)) in ORBITAL_BROWSERS


def pin_orbital(win=None) -> int:
    """Orbital "siempre encima" ANTES de lanzar el emulador (antes se fijaba un instante después y
    la ventana del emulador alcanzaba a asomarse). Solo si Orbital está al frente. Devuelve su ventana."""
    if win is None:
        if sys.platform != "win32":
            return 0
        from . import windows as win
    fg = win.foreground()
    return fg if is_orbital_window(win, fg) and win.set_topmost(fg, True) else 0


FULLSCREEN_GRACE = 4.0  # s: el juego ya cargó (su nombre en la ventana) pero aún no ocupa la pantalla
REVEAL_FADE = (210, 160, 110, 60, 20, 0)  # opacidad de Orbital al fundirse sobre el juego


def bring_game_to_front(launcher: Launcher, item_id: str, title: str = "", runner: str | None = None,
                        notify=None, skip: threading.Event | None = None, timeout: float = READY_TIMEOUT,
                        win=None, sleep=time.sleep, pinned: int | None = None, ready_check=None) -> bool:
    """Pantalla de carga hasta que el juego esté listo, y luego un fundido de Orbital al juego.

    Mientras el emulador abre se ven sus ventanas feas (la lista de juegos de Eden, una consola…).
    Si Orbital está al frente, se queda ENCIMA (topmost) con su pantalla de carga hasta que el juego
    está listo Y en pantalla completa (si no, se veía el emulador brincar de ventana a pantalla
    completa). Entonces la pantalla de carga hace su salida (evento launch-ready), el juego pasa al
    frente DEBAJO de Orbital y Orbital se funde hasta desaparecer: del cohete al juego, sin cortes.
    Si ya estás en otra cosa, no se pelea por el foco. `skip`: B en la pantalla de carga.
    `pinned`: la ventana de Orbital ya fijada encima antes de lanzar (pin_orbital).
    `ready_check()`: otra señal de "listo" (el reproductor: hasta la primera imagen, no una ventana negra)."""
    if win is None:
        if sys.platform != "win32":
            return False
        from . import windows as win
    notify = notify or (lambda event: None)
    orbital = pin_orbital(win) if pinned is None else pinned
    target = 0
    started = time.time()
    grace = int(FULLSCREEN_GRACE / .3)
    try:
        deadline = time.time() + timeout
        while time.time() < deadline and not (skip and skip.is_set()):
            status = launcher.status()
            if not status or status.get("id") != item_id:
                return False  # se cerró (o truena) o se abrió otra cosa: Orbital se queda
            pids = win.process_tree(status["pid"]) if status.get("pid") else set()
            hwnds = win.windows_of(pids) if pids else []
            if ready_check is not None:
                if hwnds and ready_check():
                    target = hwnds[0]
                    log.info("%s listo tras %.1f s", title, time.time() - started)
                    break
                sleep(.3)
                continue
            if hwnds:
                target = hwnds[0]
                info = [(win.title(h), win.is_fullscreen(h)) for h in hwnds]
                ready = next((h for h, i in zip(hwnds, info) if game_ready([i], title, runner)), 0)
                if ready and orbital and not win.is_fullscreen(ready) and grace > 0:
                    grace -= 1  # cargó, pero quizá está por pasar a pantalla completa: un momento
                    target = ready
                    sleep(.3)
                    continue
                if ready or not orbital:
                    target = ready or target
                    if ready:
                        log.info("%s listo tras %.1f s: %s", title, time.time() - started, win.title(ready))
                    break
            sleep(.3)
        if orbital and not (skip and skip.is_set()) and time.time() >= deadline:
            log.info("%s sin señal de listo en %.0f s: se muestra igual", title, timeout)
        if not target:
            status = launcher.status()
            pids = win.process_tree(status["pid"]) if status and status.get("pid") else set()
            target = win.main_window(pids) if pids else 0
        if orbital:
            settle(win, target, sleep)
            notify({"type": "launch-ready", "id": item_id})  # la pantalla de carga hace su salida
            sleep(FADE_TO_BLACK)
            if target and win.foreground() != target:
                win.focus(target)  # el juego al frente, aún debajo de Orbital (que sigue encima)
            fade = getattr(win, "set_alpha", None)
            if fade and target:
                for alpha in REVEAL_FADE:  # Orbital se funde y aparece el juego
                    fade(orbital, alpha)
                    sleep(.04)
    finally:
        if orbital:
            win.set_topmost(orbital, False)
            fade = getattr(win, "set_alpha", None)
            if fade:
                fade(orbital, None)  # vuelve a ser opaca (ya detrás del juego)
    if not target:
        return False
    fg = win.foreground()
    if fg == target:
        return True
    return is_orbital_window(win, fg) and win.focus(target)


def settle(win, hwnd: int, sleep, tries: int = 8) -> None:
    """Espera a que la ventana del juego deje de cambiar de tamaño (dos lecturas iguales seguidas)."""
    rect_of = getattr(win, "window_rect", None)
    if not rect_of or not hwnd:
        sleep(READY_SETTLE)
        return
    last = rect_of(hwnd)
    for _ in range(tries):
        sleep(READY_SETTLE / 3)
        now = rect_of(hwnd)
        if now == last:
            return
        last = now


def time_left(seconds: float) -> str:
    """"quedan 11 min" / "quedan 1 h 40 min" (vacío si falta menos de un minuto)."""
    minutes = int(seconds // 60)
    if minutes < 1:
        return ""
    hours, minutes = divmod(minutes, 60)
    return f"quedan {hours} h {minutes} min" if hours and minutes else f"quedan {hours} h" if hours else f"quedan {minutes} min"


CONTINUE_MIN_PROGRESS = .01  # menos del 1 % (lo abriste un momento): no ensucia Seguir viendo


def stremio_item(w: stremio_api.Watchable) -> LibraryItem:
    season, episode = w.episode
    if episode is not None:
        detail = f"T{season} E{episode}" if season is not None else f"Episodio {episode}"
    else:
        detail = "Película" if w.type == "movie" else "Serie" if w.type == "series" else ""
    left = (w.duration - w.time_offset) / 1000 if w.duration and w.time_offset > 0 else 0
    # Terminaste un episodio y Stremio ya apunta al siguiente (sin avance): "Sigue: T8 E24".
    next_up = w.type == "series" and w.time_offset <= 1 and not w.duration and episode is not None
    subtitle = f"Sigue: {detail}" if next_up else " · ".join(filter(None, [detail, time_left(left)]))
    barely = w.progress is not None and w.progress < CONTINUE_MIN_PROGRESS and not next_up
    return LibraryItem(
        id=f"stremio:{w.id}",
        title=w.name,
        # Solo "Seguir viendo" tiene fila; el resto de la biblioteca sirve para la voz.
        category="continue" if w.in_continue and not barely else "stremio",
        source="stremio",
        subtitle=subtitle,
        image=w.poster,
        hero=w.background,
        uri=w.deep_link,
        progress=w.progress,
        last_watched=w.last_watched,
        # Para elegir la fuente en Orbital (Seguir viendo -> el mismo episodio).
        extra={"kind": w.type, "meta_id": w.id, "video_id": w.video_id or (w.id if w.type == "movie" else None),
               "eyebrow": " · ".join(filter(None, ["Película" if w.type == "movie" else "Serie", detail if episode else ""]))},
    )


def enrich_watch_item(item: LibraryItem, info: dict) -> None:
    """Seguir viendo con lo mismo que el catálogo: sinopsis, calificación, géneros, logo y el
    nombre del episodio ("Serie · T8 E23 · Homer's Enemy")."""
    item.extra.update({k: v for k, v in cinemeta.describe_meta(info).items() if v})
    video_id = item.extra.get("video_id")
    if item.extra.get("kind") == "series" and video_id:
        for season in cinemeta.seasons(info):
            for ep in season["episodes"]:
                if ep["id"] == video_id:
                    item.extra["episode_title"] = ep["title"]
                    item.extra["eyebrow"] = f"Serie · T{season['season']} E{ep['episode']} · {ep['title']}"
    if not item.hero and info.get("background"):
        item.hero = info["background"]


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
        self._steam_art = geforcenow.SteamArt()
        self.streams = streams.StreamFinder(self.stremio_client)
        self.player = player.OrbitalPlayer(
            on_finished=self._player_finished, idle_seconds=config.sessions.video_idle_minutes * 60,
            on_idle=lambda title, minutes: self._notify({
                "type": "toast", "message": f"Cerré {title}: llevaba {minutes} min en pausa. Sigues donde te quedaste."}))
        self._wire_player()
        # Antes de abrir algo, cerrar lo que estaba abierto (lo pone el servidor: shell.close_previous).
        self.before_launch: Callable[[str], None] | None = None
        self._reveal_skip = threading.Event()
        self.revealing = False  # el último lanzamiento tiene pantalla de carga hasta launch-ready
        self.scanning = False  # primer escaneo en curso (la interfaz sigue en su pantalla de arranque)
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
            self._enrich_continue(items)
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

    def _enrich_continue(self, items: list[LibraryItem]) -> None:
        """Datos de Cinemeta para Seguir viendo (en paralelo y con caché: la segunda vez es al instante)."""
        wanted = [i for i in items if i.category == "continue" and i.extra.get("kind") in ("movie", "series")]

        def meta(item: LibraryItem):
            try:
                return item, self.cinemeta.meta(item.extra["kind"], item.extra["meta_id"])
            except cinemeta.CinemetaError:
                return item, None

        with ThreadPoolExecutor(max_workers=6) as pool:
            for item, info in pool.map(meta, wanted):
                if info:
                    enrich_watch_item(item, info)

    def dismiss_continue(self, meta_id: str) -> None:
        """"Quitar de Seguir viendo": en tu cuenta de Stremio (desaparece también en Stremio)."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth:
            raise stremio_api.StremioError("Conecta tu cuenta de Stremio en Ajustes")
        raw = self.stremio_client.library_item(auth, meta_id)
        if raw:
            self.stremio_client.save_library_item(auth, stremio_api.dismissed(raw, time.time()))
        self.refresh_stremio()
        self._notify({"type": "library-changed"})

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

    # --- acciones ------------------------------------------------------------
    def launch(self, item_id: str, runner_id: str | None = None, keep: bool = False) -> LibraryItem:
        """`keep`: abrir sin cerrar lo que estaba abierto (lo pediste en "¿Cerrar…?")."""
        self.revealing = False
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if self.before_launch and not keep:
            self.before_launch(item.id)
        if item.source in ("stremio", "cinemeta") or item.id == "media:stremio":
            self.open_stremio(item.uri if item.id != "media:stremio" else None, item.title)
            self.state.record_launch(item.id)
            return item
        if item.source == "geforcenow":
            # La app (y su reproductor en la nube) es de instancia única: se vigila por ejecutable.
            exe = geforcenow.APP_EXE if item.id == "app:geforcenow" else geforcenow.STREAMER_EXE
            self.launcher.run(item.argv, cwd=item.cwd)
            self.launcher.track_exe(item.id, item.title, exe, runner="GeForce NOW")
            threading.Thread(target=bring_app_to_front, args=(exe,), daemon=True).start()
            self.state.record_launch(item.id)
            return item
        runner = self.runner_for(item, runner_id)
        if runner or item.argv:
            # Orbital encima ANTES de lanzar: la ventana del emulador nunca se asoma.
            pinned = self._pin()
            try:
                proc = self.launcher.run(runner.argv if runner else item.argv, cwd=runner.cwd if runner else item.cwd)
            except BaseException:
                self._unpin(pinned)
                raise
            self.launcher.track(item.id, item.title, proc, runner=runner.name if runner else None)
            self.revealing = self._to_front(item.id, item.title, runner.name if runner else None, pinned=pinned)
        elif item.uri:
            self.launcher.open_uri(item.uri)
            self.launcher.track(item.id, item.title, None, steam_appid=item.steam_appid)
        else:
            raise ValueError(f"{item.title} no tiene forma de lanzarse")
        self.state.record_launch(item.id)
        return item

    @staticmethod
    def _pin() -> int | None:
        """Fija Orbital encima (si está al frente) antes de lanzar algo. None fuera de Windows."""
        return pin_orbital() if sys.platform == "win32" else None

    @staticmethod
    def _unpin(pinned: int | None) -> None:
        if pinned and sys.platform == "win32":
            from . import windows
            windows.set_topmost(pinned, False)

    def _to_front(self, item_id: str, title: str = "", runner: str | None = None, pinned: int | None = None,
                  ready=None, timeout: float = READY_TIMEOUT) -> bool:
        """Pantalla de carga hasta que el juego esté listo (ver bring_game_to_front). Devuelve si la
        interfaz debe esperar el evento launch-ready en lugar de esconder "Abriendo" sola."""
        if sys.platform != "win32":
            return False
        self._reveal_skip = threading.Event()
        threading.Thread(target=bring_game_to_front, args=(self.launcher, item_id, title, runner),
                         kwargs={"notify": self._notify, "skip": self._reveal_skip, "pinned": pinned,
                                 "ready_check": ready, "timeout": timeout}, daemon=True,
                         name="to-front").start()
        return True

    def reveal_now(self) -> None:
        """B en la pantalla de carga: deja de esperar y muestra lo que haya."""
        self._reveal_skip.set()

    def open_stremio(self, uri: str | None, title: str) -> None:
        """Abre Stremio (opcionalmente en un enlace) y lo vigila por su ejecutable: si ya estaba
        abierto, el proceso que lanzamos le pasa el enlace y termina al instante."""
        argv = stremio.find_stremio(self.config.stremio)
        if argv:
            self.launcher.run([*argv, uri] if uri else argv)
            self.launcher.track_exe("media:stremio", title, Path(argv[0]).name, runner="Stremio")
            # Si Stremio ya estaba abierto, recibe el enlace en su ventana de siempre... detrás de
            # Orbital: sin esto, "no pasa nada". La traemos al frente cuando exista.
            in_player = bool(uri and uri.startswith("stremio:///player/"))
            threading.Thread(target=bring_app_to_front, args=(Path(argv[0]).name,),
                             kwargs={"fullscreen": in_player}, daemon=True).start()
        else:
            self.launcher.open_uri(uri or "stremio://")
            self.launcher.track("media:stremio", title, None)

    def play_stremio(self, kind: str, meta_id: str, video_id: str | None, title: str) -> str:
        """Reproduce directo (autoPlay) una película o un episodio elegido en Orbital."""
        uri = cinemeta.play_link(kind, meta_id, video_id)
        self.open_stremio(uri, title)
        return uri

    # --- películas y series en el reproductor de Orbital -----------------------------------------
    def setting(self, key: str, default=None):
        """Lo que elegiste en Ajustes manda; si no, config.yaml."""
        return self.state.settings().get(key, default)

    @property
    def stream_prefs(self) -> streams.Preferences:
        return streams.Preferences(audio=self.setting("audio", self.config.stremio.audio),
                                   quality=self.setting("quality", self.config.stremio.quality))

    @property
    def subtitles_lang(self) -> str:
        return self.setting("subtitles", self.config.stremio.subtitles)

    def stream_sources(self, kind: str, video_id: str, prefs: streams.Preferences | None = None) -> list[streams.Source]:
        """Fuentes de tus addons, ordenadas por tus preferencias (la primera es la recomendada)."""
        if not self.stremio_linked:
            raise stremio_api.StremioError("Conecta tu cuenta de Stremio en Ajustes")
        return self.streams.find(self.credentials.get(STREMIO_KEY), kind, video_id, prefs or self.stream_prefs)

    def _wire_player(self) -> None:
        """Lo que el reproductor le pregunta al catálogo (siguiente episodio, otras fuentes…)."""
        p = self.player
        p.on_progress = lambda meta, pos, dur, watched: self._save_progress(meta, pos, dur, watched, refresh=False)
        p.on_failed = self._source_failed
        p.next_provider = self._next_up
        p.sources_provider = self._player_sources
        p.on_switch_source = self._switch_source
        p.on_episode = self._step_episode
        p.on_sub_scale = lambda scale: self.state.set_setting("sub_scale", scale)
        p.sub_scale = float(self.setting("sub_scale", 1.0) or 1.0)

    @staticmethod
    def _episode_label(info: dict, video_id: str) -> tuple[str, str]:
        """("T3 E6", "Nombre del episodio") de un video de una serie ("", "") si no se encuentra."""
        for season in cinemeta.seasons(info):
            for episode in season["episodes"]:
                if episode["id"] == video_id:
                    prefix = "Especial" if season["season"] == 0 else f"T{season['season']}"
                    return f"{prefix} E{episode['episode']}", episode["title"]
        return "", ""

    def _media_meta(self, kind: str, meta_id: str, video_id: str, title: str, source: streams.Source) -> dict:
        """Lo que el reproductor necesita saber del video (y lo que se guarda en Stremio)."""
        detail = ""
        if kind == "series":
            try:
                label, name = self._episode_label(self.cinemeta.meta(kind, meta_id), video_id)
                detail = " · ".join(p for p in (label, name) if p)
            except cinemeta.CinemetaError:
                pass
        return {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title, "detail": detail,
                "source": source.index, "source_label": source_label(source), "binge": source.binge,
                "tried": [source.index]}

    def best_source(self, kind: str, video_id: str, binge: str | None = None,
                    skip: set[int] | None = None, prefs: streams.Preferences | None = None) -> streams.Source | None:
        """La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior
        (misma calidad e idioma: así lo hace Stremio con bingeGroup)."""
        found = [s for s in self.stream_sources(kind, video_id, prefs) if s.index not in (skip or set())]
        if not found:
            return None
        if binge:
            same = next((s for s in found if s.binge == binge and s.score > found[0].score - 700), None)
            if same:
                return same
        return found[0]

    def play_best(self, kind: str, meta_id: str, video_id: str, title: str, keep: bool = False,
                  from_start: bool = False) -> dict:
        """"Ver": sin lista de fuentes. Orbital elige la recomendada y arranca (la lista queda en Y)."""
        source = self.best_source(kind, video_id)
        if source is None:
            raise LookupError("No encontré dónde ver esto. Revisa tus complementos de Stremio.")
        self.play_source(kind, meta_id, video_id, source.index, title, keep=keep, from_start=from_start)
        return {"source": source.public(), "label": source_label(source)}

    def play_source(self, kind: str, meta_id: str, video_id: str, index: int, title: str, keep: bool = False,
                    from_start: bool = False, prefs: streams.Preferences | None = None,
                    subtitles: str | None = None) -> str:
        """Reproduce la fuente elegida: en el reproductor de Orbital (mpv, con el mando) o, si no
        está o así se configuró, directo en el de Stremio (sin su lista de fuentes).
        `prefs`/`subtitles`: idioma pedido para esta vez ("…en español"); si no, el de Ajustes."""
        self.revealing = False
        prefs = prefs or self.stream_prefs
        source = self.streams.get(kind, video_id, prefs, index)
        if source is None:
            raise ValueError("Esa fuente ya no está disponible; vuelve a cargar las fuentes")
        mpv_exe = player.find_mpv() if self.config.stremio.player == "orbital" else None
        url = player.stream_url(source.stream)
        if mpv_exe and url:
            self.play_native(mpv_exe, url, kind, meta_id, video_id, title, keep=keep, source=source,
                             from_start=from_start, audio=prefs.audio, subtitles=subtitles)
            return "orbital"
        uri = streams.player_link(source, cinemeta.MANIFEST, kind, meta_id, video_id)
        self.open_stremio(uri, title)
        return uri

    def resume_position(self, meta_id: str, video_id: str) -> float:
        """Dónde ibas según Stremio (0 si no se sabe)."""
        try:
            return stremio_api.resume_seconds(
                self.stremio_client.library_item(self.credentials.get(STREMIO_KEY), meta_id), video_id)
        except stremio_api.StremioError as exc:
            log.info("No pude leer dónde ibas: %s", exc)
            return 0.0

    def _fallback_subs(self, kind: str, video_id: str, subs: str | None = None):
        subs = self.subtitles_lang if subs is None else subs
        if subs == "forced":
            return None  # solo los forzados que trae el video: no se buscan subtítulos completos
        auth = self.credentials.get(STREMIO_KEY)
        return (lambda: self.streams.subtitles(auth, kind, video_id, subs)) if subs else None

    def play_native(self, mpv_exe: str, url: str, kind: str, meta_id: str, video_id: str, title: str,
                    keep: bool = False, source: streams.Source | None = None, from_start: bool = False,
                    audio: str | None = None, subtitles: str | None = None) -> None:
        """mpv a pantalla completa, desde donde te quedaste (según Stremio)."""
        start = 0.0 if from_start else self.resume_position(meta_id, video_id)
        if self.before_launch and not keep:
            self.before_launch("media:player")
        meta = self._media_meta(kind, meta_id, video_id, title, source) if source else \
            {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title}
        self._wire_player()
        pinned = self._pin()
        process = self.player.play(
            self.launcher.run, mpv_exe, url, title, meta,
            start=start, audio=audio or self.stream_prefs.audio,
            subtitles=self.subtitles_lang if subtitles is None else subtitles,
            fallback_subs=self._fallback_subs(kind, video_id, subtitles))
        self.launcher.track("media:player", title, process, runner="Reproductor")
        # Hasta la primera imagen del video (cargar un stream tarda): antes se veía la ventana negra de mpv.
        self.revealing = self._to_front("media:player", title, pinned=pinned, timeout=player.STARTUP_TIMEOUT + 5,
                                        ready=lambda: bool(self.player.segment and self.player.segment.playing))

    def _load_in_player(self, kind: str, meta_id: str, video_id: str, title: str, source: streams.Source,
                        start: float = 0, message: str | None = None, tried: list[int] | None = None) -> bool:
        url = player.stream_url(source.stream)
        if not url:
            return False
        meta = self._media_meta(kind, meta_id, video_id, title, source)
        meta["tried"] = sorted(set(tried or []) | {source.index})
        return self.player.load(url, title, meta, start=start, message=message,
                                fallback_subs=self._fallback_subs(kind, video_id))

    def _source_failed(self, meta: dict, position: float, alive: bool) -> bool:
        """Una fuente no arrancó o se cortó: la siguiente mejor, en el mismo punto. True si se intenta."""
        title = meta.get("title") or "esto"
        if alive and meta.get("source") is not None:
            tried = set(meta.get("tried") or [meta["source"]])
            try:
                source = self.best_source(meta["kind"], meta["video_id"], meta.get("binge"), skip=tried)
            except stremio_api.StremioError:
                source = None
            if source is not None and len(tried) < 4:
                log.info("Probando otra fuente para %s (%s)", title, source_label(source))
                return self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], title, source,
                                            start=position, message=f"Probando otra fuente · {source_label(source)}",
                                            tried=list(tried))
        self._notify({"type": "toast", "ok": False,
                      "message": f"No pude reproducir {title}. Prueba otra fuente desde la ficha (Y)."})
        return False

    def _player_sources(self, meta: dict) -> list[dict]:
        """Pestaña Fuente del reproductor: las mejores del título, la actual marcada."""
        if meta.get("source") is None:
            return []
        found = self.stream_sources(meta["kind"], meta["video_id"])[:12]
        return [{"id": s.index, "label": source_label(s, long=True), "current": s.index == meta["source"]}
                for s in found]

    def _switch_source(self, meta: dict, index: int, position: float) -> None:
        source = self.streams.get(meta["kind"], meta["video_id"], self.stream_prefs, index)
        if source is not None:
            self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], meta.get("title") or "",
                                 source, start=position, message=f"Cambiando a {source_label(source)}…")

    def _episode_title(self, info: dict, meta_id: str, video_id: str) -> tuple[str, str]:
        label, name = self._episode_label(info, video_id)
        series = info.get("name") or meta_id
        return f"{series} · {label}".strip(" ·"), " · ".join(p for p in (label, name) if p)

    def _next_up(self, meta: dict) -> dict | None:
        """Para la tarjeta "Siguiente episodio": cuál es y cómo ponerlo (la fuente se busca ya)."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        next_id = cinemeta.next_episode(info, meta["video_id"])
        if next_id is None:
            return None
        title, detail = self._episode_title(info, meta["meta_id"], next_id)
        try:
            self.stream_sources("series", next_id)  # que al llegar el momento ya esté buscada
        except stremio_api.StremioError:
            pass
        label, name = self._episode_label(info, next_id)
        return {"label": label, "title": name,
                "play": lambda: self._play_episode(meta["meta_id"], next_id, title, meta.get("binge"))}

    def _play_episode(self, meta_id: str, video_id: str, title: str, binge: str | None = None,
                      start: float = 0) -> bool:
        """Otro episodio en el mismo reproductor (sin volver a Orbital)."""
        source = self.best_source("series", video_id, binge)
        if source is None:
            self.player.toast("No encontré dónde ver ese episodio", 4)
            return False
        return self._load_in_player("series", meta_id, video_id, title, source, start=start)

    def _step_episode(self, meta: dict, delta: int) -> None:
        """LT/RT en el reproductor: episodio anterior o siguiente."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        episodes = [e["id"] for s in cinemeta.seasons(info) if s["season"] != 0 for e in s["episodes"]]
        if meta["video_id"] not in episodes:
            return
        i = episodes.index(meta["video_id"]) + delta
        if not 0 <= i < len(episodes):
            self.player.toast("No hay episodio " + ("anterior" if delta < 0 else "siguiente"), 2.5)
            return
        title, _ = self._episode_title(info, meta["meta_id"], episodes[i])
        self._play_episode(meta["meta_id"], episodes[i], title, meta.get("binge"),
                           start=self.resume_position(meta["meta_id"], episodes[i]))

    @property
    def native_player(self) -> bool:
        """¿Se puede reproducir en el reproductor de Orbital (elegido, instalado y con cuenta)?"""
        return self.config.stremio.player == "orbital" and self.stremio_linked and player.find_mpv() is not None

    def play_title(self, kind: str, meta_id: str, video_id: str, title: str, audio: str | None = None) -> None:
        """Para la voz: pone algo sin preguntar, con la fuente recomendada. Buscar fuentes tarda
        unos segundos (Alexa corta a los ~8 s), así que se hace en segundo plano.

        `audio`: idioma pedido ("…en español"). Si ninguna fuente lo trae, se pone la mejor en tu
        idioma de siempre con subtítulos en el pedido, y se avisa."""
        if not self.native_player:
            self.play_stremio(kind, meta_id, video_id, title)
            return
        prefs = streams.Preferences(audio=audio, quality=self.stream_prefs.quality) if audio else None

        def run() -> None:
            try:
                source = self.best_source(kind, video_id, prefs=prefs)
                if source is None:
                    self._notify({"type": "toast", "message": f"No encontré dónde ver {title}", "ok": False})
                    return
                subtitles = None
                if audio and audio != self.stream_prefs.audio:
                    if audio in source.languages:
                        subtitles = ""  # lo pediste doblado: sin subtítulos encima
                    else:
                        subtitles = audio
                        name = {"es": "español", "en": "inglés"}.get(audio, audio)
                        self._notify({"type": "toast", "message": f"No hay audio en {name} para {title}: va con subtítulos en {name}"})
                self.play_source(kind, meta_id, video_id, source.index, title, prefs=prefs, subtitles=subtitles)
            except Exception as exc:  # noqa: BLE001 - se avisa en pantalla
                log.exception("No pude poner %s", title)
                self._notify({"type": "toast", "message": f"No pude poner {title}: {exc}", "ok": False})

        threading.Thread(target=run, daemon=True, name="play-title").start()

    def play_next_episode(self) -> str | None:
        """El episodio que sigue al que se está viendo en el reproductor; None si no hay."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        next_id = cinemeta.next_episode(info, current.meta["video_id"])
        if next_id is None:
            return None
        title, _ = self._episode_title(info, meta_id, next_id)
        label, _ = self._episode_label(info, next_id)
        threading.Thread(target=self._play_episode, args=(meta_id, next_id, title, current.meta.get("binge")),
                         daemon=True, name="next-episode").start()
        return label or "el siguiente episodio"

    def player_subtitles(self, lang: str) -> bool:
        """Subtítulos en ese idioma: los del video o, si no trae, los de tus addons."""
        if self.player.select_language("sub", lang):
            return True
        current = self.player.current
        auth = self.credentials.get(STREMIO_KEY)
        if current is None or not auth:
            return False
        urls = self.streams.subtitles(auth, current.meta["kind"], current.meta["video_id"], lang)
        if urls:
            self.player.add_subtitles(urls[0], lang)
        return bool(urls)

    def title_details(self, kind: str, meta_id: str) -> dict:
        """Todo para la ficha: datos, reparto, temporadas y dónde ibas (para "Continuar T3 E5")."""
        info = self.cinemeta.meta(kind, meta_id)
        details = {"id": meta_id, "kind": kind, "title": info.get("name") or "", "poster": info.get("poster"),
                   "background": info.get("background") or None, **cinemeta.describe_meta(info),
                   **cinemeta.credits(info)}
        if kind == "series":
            details["seasons"] = cinemeta.seasons(info)
        resume = None
        details["watched"] = []
        auth = self.credentials.get(STREMIO_KEY)
        if auth:
            try:
                raw = self.stremio_client.library_item(auth, meta_id)
            except stremio_api.StremioError as exc:
                log.info("No pude leer dónde ibas en %s: %s", meta_id, exc)
                raw = None
            state = (raw or {}).get("state") or {}
            if kind == "series":  # los vistos de verdad (no "todo lo anterior al que ibas")
                ids = [v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
                details["watched"] = sorted(stremio_api.parse_watched(state.get("watched"), ids))
            video_id = state.get("video_id") or None
            if video_id:
                position = stremio_api.resume_seconds(raw, video_id)
                duration = int(state.get("duration") or 0) / 1000
                label, name = self._episode_label(info, video_id) if kind == "series" else ("", "")
                if position or (kind == "series" and video_id != meta_id):
                    resume = {"video_id": video_id, "position": position, "duration": duration,
                              "label": label, "episode_title": name}
        details["resume"] = resume
        return details

    def _player_finished(self, meta: dict, position: float, duration: float, watched: float) -> None:
        self._save_progress(meta, position, duration, watched, refresh=True)

    def _save_progress(self, meta: dict, position: float, duration: float, watched: float, refresh: bool) -> None:
        """Guarda en tu cuenta de Stremio dónde te quedaste (Seguir viendo, en Orbital y en Stremio).
        Se llama cada minuto, al pausar y al terminar; `watched` son los segundos vistos desde la vez anterior."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth or (refresh and watched < 20 and position < 60):
            return  # se abrió y cerró sin ver nada: no se toca tu biblioteca
        kind, meta_id, video_id = meta["kind"], meta["meta_id"], meta["video_id"]
        try:
            info = self.cinemeta.meta(kind, meta_id)
        except cinemeta.CinemetaError:
            info = {}
        next_video = cinemeta.next_episode(info, video_id) if kind == "series" and info else None
        try:
            raw = self.stremio_client.library_item(auth, meta_id)
            item = stremio_api.with_progress(
                raw, meta_id=meta_id, kind=kind, name=info.get("name") or meta.get("title") or meta_id,
                poster=info.get("poster"), video_id=video_id, position=position, duration=duration,
                watched=watched, next_video=next_video, now=time.time(),
                video_ids=[v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")])
            self.stremio_client.save_library_item(auth, item)
            log.info("Progreso guardado en Stremio: %s %d/%d s", video_id, position, duration)
        except stremio_api.StremioError as exc:
            log.warning("No pude guardar el progreso en Stremio: %s", exc)
        if refresh:
            self.refresh_stremio(background=True)

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
        elif item_id.startswith("steam:"):
            # Steam guarda sus horas unos segundos después de cerrar el juego.
            threading.Timer(STEAM_STATS_DELAY, self.refresh_steam_stats).start()
        # Se cerró solo a los pocos segundos: casi siempre es que no pudo abrir (falta la ROM, el
        # firmware, una clave…). No es "de vuelta de": se avisa como problema.
        crashed = seconds < QUICK_EXIT and not self.launcher.last_stopped_by_user and not item_id.startswith(("media:", "app:"))
        self._notify({"type": "closed", "id": item_id, "title": title, "seconds": int(seconds), "crashed": crashed})

    def refresh_steam_stats(self) -> None:
        """Relee las horas y la última vez de Steam (barato: no reescanea la biblioteca)."""
        if self.steam_root is None:
            return
        stats = steam.user_stats(self.steam_root)
        with self._lock:
            for item in self._items.values():
                if item.source == "steam" and item.steam_appid is not None:
                    got = stats.get(str(item.steam_appid), {})
                    item.extra["steam_last_played"] = got.get("last_played", 0)
                    item.extra["steam_playtime"] = got.get("playtime", 0)
        self._notify({"type": "library-changed"})

    def _notify(self, event: dict) -> None:
        for listener in list(self.listeners):
            listener(event)
