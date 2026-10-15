"""Salud de los canales de TV en vivo: ¿abre de verdad ahora mismo?

Que el servidor conteste no basta: muchos entregan la lista y luego dan 404 en el video. Un canal «abre» si
responde su manifiesto, su variante (si hay varias calidades) y un segmento real. El resultado se guarda en
disco y un canal se oculta solo tras DOS fallos seguidos (un servidor que se cayó un rato no lo borra). Los
que nunca se han verificado se muestran, para que la sección no salga vacía mientras se revisan.
"""

from __future__ import annotations

import json
import logging
import ssl
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin

from ..net import NET_ERRORS, read_body
from .iptv import HTTP, Channel

log = logging.getLogger(__name__)

CHECK_EVERY = 6 * 3600  # s entre revisiones de toda la lista
FAILS_TO_HIDE = 2  # fallos seguidos para ocultar un canal
TIMEOUT = 8.0  # s por petición
MANIFEST_BYTES = 512 * 1024
SEGMENT_BYTES = 64 * 1024  # basta con que empiece a llegar video
MIN_SEGMENT = 1024  # un segmento de menos de 1 KB es una página de error disfrazada
WORKERS = 12  # canales a la vez: rápido, y sin saturar el Wi-Fi mientras alguien ve la tele
# El mismo que usa mpv en el modo en vivo (playback.LIVE_USER_AGENT): lo que se prueba es lo que se reproduce.
DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

Fetch = Callable[..., bytes]  # (url, headers, limit=…) -> los primeros bytes de la respuesta


class Unreachable(Exception):
    """El canal no respondió como debe; `reason` es corto y sirve para el registro."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass
class Check:
    ok: bool
    reason: str = ""
    stage: str = ""  # hasta dónde llegó: manifest | variant | segment | direct
    ms: int = 0


def _context() -> ssl.SSLContext:
    # mpv no valida certificados de fábrica (tls-verify=no) y hay canales de México con el suyo vencido que sí se ven
    # (Unison TV): una prueba más estricta que el reproductor los ocultaría sin motivo.
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def fetch(url: str, headers: dict, *, limit: int = MANIFEST_BYTES, timeout: float = TIMEOUT) -> bytes:
    """Los primeros `limit` bytes de `url`. Lanza Unreachable con el motivo. Solo http(s): la lista de un canal
    (que viene de internet) podía mandar a leer un archivo del equipo con una calidad «file:///…»."""
    if not HTTP.match(url or ""):
        raise Unreachable("dirección que no es de internet")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_context()) as res:
            return read_body(res, timeout=timeout, limit=limit, truncate=True)
    except urllib.error.HTTPError as exc:
        raise Unreachable(f"HTTP {exc.code}") from exc
    except TimeoutError as exc:
        raise Unreachable("no responde a tiempo") from exc
    except NET_ERRORS as exc:
        raise Unreachable(f"sin conexión ({type(exc).__name__})") from exc


def request_headers(channel: Channel) -> dict:
    headers = {"User-Agent": channel.user_agent or DEFAULT_USER_AGENT, "Accept": "*/*"}
    if channel.referrer:
        headers["Referer"] = channel.referrer
    return headers


def _uris(playlist: str) -> list[str]:
    return [line.strip() for line in playlist.splitlines() if line.strip() and not line.startswith("#")]


def _variant(master: str) -> str | None:
    """La dirección de la primera calidad de una lista maestra (la línea que sigue a #EXT-X-STREAM-INF)."""
    lines = [line.strip() for line in master.splitlines()]
    for i, line in enumerate(lines):
        if line.startswith("#EXT-X-STREAM-INF"):
            return next((x for x in lines[i + 1:] if x and not x.startswith("#")), None)
    return None


def check_channel(channel: Channel, fetch_fn: Fetch = fetch) -> Check:
    """Manifiesto -> variante -> un segmento real (el mismo recorrido que hace mpv al sintonizar)."""
    started, stage = time.monotonic(), "manifest"
    headers = request_headers(channel)

    def done(ok: bool, reason: str = "") -> Check:
        return Check(ok, reason, stage, int((time.monotonic() - started) * 1000))

    try:
        text = fetch_fn(channel.url, headers, limit=MANIFEST_BYTES).decode("utf-8", "replace")
        if not text.lstrip().startswith("#EXTM3U"):
            # Un flujo directo (.ts, DASH): se comprueba que sea video y no una página web.
            head = text.lstrip()[:64].lower()
            stage = "direct"
            if not text.strip():
                return done(False, "respuesta vacía")
            if head.startswith("<") and "<mpd" not in text[:2000].lower():
                return done(False, "es una página web, no un video")
            return done(True)
        media_url, media = channel.url, text
        if "#EXT-X-STREAM-INF" in text:
            stage = "variant"
            variant = _variant(text)
            if variant is None:
                return done(False, "lista maestra sin calidades")
            media_url = urljoin(channel.url, variant)
            media = fetch_fn(media_url, headers, limit=MANIFEST_BYTES).decode("utf-8", "replace")
            if not media.lstrip().startswith("#EXTM3U"):
                return done(False, "la calidad no es una lista de video")
        stage = "segment"
        segments = _uris(media)
        if not segments:
            return done(False, "sin segmentos")
        # Como un reproductor, empezando 3 segmentos antes del final (el último puede no estar listo aún).
        pick = segments[max(0, len(segments) - 3)]
        data = fetch_fn(urljoin(media_url, pick), headers, limit=SEGMENT_BYTES)
        if len(data) < MIN_SEGMENT:
            return done(False, "segmento vacío")
        return done(True)
    except Unreachable as exc:
        return done(False, exc.reason)


