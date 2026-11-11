"""El orden de las versiones (puntos por calidad, idioma, semillas) y los enlaces para el reproductor."""

from __future__ import annotations

import base64
import json
import zlib
from typing import TYPE_CHECKING
from urllib.parse import quote

from .languages import SPANISH_VARIANTS, Preferences
from .rules import SERIES_SIZE_FACTOR, SPANISH, TOO_BIG_DEFAULT_GB, TOO_BIG_GB, TOO_SMALL_GB, res_class

if TYPE_CHECKING:
    from .source import Source


# Sin tu español al instante, el plan B (Fernando, 4 nov 2026: «latino, idioma original, luego inglés y luego castellano»):
# cuánto baja cada escalón desde lo que vale tu doblaje. Lo de al instante (+1000) le sigue ganando a lo que hay que bajar.
# Los pesos son los del iPhone (tests/fixtures/rd-scenarios/README.md): cada renglón n de tu orden (0 = original, 1 = inglés,
# 2 = el otro doblaje) vale −300 − 40·n más lo que vale su prueba − 300: a 600 o más del tuyo (más que los −500 de un nombre
# que no dice el título) y a menos de 1400 (arrancar al instante contra pedirla).
STEP_UNSURE_SPANISH = 100  # «Español (no dice cuál)»: justo después del tuyo

STEP_BASE, STEP_EACH = 300, 40


# Lo que pierde una versión «al instante» de Comet frente a una de Torrentio (menos que lo que pesa «al instante»).
COMET_DOUBT = 300


def score(src: Source, prefs: Preferences, kind: str = "movie") -> float:
    s = 0.0
    if src.cached:
        s += 1000  # arranca al instante
    elif src.debrid:
        s -= 400  # Real-Debrid aún tiene que descargarla
    # Comet, de respaldo (Fernando, 6 nov): su «⚡» a veces no es cierto y manda el aviso «Not ready yet» de ElfHosted. Va
    # detrás de la de Torrentio al instante en tu idioma, pero antes de una que Real-Debrid aún tiene que bajar
    # (`Streams.cometDoubt` del iPhone).
    if src.cached and src.kind == "comet":
        s -= COMET_DOUBT
    s += language_score(src, prefs)
    order = ["4K", "1080p", "720p", "480p", ""]
    want = order.index(prefs.quality) if prefs.quality in order else 1
    res = res_class(src.resolution)
    have = order.index(res) if res in order else len(order) - 1
    s += 200 - 60 * abs(have - want) - (40 if have > want else 0)  # peor que lo pedido pesa más
    gb = src.size / 1e9
    # Demasiado grande para transmitir con soltura (REMUX de 95 GB); en 4K lo normal ya es 15-60 GB.
    too_big = TOO_BIG_GB.get(res, TOO_BIG_DEFAULT_GB) * (1 if kind == "movie" else SERIES_SIZE_FACTOR)
    if gb > too_big:
        s -= 150
    if src.size and gb < TOO_SMALL_GB["movie" if kind == "movie" else "series"]:
        s -= 120  # sospechosamente pequeño: mala calidad
    if "DV" in src.hdr and "HDR" not in src.hdr and "HDR10+" not in src.hdr:
        s -= 200  # Dolby Vision sin HDR de respaldo: colores raros en pantallas sin DV
    if "Tráiler" in src.tags or "CAM" in src.tags:
        s -= 2000
    if "3D" in src.tags:
        s -= 1500
    if "Reescalada" in src.tags:
        s -= 150
    if src.other_episode or src.other_year or src.other_series or src.refused:
        s -= 1500  # otra temporada, otro año u otra serie: nunca la recomendada (como el iPhone)
    if src.other_title:
        s -= 500  # el nombre no menciona el título: puede ser otro (no se esconde: a veces es el nombre en otro país)
    s += min(src.seeders, 500) / 10
    return s


# Cuánto vale el idioma que quieres según qué tan seguro es: lo comprobado, lo que se dice y el original van arriba;
# «tal vez», apenas; sin él, al fondo. Antes «solo inglés» supuesto le ganaba a una dual que sí decía inglés.
LANG_POINTS = {"seen": 340, "name": 300, "site": 300, "original": 300, "assumed": 260, "maybe": 60}

# Otro idioma pesa más que arrancar al instante (+1000): una en ruso lista no le gana a una en tu idioma que tarda.
WRONG_LANGUAGE = -1600


