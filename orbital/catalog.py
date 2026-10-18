"""Catálogo: la biblioteca de Orbital (juegos, apps, películas y series) y la puerta a todo lo demás.

Se divide en piezas que no se llaman entre sí, se comunican por eventos (events.EventBus):
  * Catalog (aquí): escanear fuentes, filas de la interfaz, preferencias y búsqueda por nombre.
  * Sessions (sessions.py): abrir algo, la pantalla de carga y saber cuándo termina.
  * Watch (watch.py): cuenta de Stremio, fuentes y el reproductor de Orbital.
  * ForYou (foryou.py): «Para ti», recomendaciones de Trakt, TMDB, RAWG y tus juegos.
  * LiveTV (tv.py): «TV en vivo», los canales de México, su salud y ponerlos en el reproductor.
  * focus.py: ventanas y foco (pantalla de carga encima del emulador).
Catalog expone también los métodos de Sessions y Watch que usan el servidor y la voz, para que
ellos solo conozcan una cosa.
"""

from __future__ import annotations

import difflib
import json
import logging
import os
import threading
import time
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote

from . import player
from .config import Config, expand
from .credentials import Credentials
from .events import EventBus
from .focus import READY_TIMEOUT, bring_app_to_front, bring_game_to_front, game_ready, is_orbital_window, pin_orbital  # noqa: F401 - compatibilidad
from .foryou import ForYou
from .launcher import Launcher
from .library import cinemeta, detect, emulators, esde, geforcenow, steam, steam_store, stremio, stremio_api, wiki_games
from .library.media import KINDS, MediaStore, low_res, placeholder
from .library.models import LibraryItem
from .library.scraper import Scraper, Target
from .library_watch import LibraryWatcher
from .sessions import QUICK_EXIT, Sessions  # noqa: F401
from .state import State
from .store import ItemStore
from .text import normalize
from .tv import LiveTV
from .watch import STREMIO_KEY, STREMIO_STALE_SECONDS, Watch, enrich_watch_item, source_label, stremio_item, time_left, trailer_id  # noqa: F401

CONTINUE_LIMIT = 20  # "Seguir viendo": los más recientes
JUMP_LIMIT = 16  # "Continuar" en Inicio
NEW_FOR = 7 * 86400  # un juego es "nuevo" su primera semana
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

def default_state(config: Config) -> State:
    if config.source is None:
        return State(None)
    return State(config.source.parent / "state.json")


def default_credentials(config: Config) -> Credentials:
    return Credentials(config.source.parent / "secrets.json" if config.source else None)


FILLER = {"el", "la", "los", "las", "un", "una", "de", "del", "the", "a", "of",
          # Lo que se dice alrededor del título: «el juego Hades», «la app YouTube», «Hades por favor».
          "juego", "videojuego", "app", "aplicacion", "programa", "por", "favor"}


def _one_edit(a: str, b: str) -> bool:
    """¿A lo más una letra distinta, de más o de menos?"""
    if abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(x != y for x, y in zip(a, b, strict=True)) <= 1
    short, long_ = (a, b) if len(a) < len(b) else (b, a)
    return any(long_[:i] + long_[i + 1:] == short for i in range(len(long_)))


def title_match(target: str, by_name: dict):
    """El título que quisiste decir, sin adivinar de más (Alexa transcribe; a veces mal):
    - todas tus palabras están en el título, como palabras ("zelda" → The Legend of Zelda); la última
      puede ir a medias ("hollow kni"). Antes bastaba un pedazo de letras: «h» abría Hades, «super man»
      Super Mario World y «chrono cross» Chrono Trigger.
    - o el título completo se parece mucho a lo que dijiste ("hello knight" → Hollow Knight).
    Si sobra una palabra que el título no tiene («silksong»), no es ese juego."""
    words = [w for w in target.split() if w not in FILLER] or target.split()
    if not words or len(target.replace(" ", "")) < 3:
        return None

    def has_all(name: str) -> bool:
        title = name.split()
        *full, last = words
        return all(w in title for w in full) and (last in title or (len(last) >= 4 and any(t.startswith(last) for t in title)))

    found = [i for name, i in by_name.items() if has_all(name)]
    if found:
        return min(found, key=lambda i: len(i.title))
    spoken = " ".join(words)  # sin «el juego…»: así se compara solo el título
    if len(spoken) >= 5:  # una letra mal oída («jades» → Hades), no dos («hands» no es Hades)
        near = [i for name, i in by_name.items() if _one_edit(spoken, name)]
        if near:
            return min(near, key=lambda i: len(i.title))
    close = difflib.get_close_matches(spoken, list(by_name), n=1, cutoff=0.82)  # «hands» ya no es Hades
    return by_name[close[0]] if close else None


