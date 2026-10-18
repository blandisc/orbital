"""Diagnóstico de la entrada (entrada.log): lo que reportan los mandos en bruto (al navegador y a Orbital por XInput), las
teclas, la rueda y cada acción que se disparó, con la hora y si Orbital tenía el foco. Para encontrar la causa de toques
que se repiten o de un stick que «se pega» (no para filtrarlos). Una línea JSON por evento; se rota a ~2 MB."""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path

MAX_BYTES = 2_000_000
_lock = threading.Lock()


def default_path() -> Path:
    return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "orbital" / "entrada.log"


def record(entries: list[dict], path: Path | None = None) -> None:
    """Anota eventos. Nunca lanza."""
    if not entries:
        return
    path = path or default_path()
    try:
        with _lock:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_file() and path.stat().st_size > MAX_BYTES:
                path.replace(path.with_suffix(".log.1"))
            with path.open("a", encoding="utf-8") as f:
                for entry in entries[:500]:
                    f.write(json.dumps({"t": round(time.time(), 3), **entry}, ensure_ascii=False) + "\n")
    except OSError:
        pass
