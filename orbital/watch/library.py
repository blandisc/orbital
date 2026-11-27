"""Tu biblioteca: Stremio (con su caché), Cinemeta, Trakt y Seguir viendo."""

from __future__ import annotations

import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from ..atomic import atomic_write
from ..library import cinemeta, stremio_api
from ..library import trakt as trakt_api
from ..library.models import LibraryItem
from .base import STREMIO_KEY, STREMIO_STALE_SECONDS, _Base
from .items import enrich_watch_item, returning_item, stremio_item

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


_CACHE_LOCK = threading.Lock()


RETRY_SECONDS = 1.5  # Cinemeta: espera antes del segundo intento
# «Quitada de Seguir viendo · Deshacer»: Trakt borra tu avance hasta que el aviso se fue (el aviso dura 8 s, UNDO_MS de
# main.js; un poco más por si el «Deshacer» llega tarde por la red).
DISMISS_UNDO_SECONDS = 10.0


class _Library(_Base):
    """Tu biblioteca: Stremio (con su caché), Cinemeta, Trakt y Seguir viendo."""

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
                atomic_write(self._stremio_cache, json.dumps([i.to_dict() for i in items], ensure_ascii=False), encoding="utf-8")
        except OSError:
            log.warning("No pude guardar la biblioteca de Stremio en caché", exc_info=True)

    # --- Lo tuyo de videos tal como se vio la última vez (Stremio + Trakt) -------------------------------------------------
    # Arranque en frío (27 nov 2026): con Trakt al mando (Stremio de respaldo) lo que estás viendo vivía solo en memoria, y al
    # reiniciar «A continuación» salía con 5 tarjetas (los juegos) y se llenaba hasta que Trakt contestaba (de 10 a 37 s,
    # medido). Ahora lo último que se publicó se guarda y el escaneo lo incluye: sale desde el primer segundo y Trakt lo pone al
    # día cuando contesta.
    def _load_videos_cache(self) -> list[LibraryItem]:
        if not self._videos_cache:
            return []
        try:
            return [LibraryItem.from_dict(d) for d in json.loads(self._videos_cache.read_text(encoding="utf-8"))]
        except (OSError, ValueError, TypeError, AttributeError, KeyError):
            return []

    def _put_videos(self, items: list[LibraryItem]) -> None:
        """Pone lo tuyo de videos en la biblioteca y lo guarda para el próximo arranque."""
        self.store.replace_source("stremio", items)
        self.videos = items
        if not self._videos_cache:
            return
        try:
            with _CACHE_LOCK:
                if items:
                    self._videos_cache.parent.mkdir(parents=True, exist_ok=True)
                    atomic_write(self._videos_cache, json.dumps([i.to_dict() for i in items], ensure_ascii=False), encoding="utf-8")
                else:
                    self._videos_cache.unlink(missing_ok=True)  # sin cuentas (o sin nada): el próximo arranque tampoco enseña nada viejo
        except OSError:
            log.warning("No pude guardar lo tuyo de videos en caché", exc_info=True)

    @property
    def stremio_backup(self) -> bool:
        """Corte S5: Stremio ya no se lee (Seguir viendo y Mi lista salen de Trakt) y solo recibe copia si la dejas. Sin
        Trakt conectado nunca: Stremio sigue siendo tu lista (P-4)."""
        return self.setting("stremio_role", "both") == "backup" and self.trakt_library.active

    def _save_stremio(self, auth: str, item: dict) -> None:
        """Lo que Orbital le manda a tu Stremio (tu avance, Mi lista, quitar de Seguir viendo): solo si dejaste la copia."""
        if self.setting("stremio_copy", True):
            self.stremio_client.save_library_item(auth, item)

    def refresh_stremio(self, background: bool = False) -> bool:
        """Descarga la biblioteca de Stremio. En segundo plano no bloquea a quien llama."""
        if not self.config.stremio.enabled or not self.stremio_linked:
            return False
        if self.stremio_backup:  # respaldo: lo tuyo sale de Trakt; Stremio solo recibe copia
            with self._stremio_publish:
                had = bool(self.stremio_items)
                self.stremio_items = []
                self._put_videos(self.trakt_library.merged([]))
            if had:
                self.events.publish({"type": "library-changed"})
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
            watchables = stremio_api.parse_library(raw)
            for w in watchables:
                try:
                    items.append(stremio_item(w))
                except (TypeError, ValueError, AttributeError) as exc:
                    log.warning("Stremio: se salta %s (%s)", getattr(w, "id", "?"), exc)
            self.stremio_error = None
            self._returning(items, watchables)
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
            self._put_videos(self.trakt_library.merged(items))
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
        self._put_videos(self.trakt_library.merged(items))
        self._save_stremio_cache(items)
        self.events.publish({"type": "library-changed"})

    def _returning(self, items: list[LibraryItem], watchables: list[stremio_api.Watchable]) -> None:
        """Las series que ibas al día y ya tienen episodio nuevo vuelven a Seguir viendo (con caché de Cinemeta: rápido)."""
        now = time.time()
        candidates = [w for w in watchables if stremio_api.may_return(w, now)][:stremio_api.RETURN_CHECKS]

        def check(w: stremio_api.Watchable) -> tuple[stremio_api.Watchable, tuple[str, float] | None]:
            try:
                info = self.cinemeta.meta("series", w.id)
            except cinemeta.CinemetaError:
                return w, None
            ids = [v["id"] for v in info.get("videos") or [] if isinstance(v, dict) and v.get("id")]
            if w.video_id not in stremio_api.parse_watched(w.watched, ids):
                return w, None  # lo quitaste a medias de Seguir viendo: no se terminó, no vuelve
            return w, cinemeta.new_episode(info, w.video_id or "", w.last_watched or now, now)

        if not candidates:
            return
        where = {i.id: n for n, i in enumerate(items)}
        with ThreadPoolExecutor(max_workers=6) as pool:
            for w, found in pool.map(check, candidates):
                n = where.get(f"stremio:{w.id}")
                if found and n is not None:
                    items[n] = returning_item(w, *found)
                    log.info("Seguir viendo: %s vuelve con su episodio nuevo (%s)", w.name, found[0])

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

    def dismiss_continue(self, meta_id: str, later: bool = False) -> None:
        """"Quitar de Seguir viendo": borra tu avance en Trakt (desaparece también en el iPhone) y en tu cuenta de
        Stremio (desaparece también en Stremio). Con `later` (el aviso «Quitada de Seguir viendo · Deshacer», 16 nov
        2026, como el iPhone) sale ya de Seguir viendo, pero Trakt lo borra hasta que el aviso se fue (`undo_dismiss`)."""
        trakt = self.trakt_library.client()
        auth = self.credentials.get(STREMIO_KEY)
        if not auth and trakt is None:
            raise stremio_api.StremioError(stremio_api.NOT_LINKED)
        self._dismiss_due(meta_id)  # otro «Quitar» del mismo título que seguía esperando: ya va
        before = self.state.prefs(f"stremio:{meta_id}").get("dismissed")
        # Una serie al día en Trakt no tiene avance que borrar: la consola recuerda cuándo la quitaste.
        self.state.set_pref(f"stremio:{meta_id}", "dismissed", time.time())
        raw = self.stremio_client.library_item(auth, meta_id) if auth else None
        if auth and raw:
            back = next((i for i in self.stremio_items if i.extra.get("meta_id") == meta_id and i.extra.get("new_episode")), None)
            self._save_stremio(
                auth, stremio_api.dismissed(raw, time.time(), back.extra.get("video_id") if back else None))
        if later and trakt is not None:
            timer = threading.Timer(DISMISS_UNDO_SECONDS, self._dismiss_due, args=(meta_id,))
            timer.daemon = True
            self._dismissing[meta_id] = (timer, before, raw)
            timer.start()
            self._publish_videos()  # fuera de Seguir viendo ya, sin esperar a Trakt
        else:
            self._forget_progress(meta_id)
        if auth:
            self.refresh_stremio()
        self.events.publish({"type": "library-changed"})

    def undo_dismiss(self, meta_id: str) -> None:
        """«Deshacer» del aviso: vuelve a Seguir viendo como estaba (Trakt nunca supo). LookupError si ya se borró."""
        pending = self._dismissing.pop(meta_id, None)  # atómico: o lo toma el temporizador o el «Deshacer», nunca los dos
        if pending is None:
            raise LookupError("Ya lo quité de Trakt")
        timer, before, raw = pending
        timer.cancel()
        self.state.set_pref(f"stremio:{meta_id}", "dismissed", before)
        auth = self.credentials.get(STREMIO_KEY)
        if auth and raw:
            self._save_stremio(auth, {**raw, "_mtime": stremio_api._iso(time.time())})
            self.refresh_stremio()
        self._publish_videos()

    def _dismiss_due(self, meta_id: str) -> None:
        """El aviso ya se fue: ahora sí se borra tu avance en Trakt."""
        pending = self._dismissing.pop(meta_id, None)
        if pending is None:
            return
        pending[0].cancel()
        try:
            self._forget_progress(meta_id)
        except trakt_api.TraktError as exc:
            log.warning("No pude borrar tu avance de %s en Trakt: %s", meta_id, exc)

    def _forget_progress(self, meta_id: str) -> None:
        """Lo que se borra de verdad: lo de un canal a medias y tu avance en Trakt."""
        if self.trakt_library.channel is not None:
            self.trakt_library.channel.dismiss(meta_id)  # V2: lo de un canal a medias tampoco se retoma
        trakt = self.trakt_library.client()
        if trakt is not None:
            playback, _, _, _ = self.trakt_library.snapshot()
            for row in playback:
                if row["meta_id"] == meta_id and row.get("id") is not None:
                    trakt.remove_playback(row["id"])
            self.trakt_library.forget("paused")
            self.refresh_trakt()

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
        if self.trakt_library.stale():
            self.refresh_trakt(background=True)

    def _trakt_saved(self) -> None:
        """Trakt guardó dónde ibas o que ya lo viste: Seguir viendo se vuelve a armar con eso (por detrás)."""
        self.trakt_library.forget("paused")
        self.trakt_library.forget("watched")
        self.refresh_trakt(background=True)

    def refresh_trakt(self, background: bool = False, force: bool = False) -> bool:
        """Pregunta a Trakt si cambió algo (lo que viste o guardaste en el iPhone) y, si sí, vuelve a armar Seguir viendo y
        Mi lista. En segundo plano no bloquea a quien llama."""
        if not self.config.stremio.enabled:
            return False
        if background:
            threading.Thread(target=self.refresh_trakt, kwargs={"force": force}, daemon=True, name="trakt-sync").start()
            return True
        if not self._trakt_busy.acquire(blocking=False):
            return False
        try:
            if not self.trakt_library.refresh(force=force):
                return False
            self._publish_videos()
        finally:
            self._trakt_busy.release()
        return True

    def _publish_videos(self) -> None:
        """Vuelve a poner la biblioteca de videos (Stremio + Trakt) y avisa a la pantalla."""
        with self._stremio_publish:
            items = self.stremio_items
        merged = self.trakt_library.merged(items)
        # Lo que solo vino de Trakt aún no tiene sinopsis ni nombre del episodio: Cinemeta (con caché) antes de mostrarlo.
        self._enrich([i for i in merged if i.extra.get("from_trakt") and not i.extra.get("episode_title")
                      and (i.category == "continue" or not i.extra.get("description"))])
        with self._stremio_publish:
            if self.stremio_items is not items:
                merged = self.trakt_library.merged(self.stremio_items)  # llegó la biblioteca de Stremio mientras tanto
            self._put_videos(merged)
        self.events.publish({"type": "library-changed"})

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
            self.stremio_items = []
            self._put_videos(self.trakt_library.merged([]))  # lo de Trakt se queda
            if self._stremio_cache:
                self._stremio_cache.unlink(missing_ok=True)
