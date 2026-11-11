"""Las tablas compartidas para elegir versión (design/streams-rules.json, las mismas del iPhone) y lo que sale de ellas."""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path

from ...shared import design_file

log = logging.getLogger("orbital.library.streams")  # el nombre de siempre: la bitácora no cambia

CACHE_SECONDS = 600

# F2 · las tablas para elegir versión viven en design/streams-rules.json, las mismas que debe leer el iPhone.
RULES_FILE = design_file("streams-rules.json")  # desde git o dentro del paquete (shared.py)


def load_rules(path: Path = RULES_FILE) -> dict:
    """Las reglas compartidas; {} (y queda anotado) si el archivo falta o viene roto: las versiones se siguen ordenando,
    solo sin reconocer idiomas por banderas ni palabras."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        log.error("No pude leer %s: sin reglas de idioma para elegir versión", path)
        return {}


RULES = load_rules()


# Un archivo que se lee bien pero trae una regla mal escrita (un patrón inválido, un número que no es número) no puede
# impedir que Orbital arranque: cada regla se revisa sola; la mala se anota en la bitácora y se usa el respaldo.
def _bad(where: str, value, exc: Exception | str) -> None:
    log.error("streams-rules.json: regla inválida en %s (%r): %s; la salto", where, value, exc)


def _patterns(name: str, rules: dict | None = None) -> list[tuple[re.Pattern, str]]:
    rows = (RULES if rules is None else rules).get(name) or []
    if not isinstance(rows, list):
        _bad(name, rows, "no es una lista")
        return []
    out = []
    for n, r in enumerate(rows):
        try:
            flags = r.get("flags", "")
            lang = r["lang"]
            if not isinstance(lang, str) or not isinstance(flags, str):
                raise TypeError("lang y flags van como texto")
            out.append((re.compile(r["pattern"], re.I if "i" in flags else 0), lang))
        except (KeyError, TypeError, AttributeError, re.error) as exc:
            _bad(f"{name}[{n}]", r, exc)
    return out


def _number(section: dict, key: str, default: float) -> float:
    value = section.get(key, default) if isinstance(section, dict) else default
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        if key in section:
            _bad(key, value, "no es un número")
        return float(default)
    return float(value)


def _table(value, default: dict, where: str, kind: type) -> dict:
    """Un diccionario de la regla con sus valores del tipo pedido, sobre el respaldo: lo que no sirve se salta y su lugar
    lo toma el valor de respaldo."""
    if value is None:
        return dict(default)
    if not isinstance(value, dict):
        _bad(where, value, "no es una tabla")
        return dict(default)
    out = {}
    for k, v in value.items():
        if kind is float:
            ok = isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0
        else:
            ok = isinstance(v, kind)
        if isinstance(k, str) and ok:
            out[k] = float(v) if kind is float else v
        else:
            _bad(f"{where}.{k}", v, "valor inválido")
    return {**default, **out}


def _section(name: str) -> dict:
    value = RULES.get(name)
    if value is not None and not isinstance(value, dict):
        _bad(name, value, "no es una tabla")
    return value if isinstance(value, dict) else {}


_SIZE = _section("size")

_WAITS = _section("waits")

TOO_BIG_GB: dict[str, float] = _table(_SIZE.get("too_big_gb"), {"4K": 60, "1080p": 25}, "size.too_big_gb", float)

TOO_BIG_DEFAULT_GB = _number(_SIZE, "too_big_default_gb", 15)

SERIES_SIZE_FACTOR = _number(_SIZE, "series_factor", .3)

TOO_SMALL_GB: dict[str, float] = _table(_SIZE.get("too_small_gb"), {"movie": .7, "series": .12}, "size.too_small_gb", float)

REQUEST_TIMEOUT = _number(_WAITS, "per_addon_s", 10)

# Banderas e indicios de idioma en los títulos de Torrentio y compañía. Torrentio solo pone 🇲🇽 cuando el nombre dice
# latino; 🇪🇸 la pone a cualquier «Spanish»: no dice cuál de los dos («es» = español sin saber cuál).
FLAG_LANG: dict[str, str] = _table(RULES.get("flags"), {}, "flags", str)

WORD_LANG = _patterns("words")  # en orden: el primero que coincide de cada idioma

# Las de WORD_LANG que no se confunden con palabras del título (códigos en mayúsculas, el cirílico): se buscan en todo el
# nombre; las demás, solo en lo técnico («The Italian Job» no es italiano).
CODE_LANG = _patterns("codes")

# Donde empieza lo técnico de un nombre (el año, la temporada, la calidad, el origen o un corchete): antes va el título, y
# sus palabras no son idiomas («The Italian Job», «The Spanish Prisoner», «Russian Doll»).
RELEASE_MARKER = re.compile(
    r"\b(19[2-9]\d|20[0-4]\d)\b|\bs\d{1,2}(e\d{1,3})?\b|\b\d{3,4}p\b|\b4k\b|"
    r"\b(bluray|blu-ray|bdrip|brrip|web-?dl|webrip|hdtv|dvdrip|hdrip|remux|temporada|season)\b|\[", re.I)

# «DUBBED» sin idioma (RARBG, GalaxyRG): doblaje al inglés de una película extranjera, no su audio original.
DUBBED_WORD = re.compile(r"\bdubbed\b", re.I)

# Sitios de un solo idioma: lo que suben ahí va doblado a ese idioma (MejorTorrent = castellano, Cinecalidad = latino).
SITE_LANG: dict[str, str] = _table(RULES.get("sites"), {}, "sites", str)

# Lo que va después de esto en un nombre es la lista de SUBTÍTULOS, no de audio: «[Multiple Subtitle] [ENG][SPA-LA]»,
# «sub ita.eng», «Lektor i napisy PL».
SUBS_FROM = re.compile(
    r"\b(eng|english|spa|spanish|esp|español|espanol|fre|french|ita|italian|ger|german|por|pt-?br|pl|lat|latino|"
    r"castellano)[ ._-]*(subs?|subtitles?|subtitulos|subtítulos)\b|multi[ ._-]?subs?|multiple[ ._-]?subtitles?|subt[ií]t\w*|"
    r"\bsubs\b|[a-z]+subs?\b|\bsub[ ._-]+(ita|eng|esp|spa|fr|pl|lat|forzados)\b|\bvostfr\b|\bnapisy\b|\bsubbed\b|"
    r"\bsoft[ ._-]?subs?\b", re.I)

SCRIPT_FREE = re.compile(r"[Ѐ-ӿ぀-ヿ一-鿿가-힯]")  # cirílico, japonés, chino, coreano

# Qué tan seguro es el idioma de una pista de audio (de más a menos). La interfaz lo dice con palabras.
EVIDENCE = {"seen": 5, "name": 4, "site": 4, "original": 3, "assumed": 2, "maybe": 1}

# El español viene en dos doblajes que no se parecen (Los Simpson, sobre todo): latino y castellano.
SPANISH = ("es-419", "es-ES", "es")

LANG_NAMES = {"en": "Inglés", "es": "Español", "es-419": "Latino", "es-ES": "Castellano", "fr": "Francés", "it": "Italiano", "de": "Alemán", "pt": "Portugués",
              "ru": "Ruso", "ja": "Japonés", "ko": "Coreano", "zh": "Chino", "hi": "Hindi", "pl": "Polaco",
              "tr": "Turco", "uk": "Ucraniano", "nl": "Neerlandés", "cs": "Checo", "sk": "Eslovaco",
              "hu": "Húngaro", "el": "Griego", "sv": "Nórdico", "da": "Danés", "no": "Noruego", "fi": "Finés",
              "ro": "Rumano", "bg": "Búlgaro", "hr": "Croata", "sr": "Serbio", "he": "Hebreo", "ar": "Árabe",
              "th": "Tailandés", "vi": "Vietnamita", "id": "Indonesio", "lt": "Lituano", "lv": "Letón", "et": "Estonio"}

# ISO 639-2, como etiquetan los addons de subtítulos (OpenSubtitles: "eng", "spa"…).
LANG_CODES = {"en": "eng", "es": "spa", "fr": "fre", "it": "ita", "de": "ger", "pt": "por", "ja": "jpn", "ko": "kor"}

SIZE = re.compile(r"💾\s*([\d.,]+)\s*(TB|GB|MB|KB)", re.I)

SEEDERS = re.compile(r"👤\s*(\d+)")

SITE = re.compile(r"⚙️\s*([^\n]+)")

# «1440p» (algunas de anime) se llama así pero cuenta como 1080p (`res_class`); antes quedaba sin calidad, al fondo de su
# idioma (análisis de fondo con el iPhone, 3 nov 2026).
RES = [("4K", re.compile(r"\b(2160p|4k|uhd)\b", re.I)), ("1440p", re.compile(r"\b1440p\b", re.I)),
       ("1080p", re.compile(r"\b1080p\b", re.I)), ("720p", re.compile(r"\b720p\b", re.I)),
       ("480p", re.compile(r"\b(480p|sd)\b", re.I))]


def res_class(resolution: str) -> str:
    """La calidad con que se ordena y se agrupa: 1440p cuenta como 1080p."""
    return "1080p" if resolution == "1440p" else resolution

UNITS = {"KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
