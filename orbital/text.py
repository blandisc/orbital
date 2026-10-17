"""Texto para comparar nombres: sin acentos, sin signos, en minúsculas ("Pokémon: Esmeralda" -> "pokemon esmeralda")."""

from __future__ import annotations

import time
import unicodedata
from datetime import datetime


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())


def clock(when: float | datetime | time.struct_time | None = None) -> str:
    """La hora como se dice en México, en 12 horas: «9:05 p. m.» (la misma que el reloj de la tele: core/format.js)."""
    if when is None or isinstance(when, (int, float)):
        when = time.localtime(when)
    hour, minute = (when.hour, when.minute) if isinstance(when, datetime) else (when.tm_hour, when.tm_min)
    return f"{hour % 12 or 12}:{minute:02d} {'a. m.' if hour < 12 else 'p. m.'}"
