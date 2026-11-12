"""Una sola escala de clasificación por idioma (Fernando, 12 nov 2026): en español latino, la mexicana; en cualquier otro
idioma, la de EE. UU.; nunca el dato crudo de otro país. La tabla (las dos escalas, las conversiones y qué idiomas son
latinos) es design/clasificaciones.json, la misma que copia el iPhone (OrbitalCore/Certification.swift)."""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path

from ..shared import design_file

log = logging.getLogger(__name__)

TABLE_FILE = design_file("clasificaciones.json")  # desde git o dentro del paquete (shared.py)
KINDS = ("movie", "series")


def load_table(path: Path = TABLE_FILE) -> dict:
    """La tabla compartida; {} (y queda anotado) si falta o viene rota: la ficha sale sin clasificación, nunca con la de
    otro país."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        log.error("No pude leer %s: las fichas salen sin clasificación", path)
        return {}


TABLE = load_table()


def _compact(value: object) -> str:
    """«B-15», «b15», « B 15 » → «B15»; «tv-ma» → «TVMA» (para comparar con la escala, no para mostrar)."""
    return re.sub(r"[\s\-_.]", "", str(value or "")).upper()


def _scale(name: str, kind: str, table: dict) -> list[str]:
    scales = table.get("scales") or {}
    rows = scales.get("mexico") if name == "mexico" else (scales.get("us") or {}).get(kind)
    return [r for r in rows or [] if isinstance(r, str)]


def normalize(value: object, scale: list[str]) -> str | None:
    """El valor escrito como en la escala («B-15» → «B15»), o None si no es de esa escala («NR», «B12», vacío)."""
    wanted = _compact(value)
    return next((s for s in scale if _compact(s) == wanted), None) if wanted else None


def uses_mexican_scale(language: str | None, table: dict | None = None) -> bool:
    """¿El idioma de las fichas es español latino? «es», «es-MX», «es-419», «es_AR»… sí; «es-ES», «en», «fr», no. Sin
    idioma, como el español (los ajustes vienen en «es»)."""
    table = TABLE if table is None else table
    lang = str(language or "").strip().replace("_", "-").lower() or "es"
    return lang in {str(x).lower() for x in table.get("mexican_languages") or []}


def resolve(mx: object, us: object, kind: str, language: str | None, table: dict | None = None) -> str | None:
    """(la de México, la de EE. UU., película o serie, idioma de las fichas) → lo que se muestra, o None.
    En español latino: la de México; si no la hay, la de EE. UU. convertida. En otro idioma, al revés."""
    table = TABLE if table is None else table
    kind = kind if kind in KINDS else "movie"
    mexico, usa = normalize(mx, _scale("mexico", kind, table)), normalize(us, _scale("us", kind, table))
    if uses_mexican_scale(language, table):
        return mexico or ((table.get("to_mexico") or {}).get(kind) or {}).get(usa or "")
    return usa or ((table.get("to_us") or {}).get(kind) or {}).get(mexico or "")