class HealthStore:
    """Qué se sabe de cada canal (en disco, junto al resto de cachés) y el número fijo de cada uno.

    Por canal: fallos seguidos, cuándo se revisó, si abrió la última vez y por qué falló. Un canal sin
    registro está «sin verificar»: se muestra. Los números (el «12» del canal) no cambian cuando otro canal
    se oculta o aparece uno nuevo: cada canal conserva el suyo."""

    def __init__(self, path: Path | None = None, clock: Callable[[], float] = time.time) -> None:
        self.path = path
        self.clock = clock
        self._lock = threading.Lock()
        self._records: dict[str, dict] = {}
        self._numbers: dict[str, int] = {}
        self._load()

    # --- disco ------------------------------------------------------------------------------
    def _load(self) -> None:
        if self.path is None:
            return
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        if not isinstance(data, dict):
            return
        for key, record in (data.get("channels") or {}).items():
            if isinstance(record, dict) and isinstance(record.get("fails"), int) and record["fails"] >= 0:
                self._records[str(key)] = {"fails": record["fails"], "checked": float(record.get("checked") or 0),
                                           "ok": bool(record.get("ok")), "reason": str(record.get("reason") or "")[:80]}
        for key, number in (data.get("numbers") or {}).items():
            if isinstance(number, int) and not isinstance(number, bool) and number > 0:
                self._numbers[str(key)] = number

    def save(self) -> None:
        if self.path is None:
            return
        with self._lock:
            payload = {"channels": self._records, "numbers": self._numbers}
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                tmp = self.path.with_suffix(".tmp")
                tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
                tmp.replace(self.path)
            except OSError as exc:
                log.warning("No pude guardar la salud de los canales: %s", exc)

    # --- consultas --------------------------------------------------------------------------
    def hidden(self, channel_id: str) -> bool:
        with self._lock:
            return self._records.get(channel_id, {}).get("fails", 0) >= FAILS_TO_HIDE

    def verified(self, channel_id: str) -> bool | None:
        """True: abrió la última vez · False: falló (pero aún no se oculta) · None: nunca se ha revisado."""
        with self._lock:
            record = self._records.get(channel_id)
            return None if record is None else record["ok"]

    def record_of(self, channel_id: str) -> dict | None:
        with self._lock:
            record = self._records.get(channel_id)
            return dict(record) if record else None

    # --- cambios ----------------------------------------------------------------------------
    def record(self, channel_id: str, ok: bool, reason: str = "") -> None:
        """Anota cómo salió un intento (una revisión o abrirlo de verdad). Abrir bien borra los fallos."""
        with self._lock:
            fails = 0 if ok else self._records.get(channel_id, {}).get("fails", 0) + 1
            self._records[channel_id] = {"fails": fails, "checked": self.clock(), "ok": ok, "reason": "" if ok else reason[:80]}

    def number(self, channel_id: str) -> int | None:
        with self._lock:
            return self._numbers.get(channel_id)

    def assign_numbers(self, channels: list[Channel]) -> None:
        """Los canales nuevos reciben el siguiente número libre (en orden alfabético la primera vez)."""
        with self._lock:
            top = max(self._numbers.values(), default=0)
            for channel in channels:
                if channel.id not in self._numbers:
                    top += 1
                    self._numbers[channel.id] = top

    def forget_missing(self, keep: set[str]) -> None:
        """Los canales que ya no están en la lista dejan su registro (sus números se conservan: si vuelven,
        regresan al mismo)."""
        with self._lock:
            for key in [k for k in self._records if k not in keep]:
                del self._records[key]


def check_all(channels: list[Channel], store: HealthStore, *, fetch_fn: Fetch = fetch, workers: int = WORKERS,
              online: Callable[[], bool] = lambda: True, stop: threading.Event | None = None) -> dict:
    """Revisa todos los canales y anota el resultado. Si mientras tanto se fue el Internet, los fallos no
    cuentan (no es culpa de los canales): ninguno se oculta por una caída del Wi-Fi.
    Devuelve {"ok": n, "failed": n, "discarded": bool}."""
    results: dict[str, Check] = {}

    def run(channel: Channel) -> None:
        if stop is not None and stop.is_set():
            return
        results[channel.id] = check_channel(channel, fetch_fn)

    with ThreadPoolExecutor(max_workers=max(1, workers), thread_name_prefix="tv-health") as pool:
        list(pool.map(run, channels))
    failed = [cid for cid, check in results.items() if not check.ok]
    if failed and not online():
        log.info("Sin Internet durante la revisión de canales: no cuenta ningún fallo")
        return {"ok": len(results) - len(failed), "failed": len(failed), "discarded": True}
    for cid, check in results.items():
        store.record(cid, check.ok, check.reason)
    store.forget_missing({c.id for c in channels})
    store.save()
    for cid in failed:
        log.debug("Canal sin señal (%s): %s", cid, results[cid].reason)
    return {"ok": len(results) - len(failed), "failed": len(failed), "discarded": False}
