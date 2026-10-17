"""Canales de Orbital: una serie al aire las 24 horas, como un canal de tele (TV en vivo › «Orbital 24/7»).

Ningún servidor transmite nada: el canal es un horario. Los episodios de las temporadas elegidas se revuelven una vez por
vuelta (siempre igual: el orden sale del número de la vuelta) y cada uno ocupa un espacio fijo desde una fecha de
arranque. Al prenderlo, la hora dice qué episodio va y en qué minuto: entras a media emisión, como en la tele. Al terminar
un episodio sigue el siguiente de la vuelta, en el mismo reproductor.

Cada episodio se pone con una fuente de tus complementos de Stremio en el doblaje del canal (latino: nunca castellano)
y el reproductor elige esa pista de audio (playback.dub_track). Si un episodio no tiene ese doblaje, se salta. Un canal
no toca «Seguir viendo» ni Trakt: es la tele de fondo, no lo que estás viendo tú.
"""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass
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


@dataclass(frozen=True)
class SyntheticChannel:
    id: str
    name: str
    meta_id: str  # IMDb de la serie
    seasons: tuple[int, int]  # de la primera a la última, incluidas
    dub: str = "latino"  # streams.Source.dub que se acepta
    slot: int = 1320  # s por episodio en el horario: menos que el más corto, para no entrar después del final
    logo: str | None = None

    def public(self) -> dict:
        return {"id": self.id, "name": self.name, "logo": self.logo, "categories": [CATEGORY], "quality": "",
                "synthetic": True}


CHANNELS = [
    SyntheticChannel("orbital:simpsons", "Los Simpson 24/7", "tt0096697", (3, 10),
                     logo="https://images.metahub.space/logo/medium/tt0096697/img"),
]


def lineup(info: dict, seasons: tuple[int, int]) -> list[dict]:
    """Los episodios de esas temporadas, en orden, con su etiqueta («T5 E3»)."""
    first, last = seasons
    return [{**e, "season": s["season"], "label": f"T{s['season']} E{e['episode']}"}
            for s in cinemeta.seasons(info) if first <= s["season"] <= last for e in s["episodes"]]


def cycle_order(count: int, channel_id: str, cycle: int) -> list[int]:
    """El orden de una vuelta: revuelto, pero el mismo siempre para esa vuelta (y distinto en la siguiente)."""
    order = list(range(count))
    random.Random(f"{channel_id}:{cycle}").shuffle(order)
    return order


