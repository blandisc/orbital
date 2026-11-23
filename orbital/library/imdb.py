"""El buscador público de IMDb (sin clave): la imagen de un título por su id. Es el último respaldo del póster.

Medido el 23 nov 2026 con diez búsquedas de verdad («matrix», «the office», «coco»…): Cinemeta arma una dirección de
metahub para cada resultado aunque metahub no tenga nada. 49 de 367 daban 404 (13 %), y para esos títulos tampoco había
nada en TMDB (0 de 48); IMDb sí tenía imagen para 38 de 48. Son los títulos poco conocidos: especiales, cortos, series de
YouTube. Lo mismo que el iPhone (ios/OrbitalCore/Sources/OrbitalCore/ImdbPoster.swift).
"""

from __future__ import annotations

import re

from ..net import NetError, http_json

SUGGESTION = "https://v3.sg.media-imdb.com/suggestion/x/{imdb}.json"
HOST = "m.media-amazon.com"
_ID = re.compile(r"tt[0-9]{1,12}")


def parse(body: object, imdb: str) -> str | None:
    """La imagen del título con ese id (no la de otro parecido que venga en la lista)."""
    rows = body.get("d") if isinstance(body, dict) else None
    for row in rows if isinstance(rows, list) else []:
        if isinstance(row, dict) and row.get("id") == imdb:
            image = (row.get("i") or {}).get("imageUrl") if isinstance(row.get("i"), dict) else None
            return image if isinstance(image, str) and image.startswith("https://") else None
    return None


def sized(url: str, width: int) -> str:
    """La misma imagen de Amazon al ancho pedido («…_V1_.jpg» → «…_V1_QL75_UX500_.jpg»): la original pesa ~100 KB y
    más. Si la dirección no tiene esa forma, va tal cual."""
    if not url.endswith("._V1_.jpg"):
        return url
    return url[: -len("._V1_.jpg")] + f"._V1_QL75_UX{max(1, width)}_.jpg"


def poster(imdb: str) -> str | None:
    """La imagen de IMDb de un título. None si IMDb no la tiene (eso se puede recordar); NetError si no se pudo
    preguntar (eso no: se vuelve a preguntar)."""
    if not _ID.fullmatch(imdb or ""):
        return None
    status, body = http_json(SUGGESTION.format(imdb=imdb), timeout=10, retries=0)
    if status == 404:
        return None
    if status != 200:
        raise NetError(f"IMDb respondió HTTP {status}")
    return parse(body, imdb)
