"""Canales de Orbital: series al aire las 24 horas, como un canal de tele (TV en vivo › «Orbital 24/7»).

Ningún servidor transmite nada: el canal es una programación corrida, sin huecos. Los episodios de sus series se
revuelven una vez por vuelta (siempre igual: el orden sale del número de la vuelta) y uno entra en cuanto acaba el otro,
con su duración real (Orbital la aprende la primera vez que lo pone; mientras, un estimado). Al prenderlo, la hora dice
qué episodio va y en qué minuto: entras a media emisión, como en la tele. Al terminar uno sigue lo que va a esa hora; si
pausas más de un minuto, al seguir regresas a lo que va al aire.

Cada episodio se pone con una fuente de tus complementos de Stremio en el doblaje del canal (latino: nunca castellano)
y el reproductor elige esa pista de audio (playback.dub_track). No todos los episodios tienen ese doblaje: en segundo
plano, con calma, Orbital revisa cuáles sí (`Coverage`, guardado en disco) y los que no se quedan fuera del horario; uno
que nadie ha revisado todavía entra, y si al ponerlo no tiene doblaje se salta (y se anota). Un canal no toca «Seguir
viendo» ni Trakt: es la tele de fondo, no lo que estás viendo tú.
"""

from __future__ import annotations

import json
import logging
import random
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote

from . import player
from .library import cinemeta, streams, stremio_api

if TYPE_CHECKING:
    from .catalog import Catalog

log = logging.getLogger(__name__)

CATEGORY = "Orbital 24/7"
EPOCH = 1_767_225_600  # 1 ene 2026: desde aquí corre el horario (todas las teles ven el mismo episodio a la misma hora)
MAX_SOURCES = 3  # fuentes por episodio antes de pasar al siguiente
MAX_SKIPS = 5  # episodios seguidos sin doblaje antes de rendirse (algo más pasa: Internet, los complementos)
SCAN_DELAY = 300.0  # s tras arrancar antes de revisar episodios: que Orbital abra primero
SCAN_EVERY = 15.0  # s entre episodio y episodio al revisar: sin prisa, nunca le quita Internet a lo que ves
RECHECK_OK = 30 * 86400  # un episodio con doblaje se vuelve a revisar al mes
RECHECK_MISSING = 7 * 86400  # uno sin doblaje, a la semana (alguien pudo subirlo)


@dataclass(frozen=True)
class Show:
    meta_id: str  # IMDb de la serie
    seasons: tuple[int, int] | None = None  # de la primera a la última, incluidas; None: todas (sin especiales)


@dataclass(frozen=True)
class SyntheticChannel:
    id: str
    name: str
    shows: tuple[Show, ...]
    tagline: str = ""  # lo que dice la sección cuando no sabe qué va («Pinky y Cerebro, Batman, ThunderCats…»)
    dub: str = "latino"  # streams.Source.dub que se acepta
    slot: int = 1320  # s que se estima que dura un episodio mientras no se sabe lo que dura de verdad
    logo: str | None = None  # dirección de internet (Orbital la baja y la empareja) o un archivo de la interfaz («/img/…»)
    aliases: tuple[str, ...] = ()  # cómo lo pides por voz: «pon el canal de los Simpson» (voice._find_own)

    def public(self) -> dict:
        return {"id": self.id, "name": self.name, "categories": [CATEGORY], "quality": "", "synthetic": True,
                "tagline": self.tagline}


CHANNELS = [
    SyntheticChannel("orbital:simpsons", "Los Simpson 24/7", (Show("tt0096697", (3, 10)),), slot=1350,
                     logo="https://images.metahub.space/logo/medium/tt0096697/img",
                     aliases=("los simpson", "simpson", "los simpsons", "simpsons")),
    # Las de los 90 que sí tienen doblaje latino en los complementos (las de los 60 y 70 casi no: ver la historia del
    # cambio). Gárgolas y ThunderCats solo en parte: la revisión de fondo deja fuera sus episodios sin latino.
    SyntheticChannel("orbital:caricaturas", "Caricaturas de siempre", (
        Show("tt0112123"),  # Pinky y Cerebro
        Show("tt0103359"),  # Batman: La serie animada
        Show("tt0112175"),  # El Hombre Araña (1994)
        Show("tt0108783"),  # Gárgolas
        Show("tt0088631"),  # ThunderCats (1985)
    ), tagline="Pinky y Cerebro, Batman, El Hombre Araña, Gárgolas y ThunderCats", logo="/img/channels/caricaturas.png",
       aliases=("caricaturas", "las caricaturas", "caricaturas de siempre", "caricaturas viejitas", "monitos")),
]


