"""Registro de la voz (voz.log): cada pedido de Alexa, Siri o el micrófono del iPhone, qué se dijo, qué entendió Orbital,
si salió bien y cuánto tardó. Para saber qué frases fallan de verdad (antes no quedaba rastro: solo la intención cuando
sí se entendía). Una línea JSON por pedido; se rota al llegar a ~1 MB (se guarda el anterior)."""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)

MAX_BYTES = 1_000_000
_lock = threading.Lock()


def default_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "voz.log"


def record(entry: dict, path: Path | None = None) -> None:
    """Anota un pedido. Nunca lanza: la voz no depende de su registro."""
    path = path or default_path()
    try:
        line = json.dumps({"at": time.strftime("%Y-%m-%d %H:%M:%S"), **entry}, ensure_ascii=False)
        with _lock:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_file() and path.stat().st_size > MAX_BYTES:
                path.replace(path.with_suffix(".log.1"))
            # errors="replace": un surrogate suelto («\ud800» en el JSON del pedido) no es UTF-8 válido y
            # reventaba la escritura (HTTP 500 en /api/voice); se anota como «?».
            with path.open("a", encoding="utf-8", errors="replace") as f:
                f.write(line + "\n")
    except (OSError, ValueError, TypeError) as exc:  # ValueError incluye UnicodeEncodeError
        log.debug("No pude anotar la voz: %s", exc)


def read(path: Path | None = None, limit: int = 200) -> list[dict]:
    """Los últimos pedidos (para revisar qué falla)."""
    path = path or default_path()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()[-limit:]
    except OSError:
        return []
    out = []
    for line in lines:
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out