def language_score(src: Source, prefs: Preferences) -> float:
    """Cuánto suma el idioma según qué tan seguro es. Con una variante de español elegida (Ajustes, la voz, la serie):
    el doblaje pedido primero, luego el español que no dice cuál y al final el otro (el mismo orden que el iPhone)."""
    langs = src.audio_langs or {code: "name" for code in src.languages}
    wanted = prefs.spanish if prefs.audio == "es" and prefs.spanish in SPANISH_VARIANTS else None
    if prefs.audio != "es" and not prefs.plan:  # solo tu idioma (lo de antes de «Tus idiomas»)
        how = langs.get(prefs.audio)
        return LANG_POINTS[how] if how else WRONG_LANGUAGE
    if prefs.audio != "es":
        wanted = prefs.audio
    elif not wanted:  # «Español (cualquiera)»: como siempre, cualquier español vale lo mismo y otro idioma no cuenta
        best = float(WRONG_LANGUAGE)
        for code in SPANISH:
            if code in langs:
                best = max(best, float(LANG_POINTS[langs[code]]))
        return best
    if not prefs.plan and wanted == "es-ES":
        # Con castellano y sin tu lista, la regla de antes (la del iPhone): el español que no dice cuál −100, el latino −250
        # y otro idioma no cuenta. El orden latino → original → inglés → castellano es el de quien prefiere latino.
        best = float(WRONG_LANGUAGE)
        for code in SPANISH:
            if code in langs:
                drop = 0 if code == wanted else STEP_UNSURE_SPANISH if code == "es" else 250
                best = max(best, float(LANG_POINTS[langs[code]] - drop))
        return best
    if prefs.plan:
        steps = [prefs.original if c == "original" else c for c in prefs.plan]
    else:
        steps = [prefs.original, "en", "es-ES"]  # quien prefiere latino (es-MX): el orden de Fernando, 4 nov
    # Los lugares son fijos (README: original 0, inglés 1, castellano 2): sin saber el original, su renglón queda vacío y el
    # inglés sigue siendo el 1 (antes subía al 0 y valía 40 de más que en el iPhone). Si un idioma está en dos renglones
    # (el original es el inglés), cuenta el primero.
    def slot(code: str) -> int | None:
        return next((i for i, c in enumerate(steps) if c and c == code and c != wanted), None)
    best = float(WRONG_LANGUAGE)
    for code, how in langs.items():
        if code == wanted:
            points = float(LANG_POINTS[how])
        elif code == "es" and wanted in SPANISH_VARIANTS:
            points = float(LANG_POINTS[how] - STEP_UNSURE_SPANISH)
        elif (n := slot(code)) is not None:
            points = float(-STEP_BASE - STEP_EACH * n + LANG_POINTS[how] - 300)
        else:
            continue
        best = max(best, points)
    return best


def rank(sources: list[Source], prefs: Preferences, kind: str = "movie") -> list[Source]:
    for src in sources:
        src.score = score(src, prefs, kind)
    return sorted(sources, key=lambda x: x.score, reverse=True)


def _encode_component(text: str) -> str:
    # Igual que encodeURIComponent (URI_COMPONENT_ENCODE_SET de stremio-core).
    return quote(text, safe="-_.!~*'()")


def encode_stream(stream: dict) -> str:
    """Stream::encode de stremio-core: JSON -> zlib sin compresión -> base64 estándar."""
    data = json.dumps(stream, ensure_ascii=False, separators=(",", ":")).encode()
    return base64.b64encode(zlib.compress(data, 0)).decode()


def player_link(src: Source, meta_transport: str, kind: str, meta_id: str, video_id: str) -> str:
    """Abre el reproductor de Stremio directo con esa fuente (sin su lista de fuentes)."""
    parts = [encode_stream(src.stream), src.transport_url, meta_transport, kind, meta_id, video_id]
    return "stremio:///player/" + "/".join(_encode_component(p) for p in parts)


def cache_key(kind: str, video_id: str, prefs: Preferences) -> str:
    """La lista ordenada depende del idioma, la variante y la calidad: cada combinación se recuerda aparte."""
    return f"{kind}:{video_id}:{prefs.audio}:{prefs.spanish}:{prefs.quality}:{','.join(prefs.plan)}"


def is_opensubtitles(base: str) -> bool:
    return "opensubtitles" in base.lower()