def on_air(count: int, channel: SyntheticChannel, now: float) -> tuple[int, int, float]:
    """(vuelta, lugar en la vuelta, segundos ya emitidos del episodio) a esta hora."""
    slots = int((now - EPOCH) // channel.slot)
    return slots // count, slots % count, (now - EPOCH) % channel.slot


def following(count: int, cycle: int, place: int) -> tuple[int, int]:
    """El lugar que sigue (al acabar la vuelta, la siguiente)."""
    return (cycle + 1, 0) if place + 1 >= count else (cycle, place + 1)


class SyntheticTV:
    def __init__(self, catalog: Catalog, channels: list[SyntheticChannel] | None = None, clock=time.time) -> None:
        self.catalog = catalog
        self.channels = list(CHANNELS if channels is None else channels)
        self.clock = clock

    def channel(self, channel_id: str) -> SyntheticChannel | None:
        return next((c for c in self.channels if c.id == channel_id), None)

    def _episodes(self, channel: SyntheticChannel) -> list[dict]:
        return lineup(self.catalog.watch.cinemeta.meta("series", channel.meta_id), channel.seasons)

    def _at(self, channel: SyntheticChannel, episodes: list[dict], cycle: int, place: int) -> dict:
        return episodes[cycle_order(len(episodes), channel.id, cycle)[place]]

    def now(self, channel: SyntheticChannel) -> dict | None:
        """Lo que va ahora (para la sección): episodio, imagen y a qué hora termina. None si Cinemeta no responde."""
        try:
            episodes = self._episodes(channel)
        except cinemeta.CinemetaError:
            return None
        if not episodes:
            return None
        now = self.clock()
        cycle, place, offset = on_air(len(episodes), channel, now)
        episode = self._at(channel, episodes, cycle, place)
        return {"label": episode["label"], "title": episode["title"], "still": episode.get("thumbnail"),
                "ends": now - offset + channel.slot}

    def describe(self, channel: SyntheticChannel) -> dict:
        logo = f"/api/tv/logo?id={quote(channel.id, safe='')}" if channel.logo else None
        return {**channel.public(), "logo": logo, "number": None, "verified": True, "now": self.now(channel)}

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

    def _meta(self, channel: SyntheticChannel, info: dict, episode: dict, cycle: int, place: int,
              source: streams.Source, tried: list[int], skips: int = 0) -> dict:
        series = info.get("name") or channel.name
        return {"kind": "channel", "synthetic": True, "channel_id": channel.id, "title": channel.name,
                "meta_id": channel.meta_id, "video_id": episode["id"], "series": series,
                "detail": f"{episode['label']} · {episode['title']}", "dub": channel.dub,
                "description": episode.get("overview") or "", "poster": info.get("poster"),
                "cycle": cycle, "place": place, "tried": tried, "source_label": "Latino" if channel.dub == "latino" else "",
                "skips": skips}  # episodios seguidos que no abrieron: con MAX_SKIPS se rinde

    def _pick(self, channel: SyntheticChannel, cycle: int, place: int, skip: set[int] | None = None,
              skips: int = 0) -> tuple[dict, dict, streams.Source, int, int] | None:
        """(ficha, episodio, fuente, vuelta, lugar) del primer episodio desde ese lugar que tenga el doblaje."""
        info = self.catalog.watch.cinemeta.meta("series", channel.meta_id)
        episodes = lineup(info, channel.seasons)
        if not episodes:
            return None
        for _ in range(MAX_SKIPS - skips):
            episode = self._at(channel, episodes, cycle, place)
            found = self.sources(channel, episode["id"], skip)
            if found:
                return info, episode, found[0], cycle, place
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
            info = watch.cinemeta.meta("series", channel.meta_id)
            episodes = lineup(info, channel.seasons)
            if not episodes:
                raise LookupError(f"No encontré los episodios de {channel.name}.")
            cycle, place, offset = on_air(len(episodes), channel, self.clock())
            picked = self._pick(channel, cycle, place)
        except (cinemeta.CinemetaError, stremio_api.StremioError) as exc:
            raise LookupError(f"No pude prender {channel.name}: {exc}") from exc
        if picked is None:
            raise LookupError(f"No encontré {channel.name} en español latino en tus complementos de Stremio.")
        info, episode, source, picked_cycle, picked_place = picked
        start = offset if (picked_cycle, picked_place) == (cycle, place) else 0.0  # se saltó uno: el siguiente desde el principio
        meta = self._meta(channel, info, episode, picked_cycle, picked_place, source, [source.index])
        if sessions.before_launch and not keep:
            sessions.before_launch("media:player")
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
        log.info("%s al aire: %s (%s, desde %d s)", channel.name, meta["detail"], streams.LANG_NAMES.get("es"), int(start))
        return {"ok": True, "reveal": sessions.revealing}

    def wire(self, p) -> None:
        p.on_synthetic_end = self.ended
        p.on_synthetic_failed = self.failed

    def _load(self, channel: SyntheticChannel, picked, tried: list[int], message: str, skips: int = 0) -> bool:
        info, episode, source, cycle, place = picked
        meta = self._meta(channel, info, episode, cycle, place, source, tried, skips)
        return self.catalog.watch.player.load(player.stream_url(source.stream) or "", channel.name, meta, start=0,
                                              audio="es", subtitles="", message=message)

    def ended(self, meta: dict) -> bool:
        """Terminó un episodio: el siguiente de la vuelta, en el mismo reproductor."""
        channel = self.channel(meta.get("channel_id") or "")
        if channel is None:
            return False
        try:
            count = len(self._episodes(channel))
            picked = self._pick(channel, *following(count, int(meta["cycle"]), int(meta["place"])))
        except (cinemeta.CinemetaError, stremio_api.StremioError, KeyError, ValueError) as exc:
            log.warning("%s: no pude seguir con el siguiente episodio: %s", channel.name, exc)
            return False
        if picked is None:
            return False
        return self._load(channel, picked, [picked[2].index], f"{channel.name} · {picked[1]['label']}")

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
            if picked is not None and (picked[3], picked[4]) != (cycle, place):
                tried, skips = set(), skips + 1  # ya es otro episodio
            if picked is None and skips + 1 < MAX_SKIPS:
                count = len(self._episodes(channel))
                picked = self._pick(channel, *following(count, cycle, place), skips=skips + 1)
                tried, skips = set(), skips + 1
        except (cinemeta.CinemetaError, stremio_api.StremioError, KeyError, ValueError) as exc:
            log.warning("%s: no pude cambiar de fuente: %s", channel.name, exc)
            return False
        if picked is None or skips >= MAX_SKIPS:
            return False  # varios episodios seguidos sin abrir: algo más pasa (Internet, los complementos)
        return self._load(channel, picked, sorted(tried | {picked[2].index}), f"{channel.name} · probando otra fuente", skips)
