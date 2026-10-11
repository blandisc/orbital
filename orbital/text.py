"""Texto para comparar nombres: sin acentos, sin signos, en minúsculas ("Pokémon: Esmeralda" -> "pokemon esmeralda")."""

from __future__ import annotations

import unicodedata


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())