def lineup(info: dict, show: Show) -> list[dict]:
    """Los episodios de una serie (las temporadas elegidas, sin especiales), en orden, con su etiqueta («T5 E3»)."""
    first, last = show.seasons or (1, 10_000)
    series = str(info.get("name") or "")
    return [{**e, "season": s["season"], "label": f"T{s['season']} E{e['episode']}", "meta_id": show.meta_id,
             "series": series, "poster": info.get("poster")}
            for s in cinemeta.seasons(info) if s["season"] > 0 and first <= s["season"] <= last for e in s["episodes"]]


def cycle_order(count: int, channel_id: str, cycle: int) -> list[int]:
    """El orden de una vuelta: revuelto, pero el mismo siempre para esa vuelta (y distinto en la siguiente)."""
    order = list(range(count))
    random.Random(f"{channel_id}:{cycle}").shuffle(order)
    return order


def on_air(lengths: list[float], channel_id: str, now: float) -> tuple[int, int, float]:
    """(vuelta, lugar en la vuelta, segundos ya emitidos del episodio) a esta hora, en una programación corrida:
    `lengths[i]` es lo que dura el episodio i. Una vuelta dura lo que suman todos (el orden no cambia la suma)."""
    total = sum(lengths)
    elapsed = max(0.0, now - EPOCH)
    cycle = int(elapsed // total)
    rest = elapsed - cycle * total
    order = cycle_order(len(lengths), channel_id, cycle)
    for place, index in enumerate(order):
        if rest < lengths[index]:
            return cycle, place, rest
        rest -= lengths[index]
    return cycle, len(order) - 1, lengths[order[-1]]  # redondeo al final de la vuelta


def following(count: int, cycle: int, place: int) -> tuple[int, int]:
    """El lugar que sigue (al acabar la vuelta, la siguiente)."""
    return (cycle + 1, 0) if place + 1 >= count else (cycle, place + 1)


class Coverage:
    """Qué episodios tienen el doblaje del canal: {video_id: [sí/no, cuándo se revisó]}, en disco."""

    def __init__(self, path: Path | None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict[str, list] = {}
        if path is not None:
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
                self._data = {k: v for k, v in raw.items() if isinstance(v, list) and len(v) in (2, 3)} if isinstance(raw, dict) else {}
            except (OSError, ValueError):
                self._data = {}

    def has(self, video_id: str) -> bool | None:
        """True / False según la última revisión; None si nadie lo ha revisado."""
        entry = self._data.get(video_id)
        return bool(entry[0]) if entry else None

    def stale(self, video_id: str, now: float) -> bool:
        entry = self._data.get(video_id)
        if not entry:
            return True
        return now - float(entry[1] or 0) > (RECHECK_OK if entry[0] else RECHECK_MISSING)

    def record(self, video_id: str, ok: bool, now: float | None = None) -> None:
        with self._lock:
            entry = [bool(ok), now if now is not None else time.time()]
            if (old := self._data.get(video_id)) and len(old) == 3:
                entry.append(old[2])  # lo que dura no cambia al volver a revisar
            self._data[video_id] = entry

    def duration(self, video_id: str) -> float | None:
        """Lo que dura de verdad (segundos), si ya se puso alguna vez."""
        entry = self._data.get(video_id)
        return float(entry[2]) if entry and len(entry) == 3 and entry[2] else None

    def record_duration(self, video_id: str, seconds: float) -> None:
        with self._lock:
            entry = self._data.get(video_id) or [True, time.time()]
            self._data[video_id] = [True, entry[1], round(float(seconds), 1)]  # si dura algo, se pudo ver

    def save(self) -> None:
        if self.path is None:
            return
        with self._lock:
            text = json.dumps(self._data, separators=(",", ":"))
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            log.warning("No pude guardar qué episodios tienen doblaje: %s", exc)


class SyntheticTV:
    def __init__(self, catalog: Catalog, channels: list[SyntheticChannel] | None = None, clock=time.time,
                 directory: Path | None = None) -> None:
        self.catalog = catalog
        self.channels = list(CHANNELS if channels is None else channels)
        self.clock = clock
        self.coverage = Coverage(directory / "tv-orbital.json" if directory else None)
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def channel(self, channel_id: str) -> SyntheticChannel | None:
        return next((c for c in self.channels if c.id == channel_id), None)

    def all_episodes(self, channel: SyntheticChannel) -> list[dict]:
        """Todos los episodios de sus series (una serie que Cinemeta no da se queda fuera; si ninguna, CinemetaError)."""
        out: list[dict] = []
        error: cinemeta.CinemetaError | None = None
        for show in channel.shows:
            try:
                out += lineup(self.catalog.watch.cinemeta.meta("series", show.meta_id), show)
            except cinemeta.CinemetaError as exc:
                error = exc
        if not out and error is not None:
            raise error
        return out

    def _episodes(self, channel: SyntheticChannel) -> list[dict]:
        """Los del horario: TODOS (antes se quitaban los sin doblaje y, cada vez que la revisión de fondo quitaba unos, el
        horario entero se recorría: volvía a salir el mismo episodio). Los sin doblaje se saltan al ponerlos."""
        return self.all_episodes(channel)

    def _airable(self, channel: SyntheticChannel, episodes: list[dict], cycle: int, place: int) -> tuple[int, int]:
        """Desde ese lugar, el primero que no se sabe sin doblaje (sin preguntarle a nadie: lo que ya revisó la de fondo)."""
        for _ in range(2 * len(episodes)):  # puede cruzar a la vuelta siguiente (otro orden)
            if self.coverage.has(self._at(channel, episodes, cycle, place)["id"]) is not False:
                return cycle, place
            cycle, place = following(len(episodes), cycle, place)
        return cycle, place

    def _at(self, channel: SyntheticChannel, episodes: list[dict], cycle: int, place: int) -> dict:
        return episodes[cycle_order(len(episodes), channel.id, cycle)[place % len(episodes)]]

    def _length(self, channel: SyntheticChannel, episode: dict) -> float:
        return self.coverage.duration(episode["id"]) or float(channel.slot)

    def _on_air(self, channel: SyntheticChannel, episodes: list[dict], now: float) -> tuple[int, int, float]:
        return on_air([self._length(channel, e) for e in episodes], channel.id, now)

    def now(self, channel: SyntheticChannel) -> dict | None:
        """Lo que va ahora (para la sección): episodio, imagen y a qué hora termina. None si Cinemeta no responde."""
        try:
            episodes = self._episodes(channel)
        except cinemeta.CinemetaError:
            return None
        if not episodes:
            return None
        now = self.clock()
        cycle, place, offset = self._on_air(channel, episodes, now)
        airable = self._airable(channel, episodes, cycle, place)
        if airable != (cycle, place):  # lo de esta hora no tiene doblaje: va el siguiente, desde el principio
            cycle, place, offset = *airable, 0.0
        episode = self._at(channel, episodes, cycle, place)
        ends = now - offset + self._length(channel, episode)
        upcoming = self._at(channel, episodes, *self._airable(channel, episodes, *following(len(episodes), cycle, place)))
        many = len(channel.shows) > 1
        return {"series": episode["series"] if many else "", "label": episode["label"], "title": episode["title"],
                "still": episode.get("thumbnail"), "ends": ends,
                # «A continuación», con su hora (la sección: «6:22 p. m. · T7 E17 · Homero Smithers»)
                "next": {"series": upcoming["series"] if many else "", "label": upcoming["label"],
                         "title": upcoming["title"], "starts": ends}}

    def describe(self, channel: SyntheticChannel) -> dict:
        logo = channel.logo if (channel.logo or "").startswith("/") else \
            f"/api/tv/logo?id={quote(channel.id, safe='')}" if channel.logo else None
        return {**channel.public(), "logo": logo, "number": None, "verified": True, "now": self.now(channel)}

    def remote_logo(self, channel_id: str) -> str | None:
        """La dirección de internet del logo (la baja y empareja la TV); None si es un archivo de la interfaz."""
        channel = self.channel(channel_id)
        return channel.logo if channel and channel.logo and not channel.logo.startswith("/") else None

    # --- qué episodios tienen el doblaje (en segundo plano) ---------------------------------------------------------
    def start(self) -> None:
        """Revisa con calma, episodio por episodio. Solo lo llama el arranque de verdad."""
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._scan_loop, daemon=True, name="tv-orbital")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _scan_loop(self) -> None:
        if self._stop.wait(SCAN_DELAY):
            return
        while not self._stop.is_set():
            checked = self.scan(limit=40)
            if self._stop.wait(SCAN_EVERY if checked else 6 * 3600):  # todo al día: se vuelve a ver en unas horas
                return

    def scan(self, limit: int = 40) -> int:
        """Revisa hasta `limit` episodios que nadie ha revisado (o hace mucho), uno cada SCAN_EVERY s. Cuántos revisó."""
        checked = 0
        for channel in self.channels:
            try:
                episodes = self.all_episodes(channel)
            except cinemeta.CinemetaError:
                continue
            for episode in episodes:
                if checked >= limit or self._stop.is_set():
                    break
                if not self.coverage.stale(episode["id"], self.clock()):
                    continue
                try:
                    found = bool(self.sources(channel, episode["id"]))
                except stremio_api.StremioError:
                    return checked  # sin complementos o sin cuenta: ya se revisará
                self.coverage.record(episode["id"], found, self.clock())
                checked += 1
                if checked % 10 == 0:
                    self.coverage.save()
                if self._stop.wait(SCAN_EVERY):
                    break
        if checked:
            self.coverage.save()
            log.info("Canales de Orbital: revisé %d episodios", checked)
        return checked

    # --- ponerlo en pantalla -------------------------------------------------------------------------------------
    def sources(self, channel: SyntheticChannel, video_id: str, skip: set[int] | None = None) -> list[streams.Source]:
        """Las fuentes en el doblaje del canal, las mejores primero: primero las que lo dicen; luego las de español sin
        decir cuál (el reproductor revisa la pista). Nunca las del otro doblaje."""
        watch = self.catalog.watch
        prefs = streams.Preferences(audio="es", quality=watch.stream_prefs.quality)
        found = [s for s in watch.stream_sources("series", video_id, prefs)
                 if s.index not in (skip or set()) and player.stream_url(s.stream) and "es" in s.languages
                 and not {"CAM", "Tráiler"} & set(s.tags)]
        return [s for s in found if s.dub == channel.dub] + [s for s in found if not s.dub]

    def _meta(self, channel: SyntheticChannel, episode: dict, cycle: int, place: int,
              source: streams.Source, tried: list[int], skips: int = 0) -> dict:
        detail = f"{episode['label']} · {episode['title']}"
        if len(channel.shows) > 1:
            detail = f"{episode['series']} · {detail}"  # en un canal de varias series, cuál es
        return {"kind": "channel", "synthetic": True, "channel_id": channel.id, "title": channel.name,
                "meta_id": episode["meta_id"], "video_id": episode["id"], "series": episode["series"],
                "detail": detail, "dub": channel.dub, "description": episode.get("overview") or "",
                "poster": episode.get("poster"), "still": episode.get("thumbnail"), "cycle": cycle, "place": place,
                "tried": tried,
                "source_label": "Latino" if channel.dub == "latino" else "", "binge": source.binge,
                "source_key": source.key,
                "skips": skips}  # episodios seguidos que no abrieron: con MAX_SKIPS se rinde

    def _pick(self, channel: SyntheticChannel, cycle: int, place: int, skip: set[int] | None = None,
              skips: int = 0) -> tuple[dict, streams.Source, int, int] | None:
        """(episodio, fuente, vuelta, lugar) del primer episodio desde ese lugar que tenga el doblaje."""
        episodes = self._episodes(channel)
        if not episodes:
            return None
        for _ in range(MAX_SKIPS - skips):
            cycle, place = self._airable(channel, episodes, cycle, place)  # los que ya se sabe que no: sin preguntar
            episode = self._at(channel, episodes, cycle, place)
            found = self.sources(channel, episode["id"], skip)
            if not skip:
                self.coverage.record(episode["id"], bool(found), self.clock())  # lo que se vio al ponerlo también cuenta
            if found:
                return episode, found[0], cycle, place
            log.info("%s: %s no tiene doblaje %s, sigue el siguiente", channel.name, episode["label"], channel.dub)
            skip = None
            cycle, place = following(len(episodes), cycle, place)
        return None

    def play(self, channel_id: str, *, keep: bool = False) -> dict:
        """Prende el canal en lo que va a esta hora. LookupError si no se puede (sin doblaje, sin complementos…)."""
        channel = self.channel(channel_id)
        if channel is None:
            raise LookupError("Ese canal ya no está disponible.")
        catalog = self.catalog
        watch, sessions = catalog.watch, catalog.sessions
        mpv_exe = player.find_mpv()
        if not mpv_exe:
            raise LookupError("No encuentro mpv, el reproductor de Orbital. Instálalo desde Ajustes o revisa tu instalación.")
        try:
            episodes = self._episodes(channel)
            if not episodes:
                raise LookupError(f"No encontré los episodios de {channel.name}.")
            cycle, place, offset = self._on_air(channel, episodes, self.clock())
            picked = self._pick(channel, cycle, place)
        except (cinemeta.CinemetaError, stremio_api.StremioError) as exc:
            raise LookupError(f"No pude prender {channel.name}: {exc}") from exc
        finally:
            self.coverage.save()
        if picked is None:
            raise LookupError(f"No encontré {channel.name} en español latino en tus complementos de Stremio.")
        episode, source, picked_cycle, picked_place = picked
        start = offset if (picked_cycle, picked_place) == (cycle, place) else 0.0  # se saltó uno: el siguiente desde el principio
        meta = self._meta(channel, episode, picked_cycle, picked_place, source, [source.index])
        if sessions.before_launch and not keep:
            sessions.before_launch("media:player")
        watch._wire_player()  # lo de siempre (siguiente episodio, fuentes, iPhone…), para «Seguir solo este capítulo»
        self.wire(watch.player)
        pinned = sessions.pin()
        try:
            watch.player.play(
                catalog.launcher.run, mpv_exe, player.stream_url(source.stream) or "", channel.name, meta,
                start=start, audio="es", subtitles="",
                started=lambda process: catalog.launcher.track("media:player", channel.name, process, runner="Reproductor"))
        except BaseException:
            sessions.unpin(pinned)
            raise
        sessions.revealing = sessions.to_front("media:player", channel.name, pinned=pinned, timeout=player.STARTUP_TIMEOUT + 5,
                                               ready=lambda: bool(watch.player.segment and watch.player.segment.playing))
        log.info("%s al aire: %s (desde %d s)", channel.name, meta["detail"], int(start))
        return {"ok": True, "reveal": sessions.revealing}

    def wire(self, p) -> None:
        p.on_detached = self.detached
        p.on_synthetic_end = self.ended
        p.on_synthetic_failed = self.failed
        p.on_synthetic_resync = self.resync
        p.on_synthetic_duration = self.learned

    def detached(self, meta: dict) -> None:
        """«Seguir solo este capítulo»: la barra de arriba de Orbital dice el episodio, no el canal."""
        running = getattr(self.catalog.launcher, "current", None)
        if running is not None and getattr(running, "item_id", "") == "media:player":
            running.title = meta.get("title") or running.title

    def learned(self, meta: dict, seconds: float) -> None:
        """Lo que dura de verdad el episodio que se está viendo: la programación lo usa desde ya."""
        if meta.get("video_id") and 60 < seconds < 6 * 3600:
            self.coverage.record_duration(meta["video_id"], seconds)
            self.coverage.save()

    def _load(self, channel: SyntheticChannel, picked, tried: list[int], message: str, skips: int = 0,
              start: float = 0) -> bool:
        episode, source, cycle, place = picked
        meta = self._meta(channel, episode, cycle, place, source, tried, skips)
        return self.catalog.watch.player.load(player.stream_url(source.stream) or "", channel.name, meta,
                                              start=start if start > 10 else 0, audio="es", subtitles="", message=message)

    def _back_on_air(self, meta: dict, why: str) -> bool:
        """Lo que va al aire a esta hora, en su minuto (al terminar un episodio, o al seguir tras una pausa larga). Si lo
        que va es lo mismo que se acaba de ver (duraba menos de lo estimado), el siguiente desde el principio."""
        channel = self.channel(meta.get("channel_id") or "")
        if channel is None:
            return False
        try:
            episodes = self._episodes(channel)
            if not episodes:
                return False
            cycle, place, offset = self._on_air(channel, episodes, self.clock())
            if why == "ended" and self._at(channel, episodes, cycle, place)["id"] == meta.get("video_id"):
                (cycle, place), offset = following(len(episodes), cycle, place), 0.0
            picked = self._pick(channel, cycle, place)
        except (cinemeta.CinemetaError, stremio_api.StremioError) as exc:
            log.warning("%s: no pude seguir con lo que va al aire: %s", channel.name, exc)
            return False
        finally:
            self.coverage.save()
        if picked is None:
            return False
        start = offset if (picked[2], picked[3]) == (cycle, place) else 0.0
        return self._load(channel, picked, [picked[1].index], f"{channel.name} · {picked[0]['label']}", start=start)

    def ended(self, meta: dict) -> bool:
        """Terminó un episodio: lo que va a esta hora (en una programación corrida, el siguiente)."""
        return self._back_on_air(meta, "ended")

    def resync(self, meta: dict) -> bool:
        """Pausaste un rato: al seguir, lo que va al aire ahora (como la tele en vivo)."""
        return self._back_on_air(meta, "resync")

    def failed(self, meta: dict) -> bool:
        """La fuente no abrió, se cortó o no traía el doblaje: otra del mismo episodio; si no hay, el siguiente."""
        channel = self.channel(meta.get("channel_id") or "")
        if channel is None:
            return False
        tried = set(meta.get("tried") or [])
        skips = int(meta.get("skips") or 0)
        try:
            cycle, place = int(meta["cycle"]), int(meta["place"])
            picked = self._pick(channel, cycle, place, skip=tried, skips=skips) if len(tried) < MAX_SOURCES else None
            if picked is not None and (picked[2], picked[3]) != (cycle, place):
                tried, skips = set(), skips + 1  # ya es otro episodio
            episodes = self._episodes(channel)
            if picked is None and skips + 1 < MAX_SKIPS:
                picked = self._pick(channel, *following(len(episodes), cycle, place), skips=skips + 1)
                tried, skips = set(), skips + 1
            # La otra fuente entra en el minuto que va al aire, no desde el principio: al prender el canal, la primera
            # fuente a veces no trae el latino y la de respaldo empezaba el episodio de cero (dejaba de ser «en vivo»).
            on_cycle, on_place, offset = self._on_air(channel, episodes, self.clock()) if episodes else (-1, -1, 0.0)
            start = offset if picked is not None and (picked[2], picked[3]) == (on_cycle, on_place) else 0.0
        except (cinemeta.CinemetaError, stremio_api.StremioError, KeyError, ValueError) as exc:
            log.warning("%s: no pude cambiar de fuente: %s", channel.name, exc)
            return False
        finally:
            self.coverage.save()
        if picked is None or skips >= MAX_SKIPS:
            return False  # varios episodios seguidos sin abrir: algo más pasa (Internet, los complementos)
        return self._load(channel, picked, sorted(tried | {picked[1].index}), f"{channel.name} · probando otra fuente", skips,
                          start=start)
