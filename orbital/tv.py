"""TV en vivo: los canales de México (iptv-org), su salud y ponerlos en el reproductor.

Junta tres piezas que no se conocen entre sí:

  * library/iptv.py        — leer la lista M3U, traducir las categorías, guardar una copia en disco
  * library/iptv_health.py — ¿abre de verdad cada canal? (manifiesto, variante y un segmento), 2 fallos para ocultarlo
  * player.py              — mpv en modo en vivo (cambio de canal en el mismo mpv)

La lista se baja y se revisa en segundo plano al arrancar y cada ~6 h; nada de eso toca a quien está viendo
la tele. Un canal sin verificar se muestra (para que la sección no salga vacía); uno oculto vuelve solo si
una revisión posterior lo encuentra bien. Si un canal falla al abrirlo, se marca y se pasa al siguiente.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from collections import Counter
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote

from . import player, synthetic, system
from .library import iptv, iptv_health, iptv_logos
from .library.iptv import OTHER, Channel

if TYPE_CHECKING:
    from .catalog import Catalog
    from .config import Config

log = logging.getLogger(__name__)

ALL = "todos"  # la «categoría» que junta todo
MIN_CATEGORY = 3  # una categoría con menos canales que esto se junta con «Otros» (no hay pestañas de un solo canal)
START_DELAY = 20.0  # s tras arrancar antes de revisar canales: que Orbital abra primero
MAX_SKIPS = 3  # canales seguidos que se saltan solos; más es que pasa otra cosa (el Internet, sobre todo)


def cache_dir(config: Config) -> Path | None:
    """Junto a las demás cachés de Orbital (no en pruebas: sin config.yaml no se guarda nada)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "cache" if config.source else None


