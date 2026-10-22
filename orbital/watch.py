"""Películas y series: tu cuenta de Stremio, elegir la fuente y el reproductor de Orbital.

Seguir viendo y Mi lista (cuenta de Stremio), los populares de Cinemeta, buscar y ordenar fuentes,
reproducir en mpv con el mando (siguiente episodio, otra fuente si una falla) y guardar el avance.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path

from . import companion, player, player_ui
from .config import Config
from .credentials import Credentials
from .events import EventBus
from .launcher import Launcher
from .library import addons, cinemeta, localize, streams, stremio_api
from .library import tmdb as tmdb_api
from .library.models import LibraryItem
from .scrobble import TraktScrobbler
from .sessions import Sessions
from .state import State
from .store import ItemStore

log = logging.getLogger(__name__)

STREMIO_KEY = "stremio_auth_key"
ADDONS_KEY = "stremio_addons"  # tus complementos: cifrados como la clave de sesión (sus URLs llevan claves)
STREMIO_STALE_SECONDS = 180


def expired_session(exc: Exception) -> bool:
    """¿Stremio dice que la sesión ya no vale? (tienes que volver a conectar la cuenta)"""
    text = str(exc).lower()
    return any(w in text for w in ("session not found", "not authorized", "unauthorized", "invalid auth", "authkey"))


def language_code(code: str | None) -> str | None:
    """Código de pista de mpv ("spa", "es-MX", "eng") -> el de Ajustes ("es", "en"); "" = sin
    subtítulos; None si es otro idioma (no se recuerda)."""
    if code == "":
        return ""
    code = (code or "").lower()
    if code in ("es", "spa", "esl", "esp") or code.startswith(("es-", "es_")):  # «est» es estonio, no español
        return "es"
    if code.startswith("en"):
        return "en"
    return None


def spanish_variant(code: str | None) -> str:
    """El doblaje de una pista o de un ajuste: «es-419» (latino: es-MX, es-419, es-LA…), «es-ES» (castellano) o ""."""
    code = (code or "").lower().replace("_", "-")
    if not code.startswith("es-"):
        return ""
    return "es-ES" if code == "es-es" else "es-419"


SUBTITLE_LINES = {"": "Sin subtítulos", "forced": "Solo traducciones en pantalla"}


def version_line(source: streams.Source, prefs: streams.Preferences, subtitles: str) -> str:
    """Lo que va a sonar con «Ver», en palabras: «Latino · 1080p · Sin subtítulos». El doblaje solo si el nombre de la
    fuente lo dice (si no, «Español»); el idioma que pediste si la fuente lo trae, si no el que trae."""
    lang = prefs.audio if prefs.audio in source.languages else (source.languages or [""])[0]
    name = source.dub.capitalize() if lang == "es" and source.dub else streams.LANG_NAMES.get(lang, lang)
    subs = SUBTITLE_LINES.get(subtitles) or f"Subtítulos en {streams.LANG_NAMES.get(subtitles, subtitles).lower()}"
    return " · ".join(p for p in (name, source.resolution, subs) if p)


def handoff_pick(handoff: dict) -> dict | None:
    """Las pistas que venía usando el iPhone, como las recuerda la TV («Continuar»): los subtítulos (o sin) y el audio."""
    sub, audio = handoff.get("subtitle"), handoff.get("audio")
    pick = dict(sub) if isinstance(sub, dict) else {}
    if isinstance(audio, dict):
        pick["audio"] = audio
    return pick or None


def source_label(source: streams.Source, long: bool = False) -> str:
    """"1080p · Al instante" / "4K HDR · Torrentio": de dónde viene lo que ves, en pocas palabras."""
    quality = " ".join(p for p in (source.resolution or "SD", *source.hdr[:1]) if p)
    parts = [quality, "Al instante" if source.cached else source.addon]
    if long:
        parts.append(" + ".join(streams.LANG_NAMES.get(l, l) for l in source.languages[:2]))
        if source.size:
            parts.append(f"{source.size / 1e9:.1f} GB")
    return " · ".join(p for p in parts if p)


def player_source_label(source: streams.Source) -> str:
    """"Español · 1080p · Al instante · 1.2 GB": el idioma primero, que es lo que se busca al cambiar."""
    langs = " + ".join(streams.LANG_NAMES.get(lang, lang) for lang in source.languages[:2])
    size = f"{source.size / 1e9:.1f} GB" if source.size else ""
    return " · ".join(p for p in (langs, source_label(source), size) if p)


def player_source_row(source: streams.Source) -> dict:
    """Una fila de Y › Fuentes: «Español · 1080p WEB-DL» y, a la derecha, «Al instante · 1.2 GB». Antes iba
    todo en una línea que se cortaba y varias filas se veían idénticas."""
    langs = " + ".join(streams.LANG_NAMES.get(lang, lang) for lang in source.languages[:2])
    quality = " ".join(p for p in (source.resolution or "SD", *source.hdr[:1]) if p)
    kind = next((t for t in source.tags if t in ("REMUX", "BluRay", "WEB-DL", "x265", "AV1", "CAM")), "")
    size = f"{source.size / 1e9:.1f} GB" if source.size else ""
    return {"label": " · ".join(p for p in (langs, f"{quality} {kind}".strip()) if p),
            "hint": " · ".join(p for p in ("Al instante" if source.cached else source.addon, size) if p)}


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
        # Con id de IMDb, el póster de metahub (el de Amazon que guarda Stremio a veces ya no existe).
        image=stremio_api.METAHUB_POSTER.format(id=w.id) if w.id.startswith("tt") else w.poster,
        hero=w.background,
        uri=w.deep_link,
        progress=w.progress,
        last_watched=w.last_watched,
        # Para elegir la fuente en Orbital (Seguir viendo -> el mismo episodio).
        extra={"kind": w.type, "meta_id": w.id, "video_id": w.video_id or (w.id if w.type == "movie" else None),
               "in_library": w.in_library, "left": round(left) if left >= 60 else None,  # para «termina a las…»
               "eyebrow": " · ".join(filter(None, ["Película" if w.type == "movie" else "Serie", detail if episode else ""]))},
    )


def trailer_id(info: dict) -> str | None:
    """El video de YouTube del tráiler (Cinemeta: trailerStreams[].ytId o trailers[].source)."""
    for stream in info.get("trailerStreams") or []:
        if isinstance(stream, dict) and stream.get("ytId"):
            return str(stream["ytId"])
    for trailer in info.get("trailers") or []:
        if isinstance(trailer, dict) and trailer.get("source") and trailer.get("type", "Trailer") == "Trailer":
            return str(trailer["source"])
    return None


_YOUTUBE_SEEN: dict[str, bool] = {}


def youtube_available(video: str, *, open_url=urllib.request.urlopen) -> bool:
    """¿Ese video de YouTube existe y es público? Cinemeta a veces trae el id de un tráiler que ya borraron o que es
    privado, y «Tráiler» salía para nada. oEmbed contesta 401/404 en esos casos. Sin red: sí (un tropiezo no lo esconde,
    y no se recuerda)."""
    if video in _YOUTUBE_SEEN:
        return _YOUTUBE_SEEN[video]
    url = "https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote(f"https://www.youtube.com/watch?v={video}", safe="")
    try:
        with open_url(url, timeout=3) as response:
            ok = 200 <= response.status < 300
    except urllib.error.HTTPError as exc:
        ok = exc.code not in (400, 401, 403, 404)
    except (OSError, ValueError):
        return True
    _YOUTUBE_SEEN[video] = ok
    return ok


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



_CACHE_LOCK = threading.Lock()
RETRY_SECONDS = 1.5  # Cinemeta: espera antes del segundo intento

class Watch:
    def __init__(self, config: Config, state: State, credentials: Credentials, stremio_client: stremio_api.StremioAPI,
                 cinemeta_client: cinemeta.Cinemeta, store: ItemStore, events: EventBus, sessions: Sessions,
                 launcher: Launcher) -> None:
        self.config = config
        self.state = state
        self.credentials = credentials
        self.stremio_client = stremio_client
        self.cinemeta = cinemeta_client
        self.onedrive = None  # OneDriveLibrary (catalog.py la pone): «Tu OneDrive» como fuente
        self.downloads = None  # Downloads (catalog.py la pone): lo que bajaste para ver sin internet
        self.trailer_available = youtube_available  # «Tráiler» solo si el video existe (las pruebas lo cambian)
        self.store = store
        self.events = events
        self.sessions = sessions
        self.launcher = launcher
        self.stremio_error: str | None = None
        # La última biblioteca de Stremio, guardada: al arrancar, Seguir viendo y Continuar ya salen en su
        # orden y no se reacomodan unos segundos después cuando llega la descarga nueva.
        self._stremio_cache = (Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache"
                               / "stremio-library.json") if config.source else None
        self.stremio_items: list[LibraryItem] = self._load_stremio_cache()
        self.cinemeta_items: list[LibraryItem] = []
        self._stremio_fetched = 0.0
        self._stremio_busy = threading.Lock()
        self._stremio_again = False
        self._stremio_generation = 0
        self._stremio_publish = threading.Lock()
        self._saving = threading.Lock()
        # Tus complementos (los de la cuenta y los tuyos): fuentes, subtítulos y fichas.
        self.addons = addons.AddonRegistry(self.stremio_client, auth=lambda: self.credentials.get(STREMIO_KEY),
                                           own=self.own_addons)
        self.cinemeta.registry = self.addons
        # Las fichas en el idioma de Orbital (TMDB traduce lo que Cinemeta da en inglés).
        self.localizer = localize.Localizer(tmdb_api.Tmdb(config.para_ti.tmdb_key, timeout=5),
                                            lambda: self.setting("language", config.ui.language))
        self.cinemeta.localize = self.localizer.meta
        self.streams = streams.StreamFinder(self.addons)
        self.player = player.OrbitalPlayer(
            on_finished=self._player_finished, idle_seconds=config.sessions.video_idle_minutes * 60,
            on_idle=lambda title, minutes, live=False: self.events.publish({
                "type": "toast", "message": f"Cerré {title}",
                "detail": f"Llevaba {minutes} min sin que lo vieras" if live
                else f"Llevaba {minutes} min en pausa · Sigues donde te quedaste"}))
        self.scrobbler = TraktScrobbler()  # catalog.py le da el Trakt de «Para ti» cuando ya existe
        self._wire_player()

    # --- Stremio -------------------------------------------------------------
    @property
    def stremio_linked(self) -> bool:
        return bool(self.credentials.get(STREMIO_KEY))

    @property
    def has_addons(self) -> bool:
        """Hay a quién pedirle fuentes: tu cuenta de Stremio o complementos tuyos."""
        return self.stremio_linked or bool(self.addons.local)

    def own_addons(self) -> list[str]:
        return addons.clean_urls(self.credentials.get(ADDONS_KEY))

    def add_addon(self, url: str) -> addons.Addon:
        """Agrega un complemento tuyo (comprueba antes que responde y que da algo que Orbital usa)."""
        clean = addons.manifest_url(url)
        if not clean:
            raise ValueError("Eso no es la dirección de un complemento (https://…/manifest.json o stremio://…)")
        try:
            found = addons.parse_manifest(addons.fetch_json(clean), clean)
        except addons.NET_ERRORS as exc:
            raise ValueError(f"El complemento no respondió ({addons.redact(clean)}): {exc}") from exc
        if not found:
            raise ValueError("Ese complemento no da fuentes, subtítulos, fichas ni catálogos")
        self.credentials.set(ADDONS_KEY, [*self.own_addons(), clean])
        return found

    def remove_addon(self, number: int) -> str:
        """Quita el complemento número `number` (1 = el primero de `orbital stremio addons`)."""
        own = self.own_addons()
        if not 1 <= number <= len(own):
            raise ValueError(f"No hay complemento {number}: tienes {len(own)}")
        gone = own.pop(number - 1)
        self.credentials.set(ADDONS_KEY, own or None)
        return addons.redact(gone)

    def _load_stremio_cache(self) -> list[LibraryItem]:
        if not self._stremio_cache or not self.stremio_linked:
            return []
        try:
            return [LibraryItem.from_dict(d) for d in json.loads(self._stremio_cache.read_text(encoding="utf-8"))]
        except (OSError, ValueError, TypeError, AttributeError, KeyError):
            return []

    def _save_stremio_cache(self, items: list[LibraryItem]) -> None:
        if not self._stremio_cache:
            return
        try:
            with _CACHE_LOCK:  # la descarga y el enriquecimiento en segundo plano guardan a la vez
                self._stremio_cache.parent.mkdir(parents=True, exist_ok=True)
                tmp = self._stremio_cache.with_suffix(".tmp")
                tmp.write_text(json.dumps([i.to_dict() for i in items], ensure_ascii=False), encoding="utf-8")
                tmp.replace(self._stremio_cache)
        except OSError:
            log.warning("No pude guardar la biblioteca de Stremio en caché", exc_info=True)

    def refresh_stremio(self, background: bool = False) -> bool:
        """Descarga la biblioteca de Stremio. En segundo plano no bloquea a quien llama."""
        if not self.config.stremio.enabled or not self.stremio_linked:
            return False
        if background:
            threading.Thread(target=self.refresh_stremio, daemon=True).start()
            return True
        if not self._stremio_busy.acquire(blocking=False):
            # Ya hay una descarga en curso; quizá empezó antes de lo que acabas de cambiar (Quitar de
            # Seguir viendo, Mi lista): al terminar se descarga otra vez.
            self._stremio_again = True
            return False
        self._stremio_again = False
        generation = self._stremio_generation
        try:
            raw = self.stremio_client.library(self.credentials.get(STREMIO_KEY) or "")
            items = []
            for w in stremio_api.parse_library(raw):
                try:
                    items.append(stremio_item(w))
                except (TypeError, ValueError, AttributeError) as exc:
                    log.warning("Stremio: se salta %s (%s)", getattr(w, "id", "?"), exc)
            self.stremio_error = None
            self._enrich_continue(items)
        except stremio_api.StremioError as exc:
            log.warning("Stremio: %s", exc)
            self.stremio_error = str(exc)
            return False
        except Exception as exc:  # noqa: BLE001 - nada raro de Stremio deja tu lista vacía en silencio
            log.exception("Stremio: no pude leer tu biblioteca")
            self.stremio_error = f"No pude leer tu biblioteca de Stremio ({type(exc).__name__})"
            return False
        finally:
            self._stremio_fetched = time.time()
            self._stremio_busy.release()
            if self._stremio_again:
                threading.Thread(target=self.refresh_stremio, daemon=True).start()
        with self._stremio_publish:
            if generation != self._stremio_generation or not self.stremio_linked:
                return False  # cerraste sesión mientras se descargaba: no se vuelve a poner esa lista
            self.store.replace_source("stremio", items)
            changed = [i.id for i in items] != [i.id for i in self.stremio_items] or any(
                a.progress != b.progress for a, b in zip(items, self.stremio_items, strict=False))
            self.stremio_items = items
            self._save_stremio_cache(items)
        if changed:
            self.events.publish({"type": "library-changed"})
        # Mi lista también lleva sinopsis, calificación y logo (antes solo Seguir viendo): en
        # segundo plano, para no demorar lo que ya se ve.
        rest = [i for i in items if i.category != "continue" and not i.extra.get("description")]
        if rest:
            threading.Thread(target=self._enrich_rest, args=(items, rest), daemon=True).start()
        return True

    def _enrich_rest(self, items: list[LibraryItem], rest: list[LibraryItem]) -> None:
        self._enrich(rest)
        if not any(i.extra.get("description") for i in rest):
            return  # Cinemeta no respondió: nada que avisar (la próxima descarga lo reintenta)
        if self.stremio_items is not items:
            return  # llegó una descarga más nueva: ella se encarga
        self.store.replace_source("stremio", items)
        self._save_stremio_cache(items)
        self.events.publish({"type": "library-changed"})

    def _enrich_continue(self, items: list[LibraryItem]) -> None:
        """Datos de Cinemeta para Seguir viendo (en paralelo y con caché: la segunda vez es al instante)."""
        self._enrich([i for i in items if i.category == "continue"])

    def _enrich(self, items: list[LibraryItem]) -> None:
        wanted = [i for i in items if i.extra.get("kind") in ("movie", "series")]

        def meta(item: LibraryItem):
            # Con ~200 títulos a la vez alguno falla por un instante: un segundo intento antes de rendirse.
            for attempt in range(2):
                try:
                    return item, self.cinemeta.meta(item.extra["kind"], item.extra["meta_id"])
                except cinemeta.CinemetaError:
                    if attempt == 0:
                        time.sleep(RETRY_SECONDS)
            return item, None

        with ThreadPoolExecutor(max_workers=6) as pool:
            for item, info in pool.map(meta, wanted):
                if info:
                    try:
                        enrich_watch_item(item, info)
                    except (TypeError, ValueError, AttributeError) as exc:  # una ficha rara no tumba al resto
                        log.warning("Cinemeta: ficha rara de %s (%s)", item.title, exc)

    def dismiss_continue(self, meta_id: str) -> None:
        """"Quitar de Seguir viendo": en tu cuenta de Stremio (desaparece también en Stremio)."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        raw = self.stremio_client.library_item(auth, meta_id)
        if raw:
            self.stremio_client.save_library_item(auth, stremio_api.dismissed(raw, time.time()))
        self.refresh_stremio()
        self.events.publish({"type": "library-changed"})

    def refresh_cinemeta(self, background: bool = False) -> bool:
        """Películas y series populares (catálogo público de Stremio; no necesita cuenta)."""
        if not self.config.stremio.enabled:
            return False
        if background:
            threading.Thread(target=self.refresh_cinemeta, daemon=True).start()
            return True
        try:
            items = [*cinemeta.catalog_items("movie", self.localizer.catalog("movie", self.cinemeta.catalog("movie"))),
                     *cinemeta.catalog_items("series", self.localizer.catalog("series", self.cinemeta.catalog("series")))]
        except cinemeta.CinemetaError as exc:
            log.warning("Populares de Stremio: %s", exc)
            return False
        self.store.replace_source("cinemeta", items)
        self.cinemeta_items = items
        self.events.publish({"type": "library-changed"})
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
        with self._stremio_publish:
            self._stremio_generation += 1  # una descarga que ya iba a medias no vuelve a poner la cuenta
            self.credentials.set(STREMIO_KEY, None)
            self.store.replace_source("stremio", [])
            self.stremio_items = []
            if self._stremio_cache:
                self._stremio_cache.unlink(missing_ok=True)

    # --- películas y series en el reproductor de Orbital -----------------------------------------
    def setting(self, key: str, default=None):
        """Lo que elegiste en Ajustes manda; si no, config.yaml."""
        return self.state.settings().get(key, default)

    @property
    def stream_prefs(self) -> streams.Preferences:
        """Ajustes › Idioma: «en», «es» (cualquier español), «es-419» (latino) o «es-ES» (castellano)."""
        audio = str(self.setting("audio", self.config.stremio.audio) or "en")
        variant = spanish_variant(audio)
        return streams.Preferences(audio="es" if variant else audio, spanish=variant,
                                   quality=self.setting("quality", self.config.stremio.quality))

    @property
    def subtitles_lang(self) -> str:
        return self.setting("subtitles", self.config.stremio.subtitles)

    def language_for(self, meta_id: str) -> tuple[streams.Preferences, str]:
        """Idioma de audio y subtítulos para un título: el que elegiste viéndolo (cada serie
        recuerda el suyo) o, si nunca cambiaste, el de Ajustes."""
        saved = self.state.prefs(f"stremio:{meta_id}")
        prefs = self.stream_prefs
        # Solo texto: un valor raro en state.json («audio»: ["x"]) impedía reproducir ese título.
        if isinstance(saved.get("audio"), str) and saved["audio"]:
            prefs = replace(prefs, audio=saved["audio"])
        if prefs.audio == "es" and saved.get("spanish") in streams.SPANISH_VARIANTS:
            prefs = replace(prefs, spanish=saved["spanish"])  # elegiste la pista latina (o castellana) de esta serie
        subtitles = saved.get("subtitles")
        return prefs, subtitles if isinstance(subtitles, str) else self.subtitles_lang

    def _remember_language(self, meta: dict, kind: str, code: str) -> None:
        """Cambiaste el audio o los subtítulos en el reproductor: esa serie (o película) lo recuerda."""
        lang = language_code(code)
        if meta.get("meta_id") and lang is not None:
            self.state.set_pref(f"stremio:{meta['meta_id']}", kind, lang)
            if kind == "audio" and lang == "es" and spanish_variant(code):  # la pista latina: los siguientes, en latino
                self.state.set_pref(f"stremio:{meta['meta_id']}", "spanish", spanish_variant(code))
            log.info("%s recordará %s: %s", meta.get("title") or meta["meta_id"], kind, lang or "sin subtítulos")

    def stream_sources(self, kind: str, video_id: str, prefs: streams.Preferences | None = None) -> list[streams.Source]:
        """Fuentes de tus addons, ordenadas por tus preferencias (la primera es la recomendada). Tu OneDrive ya no va aquí
        (como el iPhone): tu copia se ve desde Mi media (play_own)."""
        if not self.has_addons:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        return self.streams.find(kind, video_id, prefs or self.stream_prefs)

    def _url_for(self, source: streams.Source) -> str | None:
        if source.stream.get("onedrive") and self.onedrive is not None:
            return self.onedrive.stream_url(source)
        return player.stream_url(source.stream)

    def play_own(self, kind: str, meta_id: str, video_id: str, title: str, file_id: str | None = None,
                 keep: bool = False, from_start: bool = False) -> dict:
        """Mi media: tu copia de OneDrive (la mejor versión, o la que elegiste). Si no abre, Real-Debrid en el mismo punto
        (el respaldo de siempre); el siguiente episodio también sale de tu carpeta si está."""
        source = self.onedrive.source(kind, video_id, file_id) if self.onedrive is not None else None
        mpv_exe = player.find_mpv()
        if source is None:
            raise LookupError("Eso ya no está en tu carpeta de OneDrive.")
        if not mpv_exe:
            raise LookupError("Falta el reproductor de Orbital (mpv) para ver tu copia.")
        url = self.onedrive.stream_url(source) if self.onedrive is not None else None
        if not url:
            raise LookupError("OneDrive no me dio el archivo. Inténtalo de nuevo.")
        prefs, subtitles = self.language_for(meta_id)
        self.play_native(mpv_exe, url, kind, meta_id, video_id, title, keep=keep, source=source, from_start=from_start,
                         audio=prefs.audio, subtitles=subtitles, own=True)
        return {"source": source.public(), "label": f"Tu copia · {source.resolution}" if source.resolution else "Tu copia en OneDrive"}

    def _wire_player(self) -> None:
        """Lo que el reproductor le pregunta al catálogo (siguiente episodio, otras fuentes…)."""
        p = self.player
        p.on_progress = lambda meta, pos, dur, watched: self._save_progress(meta, pos, dur, watched, refresh=False)
        p.on_scrobble = self.scrobbler.event
        p.on_failed = self._source_failed
        p.next_provider = self._next_up
        p.sources_provider = self._player_sources
        p.on_switch_source = self._switch_source
        p.on_episode = self._step_episode
        p.episodes_provider = self._season_episodes
        p.on_play_episode = self._jump_episode
        p.on_sub_scale = lambda scale: self.state.set_setting("sub_scale", scale)
        p.iphone_provider = lambda: companion.phone_ready(self.config)
        p.on_send_iphone = self._send_to_phone
        p.idle_seconds = int(self.setting("video_idle_minutes", self.config.sessions.video_idle_minutes)) * 60
        p.on_language = self._remember_language
        p.spanish_provider = lambda meta: self.language_for(meta["meta_id"])[0].spanish if meta.get("meta_id") else ""
        p.pip_on_home = self.setting("video_home", "pip") == "pip"  # la barra dice «Home · Ver en pequeño»
        p.sub_scale = float(self.setting("sub_scale", 1.0) or 1.0)
        player_ui.set_text_size(self.setting("text_size", "normal"))  # la letra del reproductor sigue a Ajustes

    def _send_to_phone(self, meta: dict, action: str, position: float | None = None) -> str:
        """Y › «Seguir en el iPhone» (el mismo minuto) / «Enviar al iPhone» / «Descargar en el iPhone» con lo que se está
        viendo (el episodio en curso; el de un canal de Orbital, como episodio de su serie)."""
        kind = "series" if meta.get("synthetic") or meta.get("kind") == "channel" else meta.get("kind") or "movie"
        # «Seguir en el iPhone»: el mismo segundo, la misma fuente, el mismo audio y los mismos subtítulos.
        choice = {"source": meta.get("source_key"), "audio": self.player.current_audio(),
                  "subtitle": self.player.current_subtitle()} if action == "continue" else None
        sent = companion.send_to_phone(self, self.config, "open" if action == "continue" else action, kind,
                                       meta.get("meta_id") or "", meta.get("video_id"),
                                       position=position if action == "continue" else None, choice=choice)
        if action == "continue":
            minute = int((position or 0) // 60)
            return f"Abriendo en tu iPhone · {sent.get('episode_label') or sent.get('title') or ''} en el minuto {minute}".replace(" ·  en", " en")
        return companion.SENT_TOAST[action]

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
        """Lo que el reproductor necesita saber del video (y lo que se guarda en Stremio). En pausa
        muestra también los datos y la sinopsis (del episodio, si la hay; si no, de la serie)."""
        detail, facts, description, poster = "", "", "", None
        try:
            info = self.cinemeta.meta(kind, meta_id)
        except cinemeta.CinemetaError:
            info = None
        if info:
            poster = info.get("poster")
            about = cinemeta.describe_meta(info)
            facts = " · ".join(p for p in (about.get("year"), about.get("rating") and f"★ {about['rating']}",
                                           ", ".join((about.get("genres") or [])[:2])) if p)
            description = about.get("description") or ""
            if kind == "series":
                label, name = self._episode_label(info, video_id)
                detail = " · ".join(p for p in (label, name) if p)
                episode = next((e for s in cinemeta.seasons(info) for e in s["episodes"] if e["id"] == video_id), None)
                description = (episode or {}).get("overview") or description
        return {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title, "detail": detail,
                "facts": facts, "description": description, "poster": poster,
                "source": source.index, "source_label": source_label(source), "binge": source.binge,
                "source_key": source.key, "tried": [source.index]}

    def best_source(self, kind: str, video_id: str, binge: str | None = None,
                    skip: set[int] | None = None, prefs: streams.Preferences | None = None) -> streams.Source | None:
        """La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior
        (misma calidad e idioma: así lo hace Stremio con bingeGroup)."""
        found = [s for s in self.stream_sources(kind, video_id, prefs) if s.index not in (skip or set())]
        if self.native_player:  # solo las que el reproductor de Orbital puede abrir (una ftp:// atoraba el respaldo)
            found = [s for s in found if player.stream_url(s.stream) or s.stream.get("onedrive")]
        if not found:
            return None
        if binge:
            same = next((s for s in found if s.binge == binge and s.score > found[0].score - 700), None)
            if same:
                return same
        return found[0]

    def choose_source(self, kind: str, video_id: str, prefs: streams.Preferences,
                      resume: dict | None = None) -> streams.Source | None:
        """La que pone «Ver»: la fuente con la que lo dejaste («Continuar»), si sigue ahí; si no, la recomendada. La misma
        cuenta para reproducir y para decir en la ficha qué va a sonar (antes la ficha describía otra)."""
        if resume and resume.get("source"):
            same = next((s for s in self.stream_sources(kind, video_id, prefs) if s.key == resume["source"]), None)
            if same is not None:
                return same
        return self.best_source(kind, video_id, prefs=prefs)

    def no_sources_message(self, kind: str, video_id: str) -> str:
        """Por qué no hay dónde verlo, con qué hacer: sin Internet, sin complementos o de verdad no hay."""
        why = self.streams.outcome.get(f"{kind}:{video_id}")
        if why == "offline":
            return "No pude conectar con tus complementos de Stremio. Revisa Internet e inténtalo de nuevo."
        if why == "no-addons":
            return "Tu cuenta de Stremio no tiene complementos de video (como Torrentio). Instálalos en Stremio."
        return "No encontré dónde ver esto: tus complementos de Stremio no lo tienen."

    def play_best(self, kind: str, meta_id: str, video_id: str, title: str, keep: bool = False,
                  from_start: bool = False, handoff: dict | None = None) -> dict:
        """"Ver": sin lista de fuentes. Orbital elige la recomendada y arranca (la lista queda en Y). Si lo descargaste,
        tu descarga, del disco (arranca al instante y sin internet).
        `handoff`: lo que venía viendo el iPhone («Ver en la TV» desde su reproductor): {position, source, audio,
        subtitle}. Se sigue en ese segundo, con esa fuente (si la TV la tiene), ese audio y esos subtítulos."""
        handoff = handoff if handoff and not from_start else None
        start_at = handoff.get("position") if handoff else None
        pick = handoff_pick(handoff) if handoff else None
        if self.downloads is not None and self.downloads.file_for(video_id) \
                and self.play_downloaded(video_id, from_start=from_start, start_at=start_at, sub_pick=pick):
            return {"source": None, "label": "Tu descarga · sin internet"}
        prefs, subtitles = self.language_for(meta_id)
        resume = None if from_start else self.resume_choice(meta_id, video_id)
        if resume and isinstance(resume.get("audio"), dict):  # el audio con que lo dejaste en la TV
            resume = {**resume, "sub": {**(resume.get("sub") or {}), "audio": resume["audio"]}}
        if handoff:
            resume = {"video_id": video_id, "source": handoff.get("source"), "sub": pick}
            code = (handoff.get("audio") or {}).get("lang")
            audio = language_code(code)
            if audio:  # el idioma del audio del iPhone (con su variante): también para elegir fuente si la suya no está
                prefs = replace(prefs, audio=audio, spanish=spanish_variant(code) or (prefs.spanish if audio == "es" else ""))
            sub = handoff.get("subtitle") or {}
            if sub.get("off"):
                subtitles = ""
            elif language_code(sub.get("lang")):
                subtitles = language_code(sub.get("lang")) or subtitles
        source = self.choose_source(kind, video_id, prefs, resume)
        if source is None:
            raise LookupError(self.no_sources_message(kind, video_id))
        self.play_source(kind, meta_id, video_id, source.index, title, keep=keep, from_start=from_start,
                         prefs=prefs, subtitles=subtitles, sub_pick=(resume or {}).get("sub"), start_at=start_at)
        return {"source": source.public(), "label": source_label(source)}

    def play_source(self, kind: str, meta_id: str, video_id: str, index: int, title: str, keep: bool = False,
                    from_start: bool = False, prefs: streams.Preferences | None = None,
                    subtitles: str | None = None, sub_pick: dict | None = None, start_at: float | None = None) -> str:
        """Reproduce la fuente elegida: en el reproductor de Orbital (mpv, con el mando) o, si no
        está o así se configuró, directo en el de Stremio (sin su lista de fuentes).
        `prefs`/`subtitles`: idioma pedido para esta vez ("…en español"); si no, el de Ajustes."""
        self.sessions.revealing = False
        saved_prefs, saved_subs = self.language_for(meta_id)
        prefs = prefs or saved_prefs
        subtitles = saved_subs if subtitles is None else subtitles
        from .onedrive_library import INDEX as ONEDRIVE_INDEX

        source = self.onedrive.source(kind, video_id) if index == ONEDRIVE_INDEX and self.onedrive is not None \
            else self.streams.get(kind, video_id, prefs, index)
        if source is None:  # la lista caducó o se pidió con otro idioma: se vuelve a buscar una vez
            self.stream_sources(kind, video_id, prefs)
            source = self.streams.get(kind, video_id, prefs, index)
        if source is None:
            raise ValueError("Esa fuente ya no está disponible; vuelve a cargar las fuentes")
        mpv_exe = player.find_mpv() if self.config.stremio.player == "orbital" else None
        # «Tu OneDrive»: Microsoft da una dirección temporal del archivo (se pide al momento de ver).
        url = self.onedrive.stream_url(source) if source.stream.get("onedrive") and self.onedrive is not None \
            else player.stream_url(source.stream)
        if source.stream.get("onedrive") and not mpv_exe:
            mpv_exe = player.find_mpv()  # Stremio no sabe abrir tu OneDrive: siempre el reproductor de Orbital
        if mpv_exe and url:
            self.play_native(mpv_exe, url, kind, meta_id, video_id, title, keep=keep, source=source,
                             from_start=from_start, audio=prefs.audio, subtitles=subtitles, sub_pick=sub_pick,
                             start_at=start_at)
            return "orbital"
        uri = streams.player_link(source, cinemeta.MANIFEST, kind, meta_id, video_id)
        self.sessions.open_stremio(uri, title)
        return uri

    def download_url(self, job: dict) -> tuple[str, str]:
        """Para Descargas: la dirección del archivo que se va a bajar (tu OneDrive; si no, una directa de 1080p)."""
        from .downloads import pick_source

        prefs = self.language_for(job["meta_id"])[0]
        # Tu copia de OneDrive primero (la de 1080p si la hay, como el iPhone); si no, Real-Debrid.
        mine = self.onedrive.versions(job["kind"], job["video_id"]) if self.onedrive is not None else []
        if mine:
            pick = next((v for v in mine if v["resolution"] == "1080p"), mine[0])
            source = self.onedrive.source(job["kind"], job["video_id"], pick["id"]) if self.onedrive is not None else None
            if source is not None:
                job["quality"] = source.resolution or None
                return self.onedrive.stream_url(source) or "", source.release
        source = pick_source(self.stream_sources(job["kind"], job["video_id"], prefs), prefs.audio)
        if source is None:
            return "", ""
        job["quality"] = source.resolution or None
        if source.stream.get("onedrive") and self.onedrive is not None:
            return self.onedrive.stream_url(source) or "", source.release
        return player.stream_url(source.stream) or "", source.release

    def play_downloaded(self, video_id: str, from_start: bool = False, start_at: float | None = None,
                        sub_pick: dict | None = None) -> bool:
        """Lo que bajaste, directo del disco (sin internet). False si no está descargado."""
        if self.downloads is None:
            return False
        job = self.downloads.find(video_id)
        path = self.downloads.file_for(video_id) if job else None
        mpv_exe = player.find_mpv()
        if job is None or not path or not mpv_exe:
            return False
        title = job.get("title") or "Video"
        self.play_native(mpv_exe, str(path), job["kind"], job["meta_id"], video_id, title, from_start=from_start,
                         start_at=start_at, sub_pick=sub_pick)
        return True

    def resume_position(self, meta_id: str, video_id: str) -> float:
        """Dónde ibas según Stremio (0 si no se sabe)."""
        try:
            return stremio_api.resume_seconds(
                self.stremio_client.library_item(self.credentials.get(STREMIO_KEY) or "", meta_id), video_id)
        except (stremio_api.StremioError, ValueError, TypeError, AttributeError, OverflowError) as exc:
            log.info("No pude leer dónde ibas: %s", exc)
            return 0.0

    def _fallback_subs(self, kind: str, video_id: str, subs: str | None = None):
        subs = self.subtitles_lang if subs is None else subs
        if subs == "forced":
            return None  # solo los forzados que trae el video: no se buscan subtítulos completos
        return (lambda: self.streams.subtitles(kind, video_id, subs)) if subs else None

    def play_native(self, mpv_exe: str, url: str, kind: str, meta_id: str, video_id: str, title: str,
                    keep: bool = False, source: streams.Source | None = None, from_start: bool = False,
                    audio: str | None = None, subtitles: str | None = None, sub_pick: dict | None = None,
                    own: bool = False, start_at: float | None = None) -> None:
        """mpv a pantalla completa, desde donde te quedaste (según Stremio); con `start_at`, desde ese segundo (el que
        venía viendo el iPhone)."""
        if not from_start and self.player.starting(video_id, source.key if source else None):
            # Ya está cargando: Orbital sigue tapando hasta la primera imagen (el aviso del primer intento sigue en pie).
            log.info("%s ya se está abriendo: no lo empiezo otra vez", title)
            self.sessions.revealing = True
            return
        if from_start:
            start = 0.0
        elif isinstance(start_at, (int, float)) and start_at > 0:
            start = float(start_at)
        else:
            start = self.resume_position(meta_id, video_id)
        meta: dict = self._media_meta(kind, meta_id, video_id, title, source) if source else \
            {"kind": kind, "meta_id": meta_id, "video_id": video_id, "title": title}
        if own:
            meta["own"] = True  # desde Mi media: el siguiente episodio también de tu carpeta
        # Lo que estaba abierto se cierra justo antes de abrir el video, no antes de buscar sus datos por
        # internet (si algo fallaba, tu juego ya se había cerrado para nada).
        if self.sessions.before_launch and not keep:
            self.sessions.before_launch("media:player")
        self._wire_player()
        pinned = self.sessions.pin()
        try:
            # Vigilar el proceso en el mismo paso que lo abre: con dos «pon…» a la vez, el vigilante
            # del primero (ya cerrado) borraba al segundo.
            self.player.play(
                self.launcher.run, mpv_exe, url, title, meta,
                start=start, audio=audio or self.stream_prefs.audio,
                subtitles=self.subtitles_lang if subtitles is None else subtitles,
                fallback_subs=self._fallback_subs(kind, video_id, subtitles), sub_pick=None if from_start else sub_pick,
                started=lambda process: self.launcher.track("media:player", title, process, runner="Reproductor"))
        except BaseException:
            self.sessions.unpin(pinned)  # mpv no abrió: Orbital no se queda «siempre encima»
            raise
        # Hasta la primera imagen del video (cargar un stream tarda): antes se veía la ventana negra de mpv.
        self.sessions.revealing = self.sessions.to_front("media:player", title, pinned=pinned, timeout=player.STARTUP_TIMEOUT + 5,
                                        ready=lambda: bool(self.player.segment and self.player.segment.playing))

    def _load_in_player(self, kind: str, meta_id: str, video_id: str, title: str, source: streams.Source,
                        start: float = 0, message: str | None = None, tried: list[int] | None = None, own: bool = False) -> bool:
        url = self._url_for(source)
        if not url:
            return False
        meta = self._media_meta(kind, meta_id, video_id, title, source)
        meta["tried"] = sorted(set(tried or []) | {source.index})
        if own:
            meta["own"] = True
        prefs, subtitles = self.language_for(meta_id)  # el audio y los subtítulos que esta serie recuerda
        return self.player.load(url, title, meta, start=start, message=message, subtitles=subtitles, audio=prefs.audio,
                                fallback_subs=self._fallback_subs(kind, video_id, subtitles))

    def _source_failed(self, meta: dict, position: float, alive: bool) -> bool:
        """Una fuente no arrancó o se cortó: la siguiente mejor, en el mismo punto. True si se intenta."""
        title = meta.get("title") or "esto"
        if alive and meta.get("source") is not None:
            tried = set(meta.get("tried") or [meta["source"]])
            prefs = self.language_for(meta["meta_id"])[0]
            try:
                source = self.best_source(meta["kind"], meta["video_id"], meta.get("binge"), skip=tried, prefs=prefs)
                # El respaldo no cae en una grabación de cine ni en un tráiler sin que lo elijas tú.
                while source is not None and {"CAM", "Tráiler"} & set(source.tags):
                    tried.add(source.index)
                    source = self.best_source(meta["kind"], meta["video_id"], None, skip=tried, prefs=prefs)
            except stremio_api.StremioError:
                source = None
            if source is not None and len(tried) < 4:
                log.info("Probando otra fuente para %s (%s)", title, source_label(source))
                other = prefs.audio not in source.languages  # otro idioma: se dice cuál
                label = player_source_label(source) if other else source_label(source)
                ok = self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], title, source,
                                          start=position, message=f"Probando otra fuente · {label}", tried=list(tried))
                if ok:
                    return True
                tried.add(source.index)
                meta = {**meta, "tried": sorted(tried)}
                return self._source_failed(meta, position, alive)  # esa tampoco abrió: la siguiente
        self.events.publish({"type": "toast", "ok": False,
                      "message": f"No pude reproducir {title}. Prueba otra fuente desde la ficha (Y)."})
        return False

    def _player_sources(self, meta: dict) -> list[dict]:
        """Pestaña Fuentes del reproductor: TODAS las del título, las mejores primero y la actual marcada
        (antes solo las 12 primeras: con la serie en inglés, las de español no salían)."""
        if meta.get("source") is None:
            return []
        found = self.stream_sources(meta["kind"], meta["video_id"], self.language_for(meta["meta_id"])[0])
        return [{"id": s.index, **player_source_row(s), "current": s.index == meta["source"]} for s in found]

    def _switch_source(self, meta: dict, index: int, position: float) -> bool:
        """False si no se pudo (el reproductor lo avisa). Una fuente de un solo idioma distinto (la de
        español en una serie que estaba en inglés): la serie lo recuerda para los siguientes episodios."""
        prefs = self.language_for(meta["meta_id"])[0]
        source = self.streams.get(meta["kind"], meta["video_id"], prefs, index)
        if source is None:
            return False
        ok = self._load_in_player(meta["kind"], meta["meta_id"], meta["video_id"], meta.get("title") or "",
                                  source, start=position, message=f"Cambiando a {source_label(source)}…")
        if ok and len(source.languages) == 1 and source.languages[0] != prefs.audio:
            self._remember_language(meta, "audio", source.languages[0])
        return ok

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
            self.stream_sources("series", next_id, self.language_for(meta["meta_id"])[0])  # que al llegar el momento ya esté buscada
        except stremio_api.StremioError:
            pass
        label, name = self._episode_label(info, next_id)
        return {"label": label, "title": name,
                "play": lambda: self._play_episode(meta["meta_id"], next_id, title, meta.get("binge"), own=bool(meta.get("own")))}

    def _play_episode(self, meta_id: str, video_id: str, title: str, binge: str | None = None,
                      start: float = 0, own: bool = False) -> bool | None:
        """Otro episodio en el mismo reproductor (sin volver a Orbital). False: no cargó; None: ya se avisó. Desde Mi
        media (`own`), de tu carpeta si está."""
        mine = self.onedrive.source("series", video_id) if own and self.onedrive is not None else None
        if mine is not None:
            return self._load_in_player("series", meta_id, video_id, title, mine, start=start, own=True)
        # El idioma que esta serie recuerda (antes: el de Ajustes, y el siguiente episodio salía en otro idioma).
        source = self.best_source("series", video_id, binge, prefs=self.language_for(meta_id)[0])
        if source is None:
            self.player.toast("No encontré dónde ver ese episodio", 4)
            return None
        return self._load_in_player("series", meta_id, video_id, title, source, start=start)

    def _step_episode(self, meta: dict, delta: int) -> bool | None:
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
        return self._play_episode(meta["meta_id"], episodes[i], title, meta.get("binge"),
                                  start=self.resume_position(meta["meta_id"], episodes[i]), own=bool(meta.get("own")))

    def _season_episodes(self, meta: dict) -> list[dict]:
        """Y › Episodios en el reproductor: los de la temporada que estás viendo."""
        try:
            info = self.cinemeta.meta("series", meta["meta_id"])
        except cinemeta.CinemetaError:
            return []
        for season in cinemeta.seasons(info):
            if any(e["id"] == meta["video_id"] for e in season["episodes"]):
                return [{"id": e["id"], "label": f"E{e['episode']} · {e['title']}", "current": e["id"] == meta["video_id"]}
                        for e in season["episodes"]]
        return []

    def _jump_episode(self, meta: dict, video_id: str) -> bool | None:
        """Elegir un episodio desde el reproductor: lo pone donde ibas (o desde el principio)."""
        info = self.cinemeta.meta("series", meta["meta_id"])
        title, _ = self._episode_title(info, meta["meta_id"], video_id)
        # None: _play_episode ya avisó (no hay fuente); False sí es «no pude» y lo avisa el reproductor.
        return self._play_episode(meta["meta_id"], video_id, title, meta.get("binge"),
                                  start=self.resume_position(meta["meta_id"], video_id), own=bool(meta.get("own")))

    @property
    def native_player(self) -> bool:
        """¿Se puede reproducir en el reproductor de Orbital (elegido, instalado y con cuenta)?"""
        return self.config.stremio.player == "orbital" and self.has_addons and player.find_mpv() is not None

    def play_title(self, kind: str, meta_id: str, video_id: str, title: str, audio: str | None = None,
                   wait: float = 0.0, from_start: bool = False) -> str | None:
        """Para la voz: pone algo sin preguntar, con la fuente recomendada. Buscar fuentes tarda
        unos segundos (Alexa corta a los ~8 s), así que se hace en segundo plano.

        `wait`: segundos que se espera a saber si hay fuente, para que Alexa diga lo que pasó («No
        encontré dónde ver…») en vez de «Poniendo…» y luego un aviso que solo se ve en la pantalla.
        Devuelve el problema (texto) si ya se sabe, o None (se está poniendo, o sigue buscando).

        `audio`: idioma pedido ("…en español"). Si ninguna fuente lo trae, se pone la mejor en tu
        idioma de siempre con subtítulos en el pedido, y se avisa."""
        if not self.native_player:
            self.sessions.play_stremio(kind, meta_id, video_id, title)
            return None
        searched = threading.Event()
        problem: list[str] = []
        # Sin idioma pedido: el que recuerda ese título (el mismo con el que se listan sus fuentes).
        prefs = replace(self.stream_prefs, audio=audio) if audio else self.language_for(meta_id)[0]

        def run() -> None:
            try:
                source = self.best_source(kind, video_id, prefs=prefs)
                if source is None:
                    message = self.no_sources_message(kind, video_id)
                    problem.append(message)
                    searched.set()
                    self.events.publish({"type": "toast", "message": message, "ok": False})
                    return
                searched.set()
                subtitles = None
                if audio and audio != self.stream_prefs.audio:
                    if audio in source.languages:
                        subtitles = ""  # lo pediste doblado: sin subtítulos encima
                    else:
                        subtitles = audio
                        name = {"es": "español", "en": "inglés"}.get(audio, audio)
                        self.events.publish({"type": "toast", "tone": "warn", "message": f"No hay audio en {name} para {title}",
                                             "detail": f"Va con subtítulos en {name}"})
                self.play_source(kind, meta_id, video_id, source.index, title, prefs=prefs, subtitles=subtitles, from_start=from_start)
                if audio:  # lo pediste en voz alta: el siguiente episodio y el respaldo siguen igual
                    key = f"stremio:{meta_id}"
                    if audio in source.languages:
                        self.state.set_pref(key, "audio", audio)
                    if subtitles is not None:
                        self.state.set_pref(key, "subtitles", subtitles)
            except Exception as exc:  # noqa: BLE001 - se avisa en pantalla
                log.exception("No pude poner %s", title)
                message = f"No pude poner {title}: {exc}"
                problem.append(message)
                searched.set()
                self.events.publish({"type": "toast", "message": message, "ok": False})

        threading.Thread(target=run, daemon=True, name="play-title").start()
        if wait > 0:
            searched.wait(wait)
        return problem[0] if problem else None

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

    def play_episode_number(self, episode: int, season: int | None = None) -> str | None:
        """«Pon el capítulo 5»: de la serie que se ve (en su temporada si no se dice otra). None: no se ve
        una serie; "": no existe ese episodio."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        videos = [v for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
        if season is None:
            now = next((v for v in videos if v["id"] == current.meta.get("video_id")), None)
            season = now.get("season") if now else 1
        video = next((v for v in videos if v.get("season") == season and v.get("episode") == episode), None)
        if video is None:
            return ""
        title, _ = self._episode_title(info, meta_id, video["id"])
        label, _ = self._episode_label(info, video["id"])
        threading.Thread(target=self._play_episode, args=(meta_id, video["id"], title, current.meta.get("binge")),
                         kwargs={"start": self.resume_position(meta_id, video["id"])}, daemon=True,
                         name="episode-number").start()
        return label or f"el episodio {episode}"

    def play_previous_episode(self) -> str | None:
        """El episodio anterior al que se está viendo; None si no hay (o no es una serie)."""
        current = self.player.current if self.player.playing else None
        if current is None or current.meta.get("kind") != "series":
            return None
        meta_id = current.meta["meta_id"]
        info = self.cinemeta.meta("series", meta_id)
        episodes = [e["id"] for s in cinemeta.seasons(info) if s["season"] != 0 for e in s["episodes"]]
        if current.meta.get("video_id") not in episodes:
            return None
        i = episodes.index(current.meta["video_id"])
        if i == 0:
            return None
        label, _ = self._episode_label(info, episodes[i - 1])
        threading.Thread(target=self._step_episode, args=(current.meta, -1), daemon=True, name="prev-episode").start()
        return label or "el episodio anterior"

    def player_subtitles(self, lang: str) -> bool:
        """Subtítulos en ese idioma: los del video o, si no trae, los de tus addons."""
        if self.player.select_language("sub", lang):
            return True
        current = self.player.current
        if current is None or not self.has_addons:
            return False
        urls = self.streams.subtitles(current.meta["kind"], current.meta["video_id"], lang)
        if urls:
            self.player.add_subtitles(urls[0], lang)
        return bool(urls)

    def title_details(self, kind: str, meta_id: str) -> dict:
        """Todo para la ficha: datos, reparto, temporadas y dónde ibas (para "Continuar T3 E5")."""
        info = self.cinemeta.meta(kind, meta_id)
        chosen = self.art_for(meta_id)  # «Cambiar el arte»
        details = {"id": meta_id, "kind": kind, "title": info.get("name") or "", "poster": chosen.get("poster") or info.get("poster"),
                   "background": chosen.get("background") or info.get("background") or None, **cinemeta.describe_meta(info),
                   **cinemeta.credits(info)}
        if kind == "series":
            details["seasons"] = cinemeta.seasons(info)
        resume = None
        details["watched"] = []
        details["in_library"] = False
        auth = self.credentials.get(STREMIO_KEY)
        if auth:
            try:
                raw = self.stremio_client.library_item(auth, meta_id)
            except stremio_api.StremioError as exc:
                log.info("No pude leer dónde ibas en %s: %s", meta_id, exc)
                raw = None
            raw = raw if isinstance(raw, dict) else None
            state = stremio_api.state_of(raw)
            details["in_library"] = bool(raw) and not raw.get("removed") and not raw.get("temp")
            if kind == "series":  # los vistos de verdad (no "todo lo anterior al que ibas")
                ids = [v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
                details["watched"] = sorted(stremio_api.parse_watched(state.get("watched"), ids))
            video_id = state.get("video_id") if isinstance(state.get("video_id"), str) else None
            if video_id:
                position = stremio_api.resume_seconds(raw, video_id)
                duration = stremio_api.as_int(state.get("duration")) / 1000
                label, name = self._episode_label(info, video_id) if kind == "series" else ("", "")
                if position or (kind == "series" and video_id != meta_id):
                    resume = {"video_id": video_id, "position": position, "duration": duration,
                              "label": label, "episode_title": name}
        details["resume"] = resume
        video = trailer_id(info)
        details["trailer"] = video if video and self.trailer_available(video) else None  # «Tráiler» solo si se puede ver
        return details

    # --- «Cambiar el arte» de una película o serie ---------------------------------------------------------------------
    ART_KINDS = ("poster", "background")

    def art_choices(self, kind: str, meta_id: str) -> dict:
        """Los pósters y fondos que se pueden elegir (de TMDB) y los que tiene ahora. LookupError en palabras si no hay."""
        tmdb = self.localizer.tmdb
        if not tmdb.configured:
            raise LookupError("Para elegir otro arte hace falta la clave de TMDB (Ajustes › Cuentas).")
        try:
            tmdb_id = tmdb.find_id(meta_id, kind)
            found = tmdb.images(kind, tmdb_id) if tmdb_id else {"posters": [], "backgrounds": []}
        except tmdb_api.TmdbError as exc:
            raise LookupError(str(exc)) from exc
        if not found["posters"] and not found["backgrounds"]:
            raise LookupError("TMDB no tiene otras imágenes de este título.")
        return {**found, "current": self.art_for(meta_id)}

    def art_for(self, meta_id: str | None) -> dict:
        """El arte que elegiste para ese título ({"poster", "background"}); {} si nunca lo cambiaste."""
        saved = self.state.prefs(f"stremio:{meta_id}").get("art") if meta_id else None
        return {k: v for k, v in (saved or {}).items() if k in self.ART_KINDS and isinstance(v, str) and v} if isinstance(saved, dict) else {}

    def set_art(self, meta_id: str, which: str, url: str | None) -> dict:
        """Recuerda el póster o el fondo elegido (`url` None: vuelve el de siempre). Devuelve el arte de ese título."""
        if which not in self.ART_KINDS:
            raise ValueError("Solo se cambia el póster o el fondo")
        if url is not None and not str(url).startswith(tmdb_api.IMAGES):
            raise ValueError("Esa imagen no es de TMDB")
        art = self.art_for(meta_id)
        if url:
            art[which] = url
        else:
            art.pop(which, None)
        self.state.set_pref(f"stremio:{meta_id}", "art", art or None)
        return art

    def set_in_library(self, kind: str, meta_id: str, add: bool) -> None:
        """Añadir o quitar de Mi lista (tu biblioteca de Stremio: se ve igual en Stremio)."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        try:
            info = self.cinemeta.meta(kind, meta_id, localized=False)  # Stremio guarda el título original
        except cinemeta.CinemetaError:
            info = {}
        raw = self.stremio_client.library_item(auth, meta_id)
        item = stremio_api.library_toggled(raw, meta_id=meta_id, kind=kind, name=info.get("name") or meta_id,
                                           poster=info.get("poster"), add=add, now=time.time())
        self.stremio_client.save_library_item(auth, item)
        self.refresh_stremio()
        self.events.publish({"type": "library-changed"})

    def play_trailer(self, kind: str, meta_id: str) -> str:
        """El tráiler en YouTube para TV (se maneja con el mando; Home vuelve a Orbital)."""
        video = trailer_id(self.cinemeta.meta(kind, meta_id))
        if not video or not self.trailer_available(video):
            raise LookupError("Este título no tiene tráiler")
        url = f"https://www.youtube.com/tv#/watch?v={video}"
        self.launcher.open_uri(url)
        return url

    def _player_finished(self, meta: dict, position: float, duration: float, watched: float) -> None:
        self._save_progress(meta, position, duration, watched, refresh=True)

    def _safe_remember(self, meta: dict) -> None:
        try:
            self._remember_choice(meta)
        except Exception:  # noqa: BLE001 - recordar la fuente nunca tumba el guardado del avance
            log.exception("No pude recordar la fuente y los subtítulos")

    def resume_choice(self, meta_id: str, video_id: str) -> dict | None:
        """Con qué fuente y qué subtítulos dejaste ese video (para «Continuar»), o None."""
        saved = self.state.prefs(f"stremio:{meta_id}").get("resume")
        return saved if isinstance(saved, dict) and saved.get("video_id") == video_id else None

    def _remember_choice(self, meta: dict) -> None:
        """Junto a «dónde ibas»: la fuente (su huella) y la pista de subtítulos que tenías."""
        if not meta.get("meta_id") or not meta.get("video_id") or meta.get("live"):
            return
        choice = {"video_id": meta["video_id"], "source": meta.get("source_key"), "sub": self.player.current_subtitle(),
                  "audio": self.player.current_audio()}
        if choice != self.state.prefs(f"stremio:{meta['meta_id']}").get("resume"):
            self.state.set_pref(f"stremio:{meta['meta_id']}", "resume", choice)

    def _save_progress(self, meta: dict, position: float, duration: float, watched: float, refresh: bool) -> None:
        """Guarda en tu cuenta de Stremio dónde te quedaste (Seguir viendo, en Orbital y en Stremio).
        Se llama cada minuto, al pausar y al terminar; `watched` son los segundos vistos desde la vez anterior."""
        if position >= 60:  # con qué fuente y subtítulos lo dejaste (para «Continuar»)
            self._safe_remember(meta)
        auth = self.credentials.get(STREMIO_KEY)
        if not auth or (refresh and watched < 20 and position < 60):
            return  # se abrió y cerró sin ver nada: no se toca tu biblioteca
        # Uno a la vez: un guardado de cada minuto que tarda no pisa al final con una posición vieja.
        with self._saving:
            self._save_progress_now(auth, meta, position, duration, watched, refresh)

    def _save_progress_now(self, auth: str, meta: dict, position: float, duration: float, watched: float,
                           refresh: bool) -> None:
        kind, meta_id, video_id = meta["kind"], meta["meta_id"], meta["video_id"]
        try:
            info = self.cinemeta.meta(kind, meta_id, localized=False)  # Stremio guarda el título original
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
            if expired_session(exc):
                self.events.publish({"type": "toast", "ok": False,
                                     "message": "Tu sesión de Stremio caducó: vuelve a conectarla en Ajustes › Cuentas"})
        if refresh:
            self.refresh_stremio(background=True)