def art_version(path: str | Path, sep: str = "&") -> str:
    """«&v=…» con la fecha del archivo: al cambiar la imagen («Cambiar imagen»), cambia la dirección y la
    pantalla deja de enseñar la vieja que tenía guardada (las imágenes se guardan un día)."""
    try:
        return f"{sep}v={int(Path(path).stat().st_mtime)}"
    except OSError:
        return ""


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
        # Cachés en disco (no en pruebas: sin config.yaml no se guarda nada).
        cache = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" if config.source else None
        self._steam_art = geforcenow.SteamArt(cache / "steam-appids.json" if cache else None)
        # De qué trata cada juego de Steam y GeForce NOW (la tienda de Steam, en español; ver steam_store.py).
        self.steam_store = steam_store.SteamStore(cache / "steam-store.json" if cache else None)
        # Los juegos de GeForce NOW que no están en Steam (Blizzard…): su ficha de Wikidata/Wikipedia (wiki_games.py).
        self.wiki_games = wiki_games.WikiGames(cache / "wiki-games.json" if cache else None)
        self._steam_owned: list[str] = []  # los juegos de tu cuenta de Steam que no están instalados (números)
        self._cache = cache
        # La biblioteca del último escaneo: la interfaz la muestra al instante mientras se escanea.
        self._snapshot = cache / "library.json" if cache else None
        self.media = MediaStore(Path(expand(config.art.dir)) if config.art.dir else None)
        self._scraper: Scraper | None = None
        self._scraped: set[tuple[str, str, str]] = set()  # lo que ya se buscó en esta sesión (no insistir)
        self._scraping = threading.Lock()
        self.scanning = False  # primer escaneo en curso (la interfaz sigue en su pantalla de arranque)
        self._refreshing = threading.Lock()  # un escaneo a la vez (arranque + botón "Actualizar")
        self.sessions = Sessions(config, self.state, self.launcher, self.store, self.events,
                                 runner_for=self.runner_for, last_end=lambda: self.watch.player.last_end)
        self.watch = Watch(config, self.state, self.credentials, stremio_client or stremio_api.StremioAPI(),
                           cinemeta_client or cinemeta.Cinemeta(), self.store, self.events, self.sessions,
                           self.launcher)
        self.foryou = ForYou(config, self)  # «Para ti»: recomendaciones (no sale a internet hasta que se pide)
        self.watch.scrobbler.trakt = lambda: self.foryou.trakt  # lo que ves, a Trakt (se pide en cada aviso)
        self.tv = LiveTV(config, self)  # «TV en vivo»: canales y su salud (no sale a internet hasta que arranca)
        self.events.subscribe(self._on_event)

    # --- piezas y compatibilidad ----------------------------------------------------------------
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
    def _esde_emulators(self) -> list:
        """Los sistemas que tienes en ES-DE y Orbital no conoce por su cuenta (Nintendo 64, SNES…), con los emuladores
        que ES-DE sabe usar (ver library/esde_systems.py)."""
        if not self.esde or not self.esde.executable:
            return []
        from .library import esde_systems

        covered = {e.system for e in self.emulators if e.system}
        try:
            preferred = {s: e for s in os.listdir(self.esde.home / "gamelists")
                         if (e := self.esde.gamelist(s).system_emulator)} if (self.esde.home / "gamelists").is_dir() else {}
            return esde_systems.configs(self.esde.executable.parent, self.esde.home / "custom_systems", self.esde.rom_root,
                                        covered, preferred)
        except Exception:  # noqa: BLE001 - las reglas de ES-DE nunca dejan a Orbital sin biblioteca
            log.exception("No pude leer los sistemas de ES-DE")
            return []

    def refresh(self) -> int:
        """Vuelve a buscar todo. Si ya hay un escaneo en curso, espera a que termine y usa ese."""
        if not self._refreshing.acquire(blocking=False):
            with self._refreshing:
                return len(self.store.all())
        try:
            return self._refresh()
        finally:
            self._refreshing.release()

    def wait_ready(self, timeout: float = 15) -> None:
        """Espera (un poco) a que termine el escaneo en curso: abrir un juego necesita saber qué
        emuladores hay, y al arrancar la biblioteca que se ve puede ser la guardada."""
        if self._refreshing.acquire(timeout=timeout):
            self._refreshing.release()

    def load_snapshot(self) -> bool:
        """La biblioteca del último arranque, para mostrarla ya. False si no hay (o está dañada)."""
        if not self._snapshot or not self._snapshot.exists():
            return False
        try:
            items = [LibraryItem.from_dict(d) for d in json.loads(self._snapshot.read_text(encoding="utf-8"))]
        except (OSError, ValueError, TypeError, AttributeError, KeyError) as exc:
            log.info("Biblioteca guardada ilegible (se escanea de cero): %s", exc)
            return False
        if not items:
            return False
        self.store.replace(items)
        log.info("Biblioteca guardada: %d elementos (escaneando para ponerla al día)", len(items))
        return True

    def _save_snapshot(self, items: list[LibraryItem]) -> None:
        if not self._snapshot:
            return
        try:
            self._snapshot.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._snapshot.with_suffix(".tmp")
            tmp.write_text(json.dumps([i.to_dict() for i in items]), encoding="utf-8")
            tmp.replace(self._snapshot)
        except (OSError, TypeError, ValueError) as exc:
            log.info("No pude guardar la biblioteca: %s", exc)

    def _refresh(self) -> int:
        found: list[LibraryItem] = []
        if self.config.steam.enabled:
            self.steam_root = steam.find_steam(self.config.steam.path)
            if self.steam_root:
                try:
                    installed = steam.scan(self.steam_root)
                    found += installed
                    have = {i.id.removeprefix("steam:") for i in installed}
                    self._steam_owned = sorted(steam.owned_appids(self.steam_root) - have)
                except Exception:  # noqa: BLE001 - un archivo de Steam roto no tumba el escaneo
                    log.exception("No pude leer la biblioteca de Steam")
                if self.config.steam.silent_start and self.config.source:  # no en pruebas
                    threading.Thread(target=steam.start_silent, args=(self.steam_root,), daemon=True).start()
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
                    icon_path=str(self.esde.executable.parent / "resources" / "graphics" / "window_icon_256.png"),
                )
            )
        self.emulators = list(self.config.emulators)
        self.detected = {}
        if self.config.detect.enabled:
            dirs = detect.default_search_dirs(self.config.detect.dirs, self.esde.executable if self.esde else None)
            result = detect.detect(dirs, skip_ids={e.id for e in self.config.emulators})
            self.emulators = detect.merge(self.config.emulators, result.emulators)
            self.detected = result.found
        self.emulators += self._esde_emulators()
        for emu, alternatives in emulators.split_alternatives(self.emulators):
            try:
                found += emulators.scan(emu, self.esde, alternatives, self.media)
            except Exception:  # noqa: BLE001 - un emulador con problemas no debe dejar a Orbital sin arrancar
                log.exception("No pude leer los juegos de %s", emu.name)
        if self.config.stremio.enabled:
            found += stremio.items(self.config.stremio)
        gfn_app = geforcenow.app_item()
        cloud: dict[str, dict] = {}
        if gfn_app:
            found.append(gfn_app)
            # Los de tu cuenta de Steam sin instalar que se pueden jugar en la nube: como juegos de GeForce NOW.
            if self._steam_owned and self.config.source:  # no en pruebas: la lista pública sale a internet
                try:
                    public = geforcenow.cloud_by_steam(self._cache / "gfn-public.json" if self._cache else None)
                    cloud = {a: public[a] for a in self._steam_owned if a in public}
                except Exception:  # noqa: BLE001 - la lista de NVIDIA nunca tumba el escaneo
                    log.exception("No pude leer la lista pública de GeForce NOW")
            gfn_games = geforcenow.items(self._steam_art, list(cloud.items()))
            found += gfn_games
            in_cloud = {str(i.steam_appid) for i in gfn_games if i.steam_appid}  # ya en GeForce NOW: no repetido en Steam
        else:
            in_cloud = set()
        # Todo lo de tu cuenta de Steam sin instalar (los que la tienda dice que son juegos) también está en Steam, con
        # «Instalar»: lo que se juega en la nube sigue además en GeForce NOW (antes solo ahí, y «Papers, Please» parecía
        # no estar en tu Steam).
        for appid in self._steam_owned:
            playable = appid in cloud or appid in in_cloud
            name = (cloud.get(appid) or {}).get("title") if appid in cloud else None
            if (name := name or self.steam_store.game_name(appid)) and steam._is_game(appid, name):
                found.append(steam.uninstalled_item(appid, name, cloud=playable))
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
                item.image = url + art_version(item.art_path, "?")
            if item.hero_path:
                item.hero = url + "?kind=hero" + art_version(item.hero_path)
                if low_res(item.hero_path):
                    item.extra["hero_lowres"] = True
            if item.logo_path:
                item.extra["logo"] = url + "?kind=logo" + art_version(item.logo_path)
            if item.icon_path and Path(item.icon_path).is_file():
                item.extra["icon"] = url + "?kind=icon"
            # Regla: todo lleva imagen. Sin portada o sin fondo, el respaldo de su sistema.
            if not item.image and item.category not in ("apps", "media"):
                item.image = placeholder("cover", item.system, item.id)
                item.extra["placeholder_cover"] = True
            if not item.hero:
                item.hero = placeholder("hero", item.system, item.id)
                item.extra["placeholder_hero"] = True
            self._store_facts(item)
            self._chosen_art(item)
        self.state.mark_seen([i.id for i in found if i.category in ("emulators", "steam")])
        self.store.replace(found)
        self._save_snapshot(found)
        if self.library_watch is not None:
            self.library_watch.accept()  # lo que hay ahora ya está escaneado: el vigilante no lo vuelve a pedir
        log.info("Catálogo: %d elementos", len(found))
        self.warm_covers()
        self.scrape_art(background=True)
        self.watch.refresh_stremio(background=True)
        if not self.watch.cinemeta_items:
            self.watch.refresh_cinemeta(background=True)
        return len(found)

    @staticmethod
    def thumbs_dir() -> Path:
        from .library import media

        return media.default_root().parent / "thumbs"

    def warm_covers(self) -> None:
        """Las portadas reducidas de toda la biblioteca, en segundo plano (ver thumbs.py)."""
        from . import thumbs

        paths = [Path(i.art_path) for i in self.store.all() if i.art_path]
        threading.Thread(target=thumbs.warm, args=(paths, thumbs.COVER_WIDTH, self.thumbs_dir()), daemon=True,
                         name="thumbs").start()

    # --- arte de los juegos (scraper propio) -----------------------------------------------------
    def art_targets(self, force: bool = False) -> list[Target]:
        """Juegos a los que les falta portada, fondo o logotipo (o el de ES-DE no sirve)."""
        paths = {"cover": "art_path", "hero": "hero_path", "logo": "logo_path"}
        targets = []
        for item in self.store.all():
            if not item.system or not item.media_key:
                continue
            # Un fondo que es solo una captura chica también se intenta mejorar (fanart).
            kinds = [k for k in KINDS
                     if not self.media.path(item.system, item.media_key, k)
                     and (force or not getattr(item, paths[k]) or (k == "hero" and low_res(item.hero_path)))]
            if self.media.meta(item.system, item.media_key) is None:
                kinds.append("meta")
            if kinds:
                targets.append(Target(item.system, item.media_key, item.title, kinds))
        return targets

    # --- juegos nuevos con Orbital abierto (library_watch.py) ------------------
    library_watch: LibraryWatcher | None = None  # el vigilante de carpetas (solo en la Orbital de verdad: server.py lo arranca)

    def watched_folders(self) -> list[tuple[Path, bool]]:
        """Las carpetas donde aparecen juegos: las de cada emulador (con subcarpetas si el emulador las recorre) y las de
        Steam (sus appmanifest: un juego recién instalado)."""
        out: list[tuple[Path, bool]] = []
        for emu in self.emulators:
            out += [(d, bool(emu.recursive)) for d in emulators.rom_dirs(emu, self.esde)]
        if self.steam_root:
            out += [(f, False) for f in steam.library_folders(self.steam_root)]
        return out

    def rescan_for_new(self) -> list[LibraryItem]:
        """Algo cambió en las carpetas de juegos: vuelve a buscar (con su portada, logo y datos) y avisa a la tele con el
        nombre de lo que llegó. Devuelve los juegos nuevos."""
        before = {i.id for i in self.store.all()}
        self.refresh()
        new = [i for i in self.store.all() if i.id not in before and i.category in ("emulators", "steam")]
        self.notify({"type": "library-changed"})
        if new:
            names = ", ".join(i.title for i in new[:3]) + (f" y {len(new) - 3} más" if len(new) > 3 else "")
            log.info("Juegos nuevos: %s", names)
            self.notify({"type": "toast", "message": f"Nuevo en tu biblioteca: {names}"})
        return new

    def scrape_art(self, background: bool = False) -> int:
        """Busca el arte que falte; si consiguió algo, vuelve a escanear para mostrarlo."""
        if not self.config.art.scrape:
            return 0
        if background:
            threading.Thread(target=self.scrape_art, name="scraper", daemon=True).start()
            return 0
        if not self._scraping.acquire(blocking=False):
            return 0
        try:
            targets = []
            for t in self.art_targets():
                kinds = [k for k in t.kinds if (t.system, t.key, k) not in self._scraped]
                self._scraped.update((t.system, t.key, k) for k in kinds)
                if kinds:
                    targets.append(Target(t.system, t.key, t.title, kinds))
            if not targets:
                return 0
            self._scraper = self._scraper or Scraper(self.media)
            added = self._scraper.run(targets)
        except Exception:  # noqa: BLE001 - sin internet o una fuente caída: se queda el arte que hay
            log.exception("No pude buscar arte")
            return 0
        finally:
            self._scraping.release()
        if added:
            log.info("Scraper: %d imágenes nuevas", added)
            self.refresh()
            self.notify({"type": "library-changed"})  # la tele enseña la portada nueva (antes, hasta recargar)
        return added

    def replace_art(self, item_id: str, kind: str) -> bool:
        """«No me gusta esta imagen»: la descarta y busca otra."""
        item = self.store.get(item_id)
        if item is None or not item.system or not item.media_key or kind not in KINDS:
            return False
        self._scraper = self._scraper or Scraper(self.media)
        current = {"cover": item.art_path, "hero": item.hero_path, "logo": item.logo_path}.get(kind)
        found = self._scraper.replace(Target(item.system, item.media_key, item.title, [kind]), kind, current)
        self.refresh()
        return found is not None

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
        # Recién llegado (en los últimos 7 días): la consola lo anuncia en Inicio.
        seen = self.state.first_seen(item.id)
        if seen and time.time() - seen < NEW_FOR:
            data["new"] = True
        # Cuándo llegó (filtro «Añadidos»): lo que vio Orbital o, para lo que ya tenías, la fecha del archivo.
        data["added"] = seen or item.extra.get("added") or None
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
                # Una fila por sistema, en el orden de config.yaml. Un emulador instalado sin juegos también sale (vacía,
                # con dónde ponerlos): si no, parecía que Orbital no lo había reconocido (RPCS3 recién instalado).
                with_games: set[str] = set()
                empty: list[dict] = []
                for emu in self.emulators:
                    games = [i for i in items if i.category == "emulators" and i.source == emu.id]
                    if games:
                        with_games.add(emu.system or emu.id)
                        row_id = f"emulators:{emu.id}"
                        rows.append({"id": row_id, "title": emu.name, "items": [self.describe(i) for i in games],
                                     "opened": self.state.opened(row_id)})
                    elif emu.system and emulators.executable_found(emu):
                        folder = emulators.rom_dirs(emu, self.esde)
                        empty.append({"id": f"emulators:{emu.id}", "title": emu.name, "items": [], "empty": True,
                                      "system": emu.system, "folder": str(folder[0]) if folder else None})
                seen_empty: set[str] = set()
                for row in empty:  # uno por sistema y solo si ese sistema no tiene juegos con otro emulador
                    if row["system"] not in with_games and row["system"] not in seen_empty:
                        seen_empty.add(row["system"])
                        rows.append(row)
                continue
            else:
                members = [i for i in items if i.category == cat["id"]]
            if members:
                rows.append({**cat, "items": [self.describe(i) for i in members], "opened": self.state.opened(cat["id"])})
        return rows

    def grouped_items(self, row_id: str) -> list[LibraryItem]:
        """Elementos de una fila, en el mismo orden que la interfaz."""
        row = next((r for r in self.grouped() if r["id"] == row_id), None)
        found = (self.get(i["id"]) for i in row["items"]) if row else ()
        return [i for i in found if i is not None]

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
        return title_match(target, by_name)

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

    def _chosen_art(self, item: LibraryItem) -> None:
        """«Cambiar el arte»: el póster o el fondo que elegiste para esa película o serie, en lugar del de siempre."""
        meta_id = (item.extra or {}).get("meta_id")
        if item.source not in ("stremio", "cinemeta") or not meta_id:
            return
        art = self.watch.art_for(meta_id)
        if art.get("poster"):
            item.image = art["poster"]
        if art.get("background"):
            item.hero = art["background"]

    def apply_art(self, meta_id: str) -> None:
        """Se acaba de elegir arte: la biblioteca lo toma ya, sin reescanear."""
        self.store.update(self._chosen_art, where=lambda i: (i.extra or {}).get("meta_id") == meta_id)
        self.notify({"type": "library-changed"})

    STORE_SOURCES = ("steam", "geforcenow")

    def _store_facts(self, item: LibraryItem) -> None:
        """Descripción, año, géneros y desarrollador de la tienda de Steam (sin pisar lo que el juego ya trae)."""
        if item.source in self.STORE_SOURCES and item.steam_appid:
            for key, value in self.steam_store.cached(item.steam_appid).items():
                item.extra.setdefault(key, value)
        elif item.source == "geforcenow" and item.category == "geforcenow":  # no está en Steam: Wikidata/Wikipedia
            for key, value in self.wiki_games.cached(item.title).items():
                item.extra.setdefault(key, value)

    def warm_store(self, stop: threading.Event | None = None) -> None:
        """Pide a la tienda de Steam las fichas que faltan (los jugados hace poco primero), en segundo plano, y las
        pone en la biblioteca sin reescanearla."""
        games = [i for i in self.store.all() if i.source in self.STORE_SOURCES and i.steam_appid]
        games.sort(key=lambda i: self.last_played(i) or 0, reverse=True)
        unknown = [int(a) for a in self._steam_owned if not self.steam_store.known(a)]  # para saber nombre y si es juego
        no_steam = [i.title for i in self.store.all() if i.category == "geforcenow" and not i.steam_appid]
        wiki = self.wiki_games.warm(no_steam, stop=stop)
        if not self.steam_store.warm([i.steam_appid for i in games if i.steam_appid] + unknown, limit=400, stop=stop):
            if wiki:
                self.store.update(self._store_facts, where=lambda i: i.source in self.STORE_SOURCES)
                self.notify({"type": "library-changed"})
            return
        if any(self.steam_store.known(a) for a in unknown):
            self.refresh()  # llegaron nombres de juegos sin instalar: entran a la biblioteca
        else:
            self.store.update(self._store_facts, where=lambda i: i.source in self.STORE_SOURCES)
        self.notify({"type": "library-changed"})

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
            "trakt": self.foryou.status()["trakt"],
            "player": player.find_mpv() is not None,
            "alexa": bool(self.config.server.token) and not self.config.server.token_is_ephemeral,
        }