class LiveTV:
    def __init__(self, config: Config, catalog: Catalog | None = None, *, directory: Path | None = None,
                 download_fn: Callable[[], str] | None = None, fetch_fn: Callable | None = None,
                 online: Callable[[], bool] | None = None) -> None:
        self.config = config
        self.catalog = catalog
        directory = directory if directory is not None else cache_dir(config)
        self._copy = directory / "tv-mx.m3u" if directory else None
        self.store = iptv_health.HealthStore(directory / "tv-health.json" if directory else None)
        self.logos = iptv_logos.LogoCache(directory / "tv-logos" if directory else None)
        # Se buscan al llamar (no al definir): las pruebas cambian iptv.download, iptv_health.fetch y system.online
        # por funciones que no salen a Internet.
        self._download_fn = download_fn or (lambda: iptv.download())
        self._fetch_fn = fetch_fn or (lambda *args, **kwargs: iptv_health.fetch(*args, **kwargs))
        self._online = online or (lambda: system.online())
        self._channels: list[Channel] = []
        self.checking = False  # revisando la lista ahora mismo
        self.offline = False  # la última descarga de la lista falló (se usa la copia en disco)
        self.updated: float | None = None  # cuándo se revisó la lista por última vez
        self._asked = 0.0  # la última vez que la interfaz pidió una lista vacía y se salió a buscarla
        self._refreshing = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self.set_channels(iptv.read_copy(self._copy))
        # Los canales de Orbital (una serie al aire todo el día): sin lista ni salud, van primero.
        self.synthetic = synthetic.SyntheticTV(catalog) if catalog is not None else None

    # --- la lista ------------------------------------------------------------------------------
    def set_channels(self, channels: list[Channel]) -> None:
        """Los canales que hay (la copia en disco al arrancar, la lista nueva después). Cada uno conserva su número."""
        self._channels = sorted(channels, key=lambda c: iptv.fold(c.name))
        self.store.assign_numbers(self._channels)
        self.store.save()

    def channel(self, channel_id: str) -> Channel | None:
        return next((c for c in self.visible() if c.id == channel_id), None)

    def visible(self) -> list[Channel]:
        """Los que se muestran: los que abren y los que nadie ha revisado todavía; en el orden de su número."""
        shown = [c for c in self._channels if not self.store.hidden(c.id)]
        return sorted(shown, key=lambda c: self.store.number(c.id) or 0)

    def _categories(self, channels: list[Channel]) -> dict[str, list[str]]:
        """Para cada canal, sus categorías ya sin las de un solo canal (esas pasan a «Otros»)."""
        count = Counter(cat for c in channels for cat in c.categories)
        big = {cat for cat, n in count.items() if n >= MIN_CATEGORY}
        out = {}
        for c in channels:
            mine = [cat for cat in c.categories if cat in big]
            out[c.id] = mine or [OTHER]
        return out

    def describe(self, channel: Channel, categories: list[str]) -> dict:
        # El logo lo sirve Orbital (parejo y guardado en disco), no la dirección de internet de la lista.
        logo = f"/api/tv/logo?id={quote(channel.id, safe='')}" if channel.logo else None
        return {**channel.public(), "logo": logo, "categories": categories, "number": self.store.number(channel.id),
                "verified": self.store.verified(channel.id)}

    def logo_path(self, channel_id: str) -> Path | None:
        """El archivo del logo de un canal (se baja la primera vez). None si no tiene o no se pudo."""
        channel = next((c for c in self._channels if c.id == channel_id), None) or             (self.synthetic.channel(channel_id) if self.synthetic else None)
        return self.logos.get(channel.logo) if channel is not None else None

    def playing(self) -> str | None:
        """El canal que está al aire ahora (en el reproductor), si lo hay."""
        player_ = getattr(self.catalog.watch, "player", None) if self.catalog is not None else None
        segment = getattr(player_, "segment", None)
        if player_ is None or not getattr(player_, "playing", False) or segment is None:
            return None
        if not segment.live and not segment.meta.get("synthetic"):
            return None
        return segment.meta.get("channel_id")

    def overview(self, own: bool = True) -> dict:
        """Lo que pinta la interfaz: pestañas de categoría y los canales, con su número. `own=False`: sin los canales de
        Orbital (la guía del reproductor: ▲▼ salta solo entre los de la lista)."""
        visible = self.visible()
        mapped = self._categories(visible)
        count = Counter(cat for cats in mapped.values() for cat in cats)
        ours = [self.synthetic.describe(c) for c in self.synthetic.channels] if self.synthetic and own else []
        categories = [{"id": ALL, "title": "Todos", "count": len(visible) + len(ours)}] +             ([{"id": iptv.slug(synthetic.CATEGORY), "title": synthetic.CATEGORY, "count": len(ours)}] if ours else []) + [
            {"id": iptv.slug(title), "title": title, "count": count[title]}
            for title in sorted(count, key=iptv.category_sort_key)]
        if not self._channels and self._thread is not None and not self.checking and time.monotonic() - self._asked > 60:
            self._asked = time.monotonic()
            self.refresh(background=True)  # sin copia en disco: no esperar a los 20 s del arranque
        # Los que ya fallaron una vez, al final de su lista: lo primero que se ve son canales que abren.
        shown = sorted(visible, key=lambda c: self.store.verified(c.id) is False)
        return {"categories": categories, "channels": ours + [self.describe(c, mapped[c.id]) for c in shown],
                "checking": self.checking, "offline": self.offline, "updated": self.updated, "playing": self.playing(),
                # «Tus canales»: los últimos que viste (solo los que siguen en la lista).
                "recent": [cid for cid in self.store.recent() if cid in {c.id for c in visible}],
                "total": len(self._channels), "hidden": len(self._channels) - len(visible)}

    def zap_list(self, category: str | None) -> tuple[str, list[Channel]]:
        """(id de la categoría, sus canales): la lista por la que se salta con ▲▼. Una categoría que ya no existe: todos."""
        visible = self.visible()
        mapped = self._categories(visible)
        for title in {cat for cats in mapped.values() for cat in cats}:
            if category and iptv.slug(title) == category:
                return category, [c for c in visible if title in mapped[c.id]]
        return ALL, visible

    # --- revisar en segundo plano -----------------------------------------------------------------
    def refresh(self, background: bool = False) -> bool:
        """Baja la lista y revisa cada canal. Una a la vez. False si ya había una revisión en curso."""
        if background:
            threading.Thread(target=self.refresh, daemon=True, name="tv-refresh").start()
            return True
        if not self._refreshing.acquire(blocking=False):
            return False
        self.checking = True
        try:
            channels, fresh = iptv.fetch_list(self._copy, download_fn=self._download_fn)
            self.offline = not fresh
            if channels:
                self.set_channels(channels)
            if not self._channels or (self.offline and not self._online()):
                return True  # sin lista o sin Internet: no hay nada que revisar (y los fallos no cuentan)
            summary = iptv_health.check_all(self._channels, self.store, fetch_fn=self._fetch_fn, online=self._online, stop=self._stop)
            log.info("Canales de TV: %d abren, %d no%s", summary["ok"], summary["failed"], " (sin Internet: no cuenta)" if summary["discarded"] else "")
            self.updated = time.time()
            return True
        except Exception:  # noqa: BLE001 - una revisión rara no se lleva a Orbital
            log.exception("No pude revisar los canales de TV")
            return False
        finally:
            self.checking = False
            self._refreshing.release()
            if self.catalog is not None:
                self.catalog.notify({"type": "tv-changed"})  # la sección, si está abierta, se pone al día
            self._warm_logos()

    def _warm_logos(self) -> None:
        """Los logos de los canales que se ven, de antemano: cuando abres la sección ya están. Nunca tumba la revisión."""
        try:
            self.logos.warm([c.logo for c in self.visible() if c.logo])
        except Exception:  # noqa: BLE001 - un logo raro no se lleva a Orbital
            log.exception("No pude preparar los logos de los canales")

    def start(self) -> None:
        """Revisa al arrancar (con calma) y cada ~6 h. Solo lo llama el arranque de verdad."""
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="tv-health")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _loop(self) -> None:
        if self._stop.wait(START_DELAY):
            return
        while not self._stop.is_set():
            self.refresh()
            if self._stop.wait(iptv_health.CHECK_EVERY):
                return

    # --- ponerlo en pantalla ---------------------------------------------------------------------
    def _label(self, channel: Channel, category: str) -> str:
        """La categoría que dice la barra del canal: la de la lista de la que vienes si el canal es de ahí; si no,
        la primera que se muestra en la sección."""
        for title in channel.categories:
            if category != ALL and iptv.slug(title) == category:
                return title
        return self._categories(self.visible()).get(channel.id, channel.categories)[0]

    def meta_for(self, channel: Channel, category: str, tried: set[str] | None = None, retried: bool = False) -> dict:
        meta = {"kind": "tv", "live": True, "channel_id": channel.id, "title": channel.name,
                "number": self.store.number(channel.id), "category": self._label(channel, category),
                "quality": channel.quality or "", "list": category, "tried": sorted((tried or set()) | {channel.id})}
        return {**meta, "retried": True} if retried else meta

    def play(self, channel_id: str, category: str = ALL, *, keep: bool = False, fresh: bool = False) -> dict:
        """Abre mpv en ese canal (o lo sintoniza si ya había uno en vivo). LookupError si no se puede. `fresh`: en un mpv
        nuevo aunque haya uno al aire (el vigilante de memoria: el viejo se cierra y su memoria se suelta)."""
        if self.synthetic is not None and self.synthetic.channel(channel_id) is not None:
            return self.synthetic.play(channel_id, keep=keep)
        channel = self.channel(channel_id)
        if channel is None:
            raise LookupError("Ese canal ya no está disponible. Elige otro.")
        mpv_exe = player.find_mpv()
        if not mpv_exe:
            raise LookupError("No encuentro mpv, el reproductor de Orbital. Instálalo desde Ajustes o revisa tu instalación.")
        catalog = self.catalog
        if catalog is None:
            raise LookupError("La TV en vivo no está lista todavía.")
        category, _ = self.zap_list(category)
        sessions, watch = catalog.sessions, catalog.watch
        on_air = watch.player.segment if self.playing() and not fresh else None
        if on_air is not None:
            # Ya hay un canal al aire: se sintoniza en el mismo mpv (sin cerrar ni abrir nada) y quien llama solo trae la ventana.
            if on_air.meta.get("channel_id") == channel.id or self.tune(on_air.meta, channel.id, category):
                return {"ok": True, "reveal": False, "tuned": True}
        sessions.revealing = False
        self.wire(watch.player)
        # Lo que estaba abierto se cierra justo antes de abrir el canal, no antes (si algo fallaba, tu juego ya se había cerrado).
        if sessions.before_launch and not keep:
            sessions.before_launch("media:player")
        pinned = sessions.pin()
        try:
            watch.player.play(
                catalog.launcher.run, mpv_exe, channel.url, channel.name, self.meta_for(channel, category),
                audio="es", subtitles="", live=True, user_agent=channel.user_agent, referrer=channel.referrer,
                started=lambda process: catalog.launcher.track("media:player", channel.name, process, runner="Reproductor"))
        except BaseException:
            sessions.unpin(pinned)  # mpv no abrió: Orbital no se queda «siempre encima»
            raise
        # Orbital tapa hasta la primera imagen (no una ventana negra de mpv).
        sessions.revealing = sessions.to_front("media:player", channel.name, pinned=pinned, timeout=player.LIVE_STARTUP_TIMEOUT + 5,
                                               ready=lambda: bool(watch.player.segment and watch.player.segment.playing))
        return {"ok": True, "reveal": sessions.revealing}

    def wire(self, p) -> None:
        """Lo que el reproductor le pregunta a la TV (la lista por la que salta, qué hacer si un canal falla…)."""
        p.channels_provider = self.guide
        p.on_play_channel = self.tune
        p.on_channel_failed = self.failed
        p.on_channel_ok = self.opened
        p.on_memory_full = self.reopen

    def guide(self, meta: dict, category: str | None = None) -> dict:
        """La guía (Y) y la lista de ▲▼: categorías y canales de la lista elegida, con el que ves marcado."""
        picked, channels = self.zap_list(category or meta.get("list"))
        overview = self.overview(own=False)
        return {
            "category": picked,
            "categories": [{"id": c["id"], "label": c["title"], "hint": str(c["count"]), "current": c["id"] == picked}
                           for c in overview["categories"]],
            "channels": [{"id": c.id, "name": c.name, "number": self.store.number(c.id), "quality": c.quality,
                          "category": self._label(c, picked), "current": c.id == meta.get("channel_id"),
                          "shaky": self.store.verified(c.id) is False} for c in channels]}

    def tune(self, meta: dict, channel_id: str, category: str | None = None, *, tried: set[str] | None = None,
             retried: bool = False) -> bool:
        """Sintoniza ese canal en el mismo mpv. False si ya no se puede (mpv cerrado, el canal se ocultó)."""
        channel = self.channel(channel_id)
        if channel is None or self.catalog is None:
            return False
        category = category or meta.get("list") or ALL
        ok = self.catalog.watch.player.tune(channel.url, channel.name, self.meta_for(channel, category, tried, retried),
                                            user_agent=channel.user_agent, referrer=channel.referrer)
        running = getattr(self.catalog.launcher, "current", None)
        if ok and running is not None and getattr(running, "item_id", "") == "media:player":
            running.title = channel.name  # la barra de arriba dice el canal que ves, no el primero que abriste
        return ok

    def reopen(self, meta: dict) -> None:
        """El canal ocupa demasiada memoria: el mismo canal, en un mpv nuevo (se ve un parpadeo; nada se pierde)."""
        log.info("Vuelvo a abrir %s en un mpv nuevo (ocupaba demasiada memoria)", meta.get("title"))
        try:
            self.play(meta["channel_id"], meta.get("list") or ALL, keep=True, fresh=True)
        except (LookupError, OSError) as exc:
            log.warning("No pude volver a abrir %s: %s", meta.get("title"), exc)

    def opened(self, meta: dict) -> None:
        """El canal dio imagen: abrió de verdad (sus fallos seguidos se borran)."""
        meta.pop("retried", None)
        self.store.record(meta["channel_id"], True)
        self.store.watched(meta["channel_id"])
        self.store.save()

    def failed(self, meta: dict, was_playing: bool) -> bool:
        """Un canal no abrió o se cortó. Si se cortó a media vista, primero se reintenta el mismo (una vez). Si no, se
        marca (salvo que no haya Internet: no es culpa del canal) y se pasa al siguiente. True si se hizo algo."""
        channel_id, category = meta["channel_id"], meta.get("list") or ALL
        if was_playing and not meta.get("retried"):
            log.info("El canal %s se cortó: lo reintento una vez", meta.get("title"))
            return self.tune(meta, channel_id, category, tried=set(meta.get("tried") or ()), retried=True)
        # El orden se toma ANTES de marcar el fallo: con el segundo seguido el canal se oculta y ya no está en su
        # lista, y el siguiente se buscaría desde el principio.
        ids = [c.id for c in self.zap_list(category)[1]]
        if self._online():
            self.store.record(channel_id, False, "se cortó" if was_playing else "no abre")
            self.store.save()
        else:
            return False  # sin Internet ningún canal abre: no se salta de uno en uno
        tried = set(meta.get("tried") or ()) | {channel_id}
        if len(tried) > MAX_SKIPS:
            return False  # varios seguidos sin señal: se queda en «Sin señal» para que decidas tú
        order = ids[ids.index(channel_id) + 1:] + ids[:ids.index(channel_id)] if channel_id in ids else ids
        # Primero los que no han fallado (un canal dudoso no cuenta como «el siguiente» mientras haya otro); si todos
        # lo son, el más cercano.
        untried = [cid for cid in order if cid not in tried]
        following = next((cid for cid in untried if self.store.verified(cid) is not False), None) or next(iter(untried), None)
        if following is None:
            return False
        target = self.channel(following)
        self.catalog.watch.player.toast(f"{meta.get('title')} no abre · pasando a {target.name if target else 'otro canal'}", 4)
        return self.tune(meta, following, category, tried=tried)
