"""Scrobble de Trakt desde el reproductor: lo que ves aparece en «Viendo ahora» y, al terminar, en tu historial.

El reproductor (player.py) avisa de cuatro cosas: empezó o reanudó (`start`), pausó (`pause`), saltaste a otro
punto (otra vez `start`, o `pause` si estaba en pausa) y se cerró (`stop`, con el porcentaje real: Trakt marca
visto desde 80 %). Aquí se traducen a `POST /scrobble/{acción}` en un hilo aparte y EN ORDEN: la red nunca
detiene el video. Un fallo se dice una sola vez por video en el registro y queda en `snapshot()` para Ajustes.

Nunca hay scrobble de TV en vivo (el reproductor no lo avisa y aquí tampoco se acepta), ni sin Trakt conectado.

Las mismas reglas que el iPhone (desacoplar Stremio, §5; probadas contra Trakt el 29 oct):
  - Respaldo cada 5 min mientras ves (`checkpoint`): `start` y, 2 s después, `pause` con el avance real. Así otro
    aparato tiene dónde seguir aunque se apague la consola. Repetir solo `pause` no sirve: Trakt no mueve `paused_at`.
    Por lo mismo, después de un respaldo la siguiente pausa o el cierre van precedidos de un `start`.
  - Visto al 90 % (o en los créditos), no al 80 % de Trakt: hasta entonces se manda como mucho 79.9 %. Al terminar se
    manda el avance real (al menos 80 %, para que Trakt lo marque visto y lo saque de Seguir viendo).
  - Nunca una pausa o un cierre por debajo del 1 % (Trakt contesta 422).
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from .library import stremio_api
from .library import trakt as trakt_api

log = logging.getLogger(__name__)

CHECKPOINT_SECONDS = 300  # cada cuánto se le deja a Trakt un punto de reanudación mientras ves (player.py)
CHECKPOINT_GAP = 2.0  # s entre el `start` y la `pause` del respaldo (Trakt los ordena por hora)
MAX_UNFINISHED = 79.9  # Trakt marca visto desde 80 %: antes del 90 % o de los créditos, como mucho esto
MIN_SAVED = 1.0  # Trakt no guarda menos del 1 % (422 progress_too_low)
WATCHED_BY_TRAKT = 80.0
SEEK_SECONDS = 60  # un salto de este tamaño (o más) cuenta como «saltaste»: se vuelve a avisar con el avance nuevo


def percent(position: float, duration: float) -> float | None:
    """Avance de 0 a 100 (None si no se sabe la duración)."""
    try:
        if not duration or duration <= 0:
            return None
        return min(max(float(position) / float(duration) * 100.0, 0.0), 100.0)
    except (TypeError, ValueError):
        return None


# Un video mucho más corto que lo que debería ser no es la película ni el episodio: es un relleno de la fuente («este
# archivo no está disponible», 30 s). El 22 de octubre uno de 30 s «terminó» Hope (2 h 36 min): Orbital le dijo a Trakt
# que ya la habías visto y a Stremio que la quitara de Seguir viendo, y se perdió dónde ibas.
TOO_SHORT = {"movie": 20 * 60, "series": 3 * 60}  # s


def not_the_video(meta: dict, duration: float) -> bool:
    """¿Lo que suena dura tan poco que no puede ser esta película o este episodio? (Entonces no cuenta como avance.)"""
    try:
        return bool(duration) and 0 < float(duration) < TOO_SHORT.get(str(meta.get("kind")), 0)
    except (TypeError, ValueError):
        return False


def plan(action: str, meta: dict, position: float, duration: float) -> tuple[list[str], float] | None:
    """Qué avisos mandar a Trakt por un aviso del reproductor y con qué avance: (["start", "pause"], 45.2), o None si no
    se manda nada."""
    progress = percent(position, duration)
    if progress is None:
        return None
    done = bool(meta.get("finished")) or stremio_api.finished(position, duration, meta.get("kind"))
    if action == "stop" and done:
        # Terminaste (créditos o el final de un episodio) antes del 80 %: un cierre al 80 % lo marca visto y borra el punto
        # de reanudación; un cierre al 75 % lo dejaría «a medias» en Seguir viendo de todos tus aparatos.
        return ["stop"], max(progress, WATCHED_BY_TRAKT)
    progress = min(progress, MAX_UNFINISHED)
    if action == "checkpoint":
        return (["start", "pause"], progress) if progress >= MIN_SAVED else None
    if action in ("pause", "stop") and progress < MIN_SAVED:
        return None
    return [action], progress


def label(meta: dict) -> str:
    """«The Office T2 · E5» o «Dune»: cómo se dice lo último que se mandó."""
    title = str(meta.get("title") or meta.get("meta_id") or "").strip()
    parts = str(meta.get("video_id") or "").split(":")
    if meta.get("kind") == "series" and len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        return f"{title} T{int(parts[1])} · E{int(parts[2])}"
    return title


class TraktScrobbler:
    def __init__(self, trakt: Callable[[], trakt_api.Trakt | None] | None = None,
                 clock: Callable[[], float] = time.time, sleep: Callable[[float], None] = time.sleep) -> None:
        self.trakt = trakt or (lambda: None)  # se pide en cada aviso: las claves de Trakt pueden cambiar
        self.clock = clock
        self.sleep = sleep
        self.on_saved: Callable[[], None] | None = None  # Trakt guardó un punto o un visto (watch.py relee Seguir viendo)
        self._checkpointed: str | None = None  # el video cuyo último aviso fue un respaldo (lo siguiente lleva `start`)
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
            if trakt is None or not trakt.linked or action not in (*trakt_api.SCROBBLE_ACTIONS, "checkpoint"):
                return
            kind, meta_id = meta.get("kind"), meta.get("meta_id")
            if kind not in ("movie", "series") or not isinstance(meta_id, str):
                return  # TV en vivo, juegos…: nada que contarle a Trakt
            if not_the_video(meta, duration):
                log.info("Trakt: no aviso de «%s»: el video dura %d s (no es el título, es un relleno de la fuente)", label(meta), duration)
                return
            target = trakt_api.scrobble_target(kind, meta_id, meta.get("video_id"))
            planned = plan(action, meta, position, duration)
            if target is None or planned is None:
                return
            self._pool.submit(self._send, trakt, action, target, planned, str(meta.get("video_id") or ""), label(meta))
        except Exception:  # noqa: BLE001
            log.exception("Error preparando el scrobble")

    def _send(self, trakt: trakt_api.Trakt, action: str, target: dict, planned: tuple[list[str], float], session: str,
              title: str) -> None:
        steps, progress = planned
        try:
            if action in ("pause", "stop") and self._checkpointed == session:
                steps = ["start", *steps]  # tras un respaldo, Trakt cree que está en pausa: sin `start` no movería la hora
            for n, step in enumerate(steps):
                if n and steps[n - 1] == "start":
                    self.sleep(CHECKPOINT_GAP)
                trakt.scrobble(step, target, progress)
            self._checkpointed = session if action == "checkpoint" else None
            if action in ("pause", "stop", "checkpoint"):
                if hasattr(trakt, "forget_playback"):
                    trakt.forget_playback()  # Trakt ya guardó este punto: al retomar se le vuelve a preguntar
                if self.on_saved:
                    self.on_saved()
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
        log.info("Trakt: %s %s al %.1f %%", "+".join(steps), title, progress)

    # --- para Ajustes ---------------------------------------------------------------------------
    def snapshot(self) -> dict:
        """{"last": {title, action, at} | None, "error": texto | None}"""
        with self._lock:
            return {"last": dict(self._last) if self._last else None, "error": self._error}

    def wait(self) -> None:
        """Espera a que salgan los avisos pendientes (las pruebas)."""
        self._pool.submit(lambda: None).result(timeout=10)
