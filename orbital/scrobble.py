"""Scrobble de Trakt desde el reproductor: lo que ves aparece en «Viendo ahora» y, al terminar, en tu historial.

El reproductor (player.py) avisa de cuatro cosas: empezó o reanudó (`start`), pausó (`pause`), saltaste a otro
punto (otra vez `start`, o `pause` si estaba en pausa) y se cerró (`stop`, con el porcentaje real: Trakt marca
visto desde 80 %). Aquí se traducen a `POST /scrobble/{acción}` en un hilo aparte y EN ORDEN: la red nunca
detiene el video. Un fallo se dice una sola vez por video en el registro y queda en `snapshot()` para Ajustes.

Nunca hay scrobble de TV en vivo (el reproductor no lo avisa y aquí tampoco se acepta), ni sin Trakt conectado.
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from .library import trakt as trakt_api

log = logging.getLogger(__name__)

SEEK_SECONDS = 60  # un salto de este tamaño (o más) cuenta como «saltaste»: se vuelve a avisar con el avance nuevo


def percent(position: float, duration: float) -> float | None:
    """Avance de 0 a 100 (None si no se sabe la duración)."""
    try:
        if not duration or duration <= 0:
            return None
        return min(max(float(position) / float(duration) * 100.0, 0.0), 100.0)
    except (TypeError, ValueError):
        return None


def label(meta: dict) -> str:
    """«The Office T2 · E5» o «Dune»: cómo se dice lo último que se mandó."""
    title = str(meta.get("title") or meta.get("meta_id") or "").strip()
    parts = str(meta.get("video_id") or "").split(":")
    if meta.get("kind") == "series" and len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        return f"{title} T{int(parts[1])} · E{int(parts[2])}"
    return title


class TraktScrobbler:
    def __init__(self, trakt: Callable[[], trakt_api.Trakt | None] | None = None,
                 clock: Callable[[], float] = time.time) -> None:
        self.trakt = trakt or (lambda: None)  # se pide en cada aviso: las claves de Trakt pueden cambiar
        self.clock = clock
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="trakt-scrobble")  # uno a la vez, en orden
        self._lock = threading.Lock()
        self._last: dict | None = None
        self._error: str | None = None
        self._session: str | None = None  # el video del que ya se avisó un fallo
        self._warned = False

    # --- lo que pide el reproductor --------------------------------------------------------------
    def event(self, action: str, meta: dict, position: float, duration: float) -> None:
        """Un aviso del reproductor. No bloquea ni lanza: la reproducción no depende de Trakt."""
        try:
            trakt = self.trakt()
            if trakt is None or not trakt.linked or action not in trakt_api.SCROBBLE_ACTIONS:
                return
            kind, meta_id = meta.get("kind"), meta.get("meta_id")
            if kind not in ("movie", "series") or not isinstance(meta_id, str):
                return  # TV en vivo, juegos…: nada que contarle a Trakt
            target = trakt_api.scrobble_target(kind, meta_id, meta.get("video_id"))
            progress = percent(position, duration)
            if target is None or progress is None:
                return
            self._pool.submit(self._send, trakt, action, target, progress, str(meta.get("video_id") or ""), label(meta))
        except Exception:  # noqa: BLE001
            log.exception("Error preparando el scrobble")

    def _send(self, trakt: trakt_api.Trakt, action: str, target: dict, progress: float, session: str, title: str) -> None:
        try:
            trakt.scrobble(action, target, progress)
        except Exception as exc:  # noqa: BLE001 - TraktError, TraktAuthError o cualquier otra cosa
            with self._lock:
                if session != self._session:
                    self._session, self._warned = session, False
                first, self._warned = not self._warned, True
                self._error = str(exc) or "Trakt no respondió"
            if first:
                log.warning("No pude avisarle a Trakt de «%s» (%s): %s", title, action, exc)
            return
        with self._lock:
            if session != self._session:
                self._session, self._warned = session, False
            self._error = None
            self._last = {"title": title, "action": action, "at": self.clock()}
        log.info("Trakt: %s %s al %d %%", action, title, round(progress))

    # --- para Ajustes ---------------------------------------------------------------------------
    def snapshot(self) -> dict:
        """{"last": {title, action, at} | None, "error": texto | None}"""
        with self._lock:
            return {"last": dict(self._last) if self._last else None, "error": self._error}

    def wait(self) -> None:
        """Espera a que salgan los avisos pendientes (las pruebas)."""
        self._pool.submit(lambda: None).result(timeout=10)
