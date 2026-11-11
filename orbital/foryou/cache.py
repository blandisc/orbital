"""La caché de «Para ti»: lo que se trajo de internet, con fecha, en memoria y en disco.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from ..atomic import atomic_write
from .base import SERVICE_ERRORS

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


# ---------------------------------------------------------------- caché
# Una lista armada con fichas de TMDB que se cayeron en su mayoría está «a medias» (Cache.get(whole=True) no la guarda).
_build = threading.local()



def _mark_partial(asked: int, failed: int) -> None:
    """Más de la mitad de las fichas pedidas no llegó (TMDB lento o caído): lo que se arme ahora no se guarda."""
    if asked and failed * 2 > asked:
        _build.partial = True



def _has_items(value: Any) -> bool:
    """Una lista con algo, o un paquete ({items: […]}) con algo."""
    if isinstance(value, dict):
        return bool(value.get("items"))
    return bool(value)



class Cache:
    """Lo que se trajo de internet, con fecha. Si al renovar falla la red se queda lo de antes; dos
    peticiones a la vez por lo mismo esperan a una sola descarga.

    Con tope (V6): cada prefijo de clave («poster:», «details:», «imdb:»…) guarda a lo más `PREFIX_LIMIT` entradas (se
    olvidan las más viejas) y lo que pasa de `MAX_AGE` sin renovarse se borra al cargar y al guardar. Cada entrada se
    convierte a texto una sola vez: al guardar, solo lo que cambió se vuelve a serializar."""

    SAVE_DELAY = 5.0  # s: varias listas que llegan juntas se guardan de una vez
    PREFIX_LIMIT = 2000  # entradas por prefijo
    MAX_AGE = 60 * 24 * 3600  # s: ni sin internet sirve algo de hace dos meses (los pósters duran 30 días)

    def __init__(self, clock: Callable[[], float] = time.time, path: Path | None = None) -> None:
        self.clock = clock
        self._data: dict[str, tuple[float, Any]] = {}
        self._by_prefix: dict[str, dict[str, None]] = {}  # claves por prefijo, de la más vieja a la más nueva
        self._encoded: dict[str, str] = {}  # la entrada ya en JSON (se borra al cambiar)
        self._locks: dict[str, threading.Lock] = {}
        self._lock = threading.Lock()
        # Modo sin internet: lo último que se trajo queda en disco. Al arrancar sin conexión, Para ti y Películas y series
        # enseñan eso (vencido, pero mejor que nada); con conexión, se renueva como siempre.
        self.path = path
        self._save_timer: threading.Timer | None = None
        if path is not None:
            self._load()

    @staticmethod
    def _prefix(key: str) -> str:
        return key.split(":", 1)[0]

    def _put(self, key: str, when: float, value: Any) -> None:
        """Con self._lock tomado."""
        self._data[key] = (when, value)
        self._encoded.pop(key, None)
        keys = self._by_prefix.setdefault(self._prefix(key), {})
        keys.pop(key, None)
        keys[key] = None
        while len(keys) > self.PREFIX_LIMIT:
            self._drop(next(iter(keys)))

    def _drop(self, key: str) -> None:
        """Con self._lock tomado."""
        self._data.pop(key, None)
        self._encoded.pop(key, None)
        keys = self._by_prefix.get(self._prefix(key))
        if keys is not None:
            keys.pop(key, None)

    def _purge(self) -> None:
        """Con self._lock tomado: borra lo que pasó de MAX_AGE."""
        oldest = self.clock() - self.MAX_AGE
        for key in [k for k, (when, _) in self._data.items() if when < oldest]:
            self._drop(key)

    def _load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8")) if self.path and self.path.exists() else {}
        except (OSError, ValueError) as exc:
            log.info("Para ti: no pude leer lo guardado (%s): empiezo de cero", exc)
            return
        entries = [(key, entry) for key, entry in (raw.items() if isinstance(raw, dict) else [])
                   if isinstance(entry, list) and len(entry) == 2 and isinstance(entry[0], (int, float))]
        with self._lock:
            for key, entry in sorted(entries, key=lambda e: e[1][0]):  # de lo más viejo a lo más nuevo (el tope olvida lo viejo)
                self._put(key, float(entry[0]), entry[1])
            self._purge()

    def _schedule_save(self) -> None:
        if self.path is None:
            return
        with self._lock:
            if self._save_timer is not None:
                return
            self._save_timer = threading.Timer(self.SAVE_DELAY, self._save)
            self._save_timer.daemon = True
            self._save_timer.start()

    def _save(self) -> None:
        with self._lock:
            self._save_timer = None
            self._purge()
            data = dict(self._data)
            encoded = dict(self._encoded)
        path = self.path
        if path is None:
            return
        parts, fresh = [], {}
        for key, (when, value) in data.items():
            text = encoded.get(key)
            if text is None:
                try:  # solo lo que se puede guardar tal cual (listas y fichas)
                    text = json.dumps(key, ensure_ascii=False) + ":" + json.dumps([when, value], ensure_ascii=False)
                except (TypeError, ValueError):
                    continue
                fresh[key] = text
            parts.append(text)
        with self._lock:  # lo que cambió mientras tanto ya no está en _data con esa fecha: no se guarda su texto viejo
            for key, text in fresh.items():
                if self._data.get(key) is data[key]:
                    self._encoded[key] = text
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            atomic_write(path, "{" + ",".join(parts) + "}")
        except OSError as exc:
            log.info("Para ti: no pude guardar lo traído: %s", exc)

    def get(self, key: str, ttl: float, load: Callable[[], Any], *, stale: bool = False, whole: bool = False) -> Any:
        """`stale`: si ya venció, devuelve lo de antes al instante y lo renueva en segundo plano (el iPhone y la TV
        no esperan 30 s al Top 10 de Netflix: con caché fría el iPhone se rendía y no enseñaba ni Top 10 ni Disney).
        `whole`: una lista que llega vacía o a medias (la mayoría de sus fichas cayeron: TMDB lento) se enseña pero no se
        guarda, y se vuelve a pedir la próxima vez (antes se quedaba horas como si fuera la buena; como el iPhone)."""
        if whole:
            return self._whole(key, ttl, load)
        with self._lock:
            hit = self._data.get(key)
            lock = self._locks.setdefault(key, threading.Lock())
        if hit and self.clock() - hit[0] < ttl:
            return hit[1]
        if hit and stale:
            if lock.acquire(blocking=False):  # una sola renovación a la vez
                threading.Thread(target=self._refresh, args=(key, load, lock), daemon=True, name=f"cache:{key}").start()
            return hit[1]
        with lock:
            with self._lock:
                hit = self._data.get(key)
            if hit and self.clock() - hit[0] < ttl:
                return hit[1]
            try:
                value = load()
            except SERVICE_ERRORS:
                if hit:  # sin internet: lo de la última vez
                    return hit[1]
                raise
            with self._lock:
                self._put(key, self.clock(), value)
            self._schedule_save()
            return value

    def _whole(self, key: str, ttl: float, load: Callable[[], Any]) -> Any:
        with self._lock:
            hit = self._data.get(key)
        if hit and self.clock() - hit[0] < ttl:
            return hit[1]
        outer = getattr(_build, "partial", False)
        _build.partial = False
        try:
            value = load()
        except SERVICE_ERRORS:
            if hit:
                return hit[1]
            raise
        finally:
            partial = _build.partial
            _build.partial = outer or partial
        if partial or not _has_items(value):
            return hit[1] if hit and _has_items(hit[1]) else value  # lo bueno de antes gana a lo incompleto de ahora
        with self._lock:
            self._put(key, self.clock(), value)
        self._schedule_save()
        return value

    def _refresh(self, key: str, load: Callable[[], Any], lock: threading.Lock) -> None:
        try:
            value = load()
            with self._lock:
                self._put(key, self.clock(), value)
            self._schedule_save()
        except SERVICE_ERRORS as exc:  # sin red: se queda lo de antes
            log.warning("Para ti: no pude renovar %s: %s", key, exc)
        except Exception:  # noqa: BLE001 - un error de programación se ve en la bitácora; se queda lo de antes
            log.exception("Para ti: falló la renovación de %s", key)
        finally:
            lock.release()

    def clear(self, prefix: str = "") -> None:
        with self._lock:
            for key in [k for k in self._data if k.startswith(prefix)]:
                self._drop(key)
        self._save()  # de inmediato: si no, lo borrado regresa del disco al reiniciar

    def peek(self, key: str) -> Any:
        """Lo último que se trajo para `key` (aunque ya venció), sin salir a internet; None si nunca."""
        with self._lock:
            hit = self._data.get(key)
        return hit[1] if hit else None
