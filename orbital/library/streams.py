"""Fuentes de Stremio elegidas en Orbital, con el mando.

Stremio, al abrir un episodio, muestra su lista de fuentes (pensada para ratón). Orbital pide las
fuentes a tus mismos addons (Torrentio, etc.), las analiza, las ordena según tus preferencias
(idioma, calidad) y pre-elige una: solo confirmas con A o eliges otra. Luego abre el reproductor
de Stremio directo con esa fuente (enlace stremio:///player/..., el mismo formato que stremio-core).

Las URLs pueden llevar claves (p. ej. Real-Debrid): nunca salen del servidor; la interfaz solo
recibe un índice de fuente.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import re
import threading
import time
import unicodedata
import zlib
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass, field, replace
from datetime import date
from pathlib import Path
from urllib.parse import quote, urlparse

from ..net import NET_FAILURES
from . import addons, opensubtitles
from . import subtitles as subtitle_lib

log = logging.getLogger(__name__)

CACHE_SECONDS = 600

# F2 · las tablas para elegir versión viven en design/streams-rules.json, las mismas que debe leer el iPhone.
RULES_FILE = Path(__file__).resolve().parents[2] / "design" / "streams-rules.json"


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


def _patterns(name: str) -> list[tuple[re.Pattern, str]]:
    return [(re.compile(r["pattern"], re.I if "i" in r.get("flags", "") else 0), r["lang"]) for r in RULES.get(name) or []]


_SIZE = RULES.get("size") or {}
TOO_BIG_GB: dict[str, float] = dict(_SIZE.get("too_big_gb") or {"4K": 60, "1080p": 25})
TOO_BIG_DEFAULT_GB = float(_SIZE.get("too_big_default_gb", 15))
SERIES_SIZE_FACTOR = float(_SIZE.get("series_factor", .3))
TOO_SMALL_GB: dict[str, float] = dict(_SIZE.get("too_small_gb") or {"movie": .7, "series": .12})
REQUEST_TIMEOUT = float((RULES.get("waits") or {}).get("per_addon_s", 10))

# Banderas e indicios de idioma en los títulos de Torrentio y compañía. Torrentio solo pone 🇲🇽 cuando el nombre dice
# latino; 🇪🇸 la pone a cualquier «Spanish»: no dice cuál de los dos («es» = español sin saber cuál).
FLAG_LANG: dict[str, str] = dict(RULES.get("flags") or {})
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
SITE_LANG: dict[str, str] = dict(RULES.get("sites") or {})
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


@dataclass
class Source:
    index: int
    addon: str
    stream: dict  # tal cual lo dio el addon (con su URL): solo vive en el servidor
    transport_url: str
    resolution: str = ""
    hdr: list[str] = field(default_factory=list)
    size: int = 0
    seeders: int = 0
    site: str = ""
    cached: bool = False  # [RD+]: ya está en Real-Debrid, arranca al instante
    requested: bool = False  # la pediste tú y ya terminó: «Al instante · la pediste» (va primero)
    debrid: bool = False
    languages: list[str] = field(default_factory=list)
    release: str = ""
    tags: list[str] = field(default_factory=list)
    score: float = 0.0
    binge: str | None = None  # behaviorHints.bingeGroup: misma calidad/idioma en el siguiente episodio
    dub: str = ""  # en español: "latino", "castellano" o "" si no lo dice (con los dos, "latino": trae esa pista)
    # Las pistas de audio y qué tan seguro es cada una: {"es-419": "name", "en": "original"} (ver EVIDENCE). Español en
    # tres: "es-419" (latino), "es-ES" (castellano) y "es" (no dice cuál). `languages` es lo mismo sin el doblaje.
    audio_langs: dict[str, str] = field(default_factory=dict)
    other_title: bool = False  # el nombre no menciona el título: Torrentio a veces trae otro («La casa de la pradera»)
    other_episode: bool = False  # trae otra temporada («Breaking Bad T4 · 04 - CAPITULO 01» en T1 E1): «¿Otro episodio?»
    # El nombre dice otro año («Даже ветер… [1977]» para la de 1968): es otra película. A diferencia de `other_title` (el nombre
    # no menciona el título: solo baja, y en tu idioma sigue ganando, FQ3-A), esta nunca es la recomendada (como el iPhone).
    other_year: bool = False
    # Otra serie de casi el mismo nombre («The Clone Wars» de 2008 para «Clone Wars» de 2003; names_another_series): como
    # otro año, nunca la recomendada ni la de «Continuar» (Fernando, 8 nov: lista en Real-Debrid, le seguía ganando).
    other_series: bool = False
    refused: bool = False  # Real-Debrid no la dejó bajar (FQ2-A): −1500, como el iPhone; solo es la tarjeta si está sola
    kind: str = "other"  # de qué complemento viene: "torrentio", "comet" u "other" (addon_kind; el ícono de «Versión»)

    @property
    def doubtful(self) -> bool:
        """De otro año o de otro episodio: nunca la recomendada, la ofrecida ni «al instante» si hay otra."""
        return self.other_year or self.other_episode or self.other_series

    @property
    def checked(self) -> bool:
        """Ya se abrió y estas son sus pistas reales (el iPhone lo llama «Comprobado»)."""
        return any(how == "seen" for how in self.audio_langs.values())

    @property
    def key(self) -> str:
        """Una huella estable de esta fuente (su índice cambia de una búsqueda a otra): el torrent y su archivo o, si no
        es torrent, complemento + nombre + tamaño. Para volver a la misma al «Continuar»."""
        info_hash = self.stream.get("infoHash")
        if info_hash:
            return f"{self.addon}|{str(info_hash).lower()}|{self.stream.get('fileIdx', '')}"
        name = self.release or str(self.stream.get("title") or self.stream.get("name") or "")
        return f"{self.addon}|{name}|{self.size}"

    @property
    def info_hash(self) -> str | None:
        """La huella del torrent (40 hexadecimales): la de Torrentio sin Real-Debrid, o la que va en su dirección de
        Real-Debrid (/resolve/realdebrid/<clave>/<huella>/…). Con ella se pide justo esta versión (T8-A)."""
        raw = self.stream.get("infoHash")
        if isinstance(raw, str) and re.fullmatch(r"[0-9a-fA-F]{40}", raw):
            return raw.lower()
        url = self.stream.get("url")
        found = re.search(r"/resolve/realdebrid/[^/]+/([0-9a-fA-F]{40})(?:/|$)", url) if isinstance(url, str) else None
        return found.group(1).lower() if found else None

    def public(self) -> dict:
        """Lo que ve la interfaz: nada de URLs ni claves."""
        return {
            "id": self.index, "addon": self.addon, "resolution": self.resolution, "hdr": self.hdr,
            "size": self.size, "seeders": self.seeders, "site": self.site, "cached": self.cached,
            "debrid": self.debrid, "languages": [LANG_NAMES.get(l, l) for l in self.languages],
            "release": self.release, "tags": self.tags, "audio": self.audio_label, "dub": self.dub,
            # Para «Versión»: cada idioma con su código, su nombre y cómo lo sabemos.
            "audio_langs": [{"code": code, "name": LANG_NAMES.get(code, code), "proof": how}
                            for code, how in self.audio_langs.items()],
            "addon_kind": self.kind,  # Ⓣ Torrentio, Ⓒ Comet o la pieza de los demás, junto a la calidad (AddonMark)
            "other_title": self.other_title or self.other_year or self.other_series, "other_episode": self.other_episode, "checked": self.checked, "requested": self.requested,
            # T8-A: la que hay que pedir lleva su huella (no es secreta) para «Pedirlo y avisarme» justo esta.
            **({"hash": self.info_hash} if self.debrid and not self.cached and self.info_hash else {}),
        }

    @property
    def audio_label(self) -> str:
        """"Atmos", "5.1" o "" (para el chip de audio)."""
        return next((t for t in ("Atmos", "5.1") if t in self.tags), "")


def _size_number(text: str) -> float:
    """«1,5» y «1.5» son uno y medio; «1,234.5» y «1.234,5», mil doscientos y pico; «0,750», tres cuartos.
    Lo que no se entiende queda en 0 (sin tamaño), no tira la fuente."""
    if "," in text and "." in text:
        decimal = "," if text.rfind(",") > text.rfind(".") else "."
        text = text.replace("." if decimal == "," else ",", "").replace(",", ".")
    elif "," in text:
        thousands = re.fullmatch(r"[1-9]\d{0,2}(,\d{3})+", text)
        text = text.replace(",", "") if thousands else text.replace(",", ".")
    elif text.count(".") > 1:
        text = text.replace(".", "") if re.fullmatch(r"[1-9]\d{0,2}(\.\d{3})+", text) else ""
    try:
        return float(text)
    except ValueError:
        return 0.0


FIND_DEADLINE = float((RULES.get("waits") or {}).get("find_deadline_s", 8.0))  # s para juntar fuentes: lo que llegó, se usa
CACHE_MAX = 200
RETRY_FAILED = 15  # s que se recuerda una lista incompleta por un error de red
def stable_index(addon_url: str, stream: dict) -> int:
    """El número de una fuente: sale del complemento y de su enlace, no de su lugar en la lista. Así
    «la fuente 3» sigue siendo la misma aunque otra búsqueda traiga los complementos en otro orden
    (antes, al volver a buscar, «reintentar» podía poner otra fuente sin avisar)."""
    what = stream.get("url") if isinstance(stream.get("url"), str) else f"{stream.get('infoHash')}/{stream.get('fileIdx')}"
    digest = hashlib.sha1(f"{addon_url} {what}".encode("utf-8", "surrogatepass")).hexdigest()
    return int(digest[:12], 16) % 2**31  # entero chico: viaja como número en JSON sin perder precisión


PARSE_ERRORS = (ValueError, TypeError, AttributeError, OverflowError, IndexError, KeyError)

# Lo que Torrentio manda en lugar de una película cuando Real-Debrid no puede: la «versión» «RD error» o uno de sus videos
# cortos de aviso (`/videos/failed_access_v3.mp4`…). Nunca es el título: no se ofrece (AD-5; igual que TorrentioNotices.swift).
_NOTICE_VIDEO = re.compile(r"/videos/([a-z_]+?)(?:_v\d+)?\.mp4$")
ACCOUNT_NOTICES = {"failed_access", "blocked_access"}


def is_link(stream: dict) -> bool:
    """Una versión que se abre con un enlace (http): la de Real-Debrid o una directa. Un torrent suelto no: el respaldo con
    el servidor de Stremio se quitó (Fernando, 4 nov 2026), como en el iPhone."""
    url = stream.get("url")
    return isinstance(url, str) and url.strip().lower().startswith(("http://", "https://"))


def torrentio_notice(stream: dict) -> str | None:
    """El aviso que es esta «versión» («failed_access», «downloading»…) o None si es un video de verdad."""
    url = stream.get("url") if isinstance(stream.get("url"), str) else ""
    m = _NOTICE_VIDEO.search(url.split("?", 1)[0])
    if m:
        return m.group(1)
    name = f"{stream.get('name') or ''} {stream.get('title') or ''}".lower()
    return "failed_access" if "rd error" in name else None


def _who(addon: str, transport_url: str) -> str:
    """Quién trae la versión: el nombre del complemento y el servidor de su dirección, en minúsculas."""
    try:
        host = urlparse(transport_url).hostname or ""
    except ValueError:
        host = ""
    return f"{addon} {host}".lower()


def addon_kind(addon: str, transport_url: str) -> str:
    """De qué complemento viene una versión: "torrentio", "comet" u "other" (el ícono chico de «Versión», Fernando 6 nov;
    `Streams.addonKind` del iPhone)."""
    who = _who(addon, transport_url)
    return "torrentio" if "torrentio" in who else "comet" if "comet" in who else "other"


DEBRID_MARK = re.compile(r"\[(RD|AD|PM|DL|TB|OC)[ +\]]")


def instant_mark(name: str, addon: str, transport_url: str) -> tuple[bool, bool]:
    """(¿ya está en Real-Debrid?, ¿pasa por Real-Debrid?) según cómo lo marca cada complemento (`Streams.instantMark` del
    iPhone): Torrentio con «[RD+]»; Comet y MediaFusion con «⚡» (al instante) o «⏳»/«⬇» (hay que bajarla)."""
    who = _who(addon, transport_url)
    head = name.split("\n", 1)[0]
    bolt = "⚡" in head  # por letra: «⚡️» trae un selector de variante detrás y sigue contando
    waiting = "⏳" in head or "⬇" in head
    marked = bool(DEBRID_MARK.search(name))
    if "torrentio" in who:
        return "[RD+]" in name or "+]" in head, marked
    if "comet" in who:
        return bolt or "+]" in head, marked or bolt or waiting
    if "mediafusion" in who:
        return bolt, bolt or waiting or marked
    return "[RD+]" in name or "+]" in head or bolt, marked or bolt or waiting


def parse(stream: dict, addon: str, transport_url: str, index: int, original: str | None = None) -> Source:
    """`original`: el idioma original del título según TMDB ("en", "ja", "es-ES"…); None si no se sabe."""
    name = str(stream.get("name") or "")
    text = str(stream.get("title") or stream.get("description") or "")
    blob = f"{name}\n{text}"
    first = text.split("\n", 1)[0].strip()
    hints = stream.get("behaviorHints") if isinstance(stream.get("behaviorHints"), dict) else {}
    filename = str(hints.get("filename") or "")
    src = Source(index=index, addon=addon.split()[0] if addon.split() else "", stream=stream, transport_url=transport_url,
                 kind=addon_kind(addon, transport_url))
    binge = hints.get("bingeGroup")
    src.binge = binge if isinstance(binge, str) and binge else None
    src.cached, src.debrid = instant_mark(name, addon, transport_url)
    # La resolución que declara el addon manda; el nombre del archivo solo si el addon no dice nada
    # ("1080p.UHD.BluRay" no es 4K: "UHD" ahí es el origen del disco).
    for where in (name, f"{first} {filename}"):
        src.resolution = next((label for label, pattern in RES if pattern.search(where)), "")
        if src.resolution:
            break
    src.hdr = [t for t, p in (("DV", r"\b(DV|DoVi|Dolby ?Vision)\b"), ("HDR10+", r"HDR10\+"), ("HDR", r"\bHDR(10)?\b"))
               if re.search(p, blob, re.I)]
    if "HDR10+" in src.hdr and "HDR" in src.hdr:
        src.hdr.remove("HDR")
    if (m := SIZE.search(text)):
        src.size = int(_size_number(m.group(1)) * UNITS[m.group(2).upper()])
    if (m := SEEDERS.search(text)):
        src.seeders = int(m.group(1))
    if (m := SITE.search(text)):
        src.site = m.group(1).strip()
    # Torrentio: nombre del torrent, archivo (en paquetes), «👤 💾 ⚙️» y, al final, banderas y marcas («Dual Audio»).
    lines = text.split("\n")
    marks = lines[-1] if len(lines) > 1 and (FLAG_RE.search(lines[-1]) or MARKS.search(lines[-1])) else ""
    words = "\n".join([line for line in lines[:-1 if marks else None] if not SIZE.search(line) and not SEEDERS.search(line)]
                      + [filename])
    # Peerflix pone la bandera en el nombre («Peerflix 🇪🇸 1080p»): cuenta como una marca más.
    marks = " ".join([marks, *FLAG_RE.findall(name)])
    set_languages(src, audio_languages(words, marks, src.site, original))
    src.release = first
    src.tags = [t for t, p in (("REMUX", r"\bremux\b"), ("BluRay", r"\bblu-?ray\b"), ("WEB-DL", r"\bweb-?(dl|rip)\b"),
                                ("x265", r"\b(x265|hevc|h\.?265)\b"), ("AV1", r"\bav1\b"), ("Atmos", r"\batmos\b"),
                                ("5.1", r"\b(5\.1|ddp?5|dts)"), ("Tráiler", r"\btrailer\b"), ("CAM", r"\b(cam|hdcam|ts|telesync)\b"),
                                ("3D", r"\b3D\b|\bSBS\b"), ("Reescalada", r"\bupscaled?\b|\bai[-. ]?enhanced\b"))
                if re.search(p, blob, re.I)]
    if src.dub:
        src.tags.insert(0, src.dub.capitalize())  # «Latino» / «Castellano» en la lista de fuentes
    return src


FLAG_RE = re.compile("|".join(map(re.escape, FLAG_LANG)) or r"(?!)")  # sin tabla, ninguna bandera
MARKS = re.compile(r"\b(Dubbed|Dual Audio|Multi Audio|Multi Subs)\b")


def audio_languages(words: str, marks: str = "", site: str = "", original: str | None = None) -> dict[str, str]:
    """Los idiomas de AUDIO de una fuente y cómo lo sabemos (EVIDENCE), de lo que dicen el nombre, el sitio y las marcas de
    Torrentio. Reglas sacadas de 405 fuentes reales (tests/fixtures/streams): las banderas de Torrentio mezclan audio y
    subtítulos; un nombre que lista subtítulos no habla del audio; «Dual» es el original más un doblaje."""
    found: dict[str, str] = {}

    def put(code: str, how: str) -> None:
        if EVIDENCE[how] > EVIDENCE.get(found.get(code, ""), 0):
            found[code] = how

    no_subs = [SUBS_FROM.split(line, 1)[0] for line in words.split("\n")]
    subtitled = "\n".join(no_subs) != words
    audio_words = "\n".join(line[m.start():] if (m := RELEASE_MARKER.search(line)) else line for line in no_subs)
    for pattern, code in WORD_LANG:
        if pattern.search(audio_words):
            put(code, "name")
    for pattern, code in CODE_LANG:
        if pattern.search("\n".join(no_subs)):
            put(code, "name")
    if (lang := SITE_LANG.get(re.sub(r"\W", "", site).lower())) and not (subtitled and lang not in found):
        put(lang, "site")
    flags = list(dict.fromkeys(FLAG_LANG[f] for f in FLAG_RE.findall(marks)))
    dubbed = bool(re.search(r"\b(Dubbed|Multi Audio|Dual Audio)\b", marks))
    dual = "Dual Audio" in marks or bool(re.search(r"\bdual\b", audio_words, re.I))
    if len(flags) >= 5:  # muchas banderas: con doblaje, alguna es pista (no se sabe cuál); sin él, son subtítulos
        for code in flags if dubbed else ():
            put(code, "maybe")
    elif dubbed or "Multi Subs" not in marks:
        for code in flags:
            # 🇲🇽 solo sale cuando el nombre dice latino; con «Dual Audio» y una o dos banderas, esas son las pistas.
            put(code, "name" if code == "es-419" or ("Dual Audio" in marks and len(flags) <= 2) else "maybe")
    if dual:
        # «Dual»: el original y un doblaje (en anime, japonés + inglés). Sin saber el original, inglés supuesto.
        put(original or "en", "name" if original else "assumed")
        if original and original != "en" and not any(c != original and EVIDENCE[h] >= EVIDENCE["name"] for c, h in found.items()):
            put("en", "name")
    if "es" in found and any(EVIDENCE.get(found.get(v, ""), 0) >= EVIDENCE[found["es"]] for v in ("es-419", "es-ES")):
        found.pop("es")  # «SPANiSH.LATiNO»: ya se sabe cuál
    if "es" in found and original in ("es-419", "es-ES"):  # «Spanish» en una serie española: es su castellano
        put(original, found.pop("es"))
    if not found and DUBBED_WORD.search(audio_words):
        return {"en": "maybe"}
    if not any(EVIDENCE[how] >= EVIDENCE["name"] for how in found.values()):
        put(original or "en", "original" if original else "assumed")  # nada lo dice: casi siempre el original
    return dict(sorted(found.items(), key=lambda kv: -EVIDENCE[kv[1]]))


def set_languages(src: Source, langs: dict[str, str]) -> None:
    """`audio_langs` y lo que sale de ahí: `languages` (sin el doblaje) y `dub` (solo si es seguro, para los canales)."""
    src.audio_langs = langs
    src.languages = list(dict.fromkeys("es" if code in SPANISH else code for code in langs)) or ["en"]
    sure = {code for code, how in langs.items() if EVIDENCE[how] >= EVIDENCE["original"]}
    src.dub = "latino" if "es-419" in sure else "castellano" if "es-ES" in sure else ""


TRACK_LANG = {"eng": "en", "spa": "es", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it", "por": "pt",
              "rus": "ru", "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "pol": "pl", "ukr": "uk", "hin": "hi",
              "tur": "tr", "hun": "hu", "cze": "cs", "ces": "cs", "dut": "nl", "nld": "nl", "swe": "sv", "ara": "ar",
              "esl": "es", "esp": "es", "cat": "ca", "dan": "da", "nor": "no", "nob": "no", "fin": "fi", "gre": "el",
              "ell": "el", "heb": "he", "tha": "th", "vie": "vi", "ind": "id", "rum": "ro", "ron": "ro", "bul": "bg"}
LATIN_REGIONS = {"419", "mx", "ar", "us", "co", "cl", "pe", "ve", "uy", "ec", "gt", "cr", "pr", "bo", "py", "do", "hn", "sv", "ni", "pa", "cu"}
LATINO_TRACK = re.compile(r"\blatin|\blat\b|419|latam|m[eé]xic|hispanoam", re.I)
CASTELLANO_TRACK = re.compile(r"castellano|castilian|espa[ñn]a|spain|\bes-es\b|europe|ib[eé]ric", re.I)


def track_languages(tracks: list[dict]) -> list[str]:
    """Los idiomas de las pistas de audio que dio mpv al reproducir ("es-419", "en"…): lo comprobado. Vacío si alguna
    pista no dice su idioma (entonces no se sabe qué trae)."""
    out = []
    for t in tracks or []:
        if not isinstance(t, dict) or t.get("type") != "audio":
            continue
        raw = str(t.get("lang") or "").lower()
        if not raw or raw in ("und", "mul", "zxx"):
            return []
        base, _, region = raw.replace("_", "-").partition("-")
        code = TRACK_LANG.get(base, base if len(base) in (2, 3) and base.isalpha() else "")
        if not code:
            return []
        if code == "es":
            label = f"{raw} {t.get('title') or ''}"
            code = ("es-419" if region in LATIN_REGIONS or LATINO_TRACK.search(label) else
                    "es-ES" if region == "es" or CASTELLANO_TRACK.search(label) else "es")
        out.append(code)
    return list(dict.fromkeys(out))


def heard(src: Source, tracks: list[dict]) -> bool:
    """Lo que Orbital vio al reproducirla reemplaza lo que decía el nombre. False si las pistas no dicen su idioma."""
    langs = track_languages(tracks)
    if not langs:
        return False
    # Una pista «spa» que no dice cuál no borra el doblaje que el nombre sí decía (como el iPhone).
    said = [c for c in ("es-419", "es-ES") if EVIDENCE.get(src.audio_langs.get(c, ""), 0) >= EVIDENCE["original"]]
    if "es" in langs and len(said) == 1 and not set(langs) & {"es-419", "es-ES"}:
        langs = [said[0] if code == "es" else code for code in langs]
    set_languages(src, {code: "seen" for code in langs})
    src.tags = [t for t in src.tags if t not in ("Latino", "Castellano")]
    if src.dub:
        src.tags.insert(0, src.dub.capitalize())
    return True


STOPWORDS = {"the", "and", "los", "las", "del", "une", "les", "der", "die", "das", "una"}


def _plain(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text).split())


def mentions_title(titles: list[str], text: str) -> bool:
    """¿El nombre de la fuente menciona alguno de los títulos (en cualquier idioma)? Lo que está en otra escritura
    (cirílico, japonés…) se da por bueno: no hay cómo compararlo."""
    if not titles or SCRIPT_FREE.search(text):
        return True
    # Basta la palabra más distintiva (la más larga) de algún título: «Dune - Parte due» (italiano) es Dune; pedir todas
    # las palabras marcaba como otro título a 12 de 121. «La casa de la pradera» no dice «papel» ni «heist».
    haystack = _plain(text).replace(" ", "")
    for title in titles:
        words = [w for w in _plain(title).split() if w not in STOPWORDS]
        longest = max((len(w) for w in words), default=0)
        if longest < 3:
            return True  # «Up», «It», «Pi»: caben dentro de cualquier palabra; con ese nombre no se puede decidir
        if any(len(w) == longest and w in haystack for w in words):
            return True
    return False


ARTICLES = frozenset({"the", "a", "an", "el", "la", "los", "las", "le", "les", "il", "der", "die", "das"})
# Donde acaba el nombre de la serie: «S01E01», pero también un paquete («S01-S07», «Season 1», «Complete»), el año o la
# calidad («Star.Wars.The.Clone.Wars.S01-S07.1080p» no trae «S01E01»; como el iPhone).
SERIES_EPISODE_MARK = re.compile(r"[ ._\-\[(](?:s\d{1,2}(?:[ ._]?e\d{1,3})?|seasons?|temporadas?|complete|completa|\d{3,4}p|(?:19|20)\d{2})"
                                 r"(?=[ ._\-\])]|$)", re.IGNORECASE)


def names_another_series(titles: list[str], release: str) -> bool:
    """Otra serie con casi el mismo nombre (Fernando, 8 nov: «Star Wars: Clone Wars» de 2003 bajaba «Star.Wars.The.Clone.Wars»
    de 2008, que Comet le daba por el nombre; como el iPhone, Streams.namesAnotherSeries). El nombre de la serie en el archivo
    (lo de antes de «S01E01») es uno de sus títulos pero con un artículo de más: es la otra. Igual o sin artículo, es esta."""
    mark = SERIES_EPISODE_MARK.search(release.replace("📄", ""))
    if not mark:
        return False
    show = [w for w in _plain(release.replace("📄", "")[: mark.start()]).split() if not w.isdigit()]
    if not show:
        return False
    for title in titles:
        words = _plain(title).split()
        if words == show:
            return False
        extra = [w for w in show if w not in words]
        core, title_core = [w for w in show if w not in ARTICLES], [w for w in words if w not in ARTICLES]
        # Con un artículo de más y lo demás igual, o igual al final del título («The.Clone.Wars» para «Star Wars: Clone Wars»;
        # Fernando, 9 nov: seguía abriendo la de 2008).
        if extra and all(w in ARTICLES for w in extra) and core and (
                core == title_core or 2 <= len(core) < len(title_core) and title_core[-len(core):] == core):
            return True
    return False


def series_years(info: str | None) -> tuple[int, int] | None:
    """Los años de una serie de Cinemeta («2003–2005»; «2019–» sigue al aire), como Streams.seriesYears del iPhone."""
    found = [int(y) for y in YEAR.findall(info or "")]
    if not found:
        return None
    ongoing = (info or "").strip().endswith(("–", "-"))
    end = found[1] if len(found) > 1 else date.today().year if ongoing else found[0]
    return found[0], max(found[0], end)


def other_years(release: str, years: tuple[int, int] | None) -> bool:
    """Una serie de otros años: el nombre trae un solo año y cae fuera de los de la serie, con uno de margen («Star Wars:
    Clone Wars» es de 2003–2005; un «…(2008)…» es la otra; como Streams.otherYears del iPhone)."""
    if not years:
        return False
    found = {int(y) for y in YEAR.findall(release)}
    return len(found) == 1 and not years[0] - 1 <= next(iter(found)) <= years[1] + 1


# «¿Otro episodio?» (las mismas reglas que el iPhone, Streams+Episodes.swift): Torrentio a veces pone en un episodio el
# archivo de otra temporada. Solo con temporada (los de Kitsu van de corrido).
EPISODE_MARK = re.compile(r"\bs(\d{1,2})[ ._-]?e\d{1,3}\b|\b(\d{1,2})x\d{2,3}\b", re.I)
SEASON_WORD = re.compile(r"\b(?:s|season|temporada|saison|stagione|staffel|sezon)[ ._-]?(\d{1,2})\b", re.I)
SEASON_LETTER = re.compile(r"\bT(\d{1,2})\b")  # «T4» (temporada), solo en mayúscula
SEASON_RANGE = re.compile(
    r"\bs\d{1,2}[ ._]*(?:-|~|a|to)[ ._]*s?\d{1,2}\b|\b(?:seasons?|temporadas?)[ ._]*\d{1,2}[ ._]*(?:-|~|a|to|&|y)[ ._]*\d{1,2}\b|"
    r"\bt\d{1,2}[ ._]*-[ ._]*t?\d{1,2}\b", re.I)


YEAR = re.compile(r"\b(19[2-9]\d|20[0-4]\d)\b")


def other_year(release: str, year: int | None) -> bool:
    """El nombre dice un solo año y no es el de la película (como el iPhone, Streams.otherTitle): Cinemeta da el estreno en
    EE. UU. y una extranjera puede llegar allá hasta 3 años después, así que un año anterior cuenta hasta 3."""
    if not year:
        return False
    years = {int(y) for y in YEAR.findall(release)}
    if len(years) != 1:
        return False
    only = years.pop()
    return only - year > 1 or year - only > 3


# El idioma original por el país de Cinemeta cuando TMDB no lo da (como TitleOrigin.originalCode del iPhone): el primer país
# con idioma conocido; uno hispano da es-419 o es-ES según el primero de habla hispana que se nombre.
SPAIN_NAMES = {"es", "spain", "españa"}
LATIN_NAMES = {"mx", "mexico", "méxico", "ar", "argentina", "co", "colombia", "cl", "chile", "pe", "peru", "perú", "ve",
               "venezuela", "uy", "uruguay", "ec", "ecuador", "bo", "bolivia", "py", "paraguay", "cu", "cuba", "do",
               "dominican republic", "gt", "guatemala", "cr", "costa rica", "pa", "panama", "pr", "puerto rico"}
COUNTRY_LANGUAGES = {
    "united states": "en", "us": "en", "usa": "en", "united kingdom": "en", "uk": "en", "gb": "en", "canada": "en",
    "australia": "en", "japan": "ja", "jp": "ja", "south korea": "ko", "korea": "ko", "kr": "ko", "france": "fr", "fr": "fr",
    "germany": "de", "de": "de", "italy": "it", "it": "it", "brazil": "pt", "br": "pt", "portugal": "pt", "india": "hi",
    "china": "zh", "cn": "zh", "russia": "ru"}


def original_from_country(country: object) -> str | None:
    countries = [c.strip() for c in re.split(r"[,/]", str(country or "").lower()) if c.strip()]
    lang = next((COUNTRY_LANGUAGES.get(c) or ("es" if c in LATIN_NAMES or c in SPAIN_NAMES else None)
                 for c in countries if COUNTRY_LANGUAGES.get(c) or c in LATIN_NAMES or c in SPAIN_NAMES), None)
    if lang != "es":
        return lang
    for c in countries:
        if c in LATIN_NAMES:
            return "es-419"
        if c in SPAIN_NAMES:
            return "es-ES"
    return "es"


def season_of(video_id: str) -> int | None:
    """La temporada de un episodio de IMDb («tt0903747:1:2» → 1); None si no es de ese tipo."""
    parts = video_id.split(":")
    if len(parts) != 3 or not parts[0].startswith("tt") or not parts[1].isdigit():
        return None
    return int(parts[1])


def other_episode(release: str, filename: str, season: int) -> bool:
    """El archivo o el nombre dicen otra temporada (y ninguno dice esta)."""
    def seasons(pattern: re.Pattern, text: str) -> list[int]:
        return [int(next(g for g in m.groups() if g)) for m in pattern.finditer(text)]
    for text in (filename, release):
        marked = seasons(EPISODE_MARK, text)
        if marked:
            return season not in marked
    if SEASON_RANGE.search(release):
        return False
    named = seasons(SEASON_WORD, release) + seasons(SEASON_LETTER, release)
    return bool(named) and season not in named


def spanish_dub(text: str) -> str:
    """"latino", "castellano" o "" según lo que diga el título de la fuente. Si dice los dos, "latino" (trae esa pista).
    🇪🇸 sola no lo dice: Torrentio la pone a cualquier «Spanish»."""
    langs = audio_languages(text, " / ".join(FLAG_RE.findall(text)))
    return "latino" if "es-419" in langs else "castellano" if "es-ES" in langs else ""


# El doblaje de una fuente y la variante que se pide en Ajustes (los códigos del iPhone).
DUB_CODES = {"latino": "es-419", "castellano": "es-ES"}
SPANISH_VARIANTS = ("es-419", "es-ES")


@dataclass
class Preferences:
    audio: str = "en"  # idioma de audio preferido
    quality: str = "1080p"  # resolución preferida ("4K" en la TV si quieres)
    spanish: str = ""  # con audio en español: "es-419" (latino), "es-ES" (castellano) o "" (cualquiera)
    original: str = ""  # el idioma original del título ("ja", "en"…): lo pone find(), no Ajustes
    # Tu orden después del primero (N4-A, Ajustes › Tus idiomas): códigos y «original» (el idioma original de cada título).
    # Vacío: el de siempre (con latino o castellano, original → inglés → el otro doblaje).
    plan: tuple[str, ...] = ()


# Ajustes › Tus idiomas (N4-A, Fernando 4 nov): una sola lista ordenada; «original» es un renglón. Por omisión, con latino.
LANGUAGE_CHOICES = ("es-419", "es-ES", "original", "en", "fr", "pt", "it", "de", "ja", "ko")
DEFAULT_LANGUAGES = ("es-419", "original", "en", "es-ES")


def languages_from_audio(audio: str) -> tuple[str, ...]:
    """Tu orden a partir del «Idioma» de antes (un solo valor): latino o castellano con el plan B de siempre; otro, solo él
    y luego el original."""
    if audio == "es-ES":  # la regla de siempre con castellano (como el iPhone): castellano y luego latino
        return ("es-ES", "es-419")
    if audio in ("es-419", "es"):
        return DEFAULT_LANGUAGES
    return (audio or "en", "original")


def valid_languages(value) -> bool:
    return (isinstance(value, list) and 1 <= len(value) <= len(LANGUAGE_CHOICES) and len(set(value)) == len(value)
            and all(isinstance(v, str) and v in LANGUAGE_CHOICES for v in value) and value[0] != "original")


def prefs_from_languages(languages, quality: str = "1080p") -> Preferences:
    """Las preferencias de búsqueda a partir de tu orden: el primero es tu idioma (con su doblaje) y lo demás, el plan B."""
    first, rest = languages[0], tuple(languages[1:])
    if first in SPANISH_VARIANTS:
        return Preferences(audio="es", spanish=first, quality=quality, plan=rest)
    return Preferences(audio=first, quality=quality, plan=rest)


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


class StreamFinder:
    """Pide fuentes a los complementos que las dan (en paralelo) y las guarda unos minutos."""

    def __init__(self, registry: addons.AddonRegistry, timeout: float = REQUEST_TIMEOUT) -> None:
        self.registry = registry
        self.timeout = timeout
        self._cache: dict[str, tuple[float, list[Source]]] = {}
        # Cómo le va a cada complemento (addons.Health): la del registro, para que Ajustes › Complementos diga lo mismo.
        self.health = getattr(registry, "health", None) or addons.Health()
        self.outcome: dict[str, str] = {}  # kind:video -> "ok" | "offline" | "no-addons" (para decir por qué no hay)  # complemento -> hasta cuándo no se le pregunta (no respondió)
        self._lock = threading.Lock()
        # Lo que se sabe del título y de cada fuente fuera de los complementos (los pone Watch):
        # facts(kind, video_id) -> {"original": "en" | "ja" | "es-ES"…, "titles": [...]} (de TMDB/Cinemeta);
        # tracks(key) -> las pistas de audio que mpv vio al reproducir esa fuente, o None.
        self.facts: Callable[[str, str], dict | None] = lambda kind, video_id: None
        self.tracks: Callable[[str], list[dict] | None] = lambda key: None
        # Ajustes › Ver › «Buscar subtítulos en internet»: OpenSubtitles viene con Orbital, ya no es complemento (3 nov 2026).
        self.internet_subtitles: Callable[[], bool] = lambda: True
        # La API oficial de OpenSubtitles (con la clave de la app): muchos más; el complemento queda de respaldo. La pone Watch.
        self.opensubtitles: opensubtitles.OpenSubtitles | None = None

    def addons(self) -> list[addons.Addon]:
        return self.registry.addons()

    def _get_json(self, addon: addons.Addon, path: str) -> dict:
        return addons.fetch_json(f"{addon.base}/{path}", self.timeout)

    def _fetch(self, addon: addons.Addon, kind: str, video_id: str) -> list[dict] | None:
        """Las fuentes de un complemento; None si la red falló (para no recordar «no hay» 10 minutos)."""
        started = time.monotonic()
        try:
            streams = self._get_json(addon, f"stream/{kind}/{quote(video_id, safe='')}.json").get("streams")
            streams = streams if isinstance(streams, list) else []
        except NET_FAILURES as exc:
            log.info("Sin fuentes de %s: %s", addon.name, exc)
            return None
        self.health.ok(addon.url, time.monotonic() - started)
        return [s for s in streams if isinstance(s, dict) and (s.get("url") or s.get("infoHash"))]

    def subtitles(self, kind: str, video_id: str, lang: str) -> list[str]:
        """URLs de subtítulos en tu idioma de tus complementos y de OpenSubtitles (si está prendido), por si el video no trae."""
        codes = {lang, LANG_CODES.get(lang, lang)}
        urls = []

        def get(addon: addons.Addon | None) -> list:
            path = f"subtitles/{kind}/{quote(video_id, safe='')}.json"
            try:
                data = self._get_json(addon, path) if addon else addons.fetch_json(f"{subtitle_lib.BUILTIN}/{path}", self.timeout)
            except NET_FAILURES as exc:
                log.info("Sin subtítulos de %s: %s", addon.name if addon else "OpenSubtitles", exc)
                return []
            subs = data.get("subtitles")
            return subs if isinstance(subs, list) else []

        # OpenSubtitles viene con Orbital: el de la lista o el traído de Stremio no se pregunta dos veces.
        ask: list[addons.Addon | None] = [a for a in self.addons() if a.handles("subtitles", kind, video_id) and not is_opensubtitles(a.base)]
        if self.internet_subtitles():
            ask.append(None)
        for addon in ask:
            urls += [s["url"] for s in get(addon) if isinstance(s, dict) and isinstance(s.get("url"), str)
                     and s["url"].startswith(("http://", "https://")) and s.get("lang") in codes]
        return urls

    def subtitle_options(self, kind: str, video_id: str, fingerprint: tuple[str, int] | None = None) -> list[dict] | None:
        """Todos los subtítulos de un video, de tus complementos y de OpenSubtitles (si está prendido en Ajustes › Ver, como el iPhone), con la copia
        para la que se hicieron y sus descargas. Con la huella del archivo, los de tu copia exacta salen primero. None si
        nadie contestó (sin internet): así «no hay» y «sin conexión» no se confunden."""
        # OpenSubtitles viene con Orbital: el de la lista o el traído de Stremio no se pregunta dos veces.
        bases = [(a.base, a.name) for a in self.addons() if a.handles("subtitles", kind, video_id) and not is_opensubtitles(a.base)]
        if self.internet_subtitles():
            bases.append((subtitle_lib.BUILTIN, "OpenSubtitles"))
        extra = f"/videoHash={fingerprint[0]}&videoSize={fingerprint[1]}" if fingerprint else ""

        def ask(base: str, name: str) -> list[dict] | None:
            try:
                data = addons.fetch_json(f"{base}/subtitles/{kind}/{quote(video_id, safe='')}{extra}.json", self.timeout)
            except NET_FAILURES as exc:
                log.info("Sin subtítulos de %s: %s", name, exc)
                return None
            return subtitle_lib.parse_options(data.get("subtitles") or [], "OpenSubtitles" if "opensubtitles" in base else name)

        api = self.opensubtitles if self.internet_subtitles() else None
        with ThreadPoolExecutor(max_workers=max(1, len(bases)) + 1) as pool:
            official = pool.submit(api.search, video_id, fingerprint) if api is not None else None
            answers = list(pool.map(lambda b: ask(*b), bases))
            from_api = (official.result() if official else None) or []
        if all(a is None for a in answers) and not from_api:
            return None
        return opensubtitles.merge(from_api, [o for a in answers if a for o in a])

    def find(self, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        key = cache_key(kind, video_id, prefs)
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        serving = [a for a in self.addons() if a.handles("stream", kind, video_id)]
        # Un complemento que falló dos veces seguidas no se espera: se vuelve a probar con espera creciente, hasta una
        # hora (si todos están así, se prueban).
        alive = [a for a in serving if not self.health.skip(a.url)] or serving
        skipped = len(alive) < len(serving)
        pool = ThreadPoolExecutor(max_workers=max(1, len(alive)))
        futures = {pool.submit(self._fetch, a, kind, video_id): a for a in alive}
        # Plazo total: un complemento lento no deja al usuario mirando la pantalla de carga 45 s.
        done, late = wait(futures, timeout=FIND_DEADLINE)
        pool.shutdown(wait=False, cancel_futures=True)
        results = []
        for future, addon in futures.items():
            streams = future.result() if future in done else None
            if streams is None:
                self.health.fail(addon.url)
                log.info("%s no respondió a tiempo", addon.name)
            results.append((addon, streams))
        sources, seen = [], set()
        failed = skipped or any(streams is None for _, streams in results)
        try:
            facts = self.facts(kind, video_id) or {}
        except Exception as exc:  # noqa: BLE001 - sin TMDB, las fuentes salen igual (sin el idioma original)
            log.info("Sin datos del título para las fuentes: %s", exc)
            facts = {}
        original = facts.get("original") if isinstance(facts.get("original"), str) else None
        titles = [x for x in facts.get("titles") or [] if isinstance(x, str) and x.strip()]
        years = series_years(facts.get("years")) if kind == "series" else None
        notices = set()
        for addon, streams in results:
            for stream in streams or []:
                if isinstance(stream, dict) and (notice := torrentio_notice(stream)):
                    notices.add(notice)
                    continue
                if isinstance(stream, dict) and not is_link(stream):
                    continue  # un torrent suelto (sin Real-Debrid): ya no se reproduce en la tele (4 nov), como el iPhone
                index = stable_index(addon.url, stream)
                while index in seen:  # el mismo enlace dos veces: la segunda, el número siguiente
                    index = (index + 1) % 2**31
                try:
                    src = parse(stream, addon.name, addon.url, index, original)
                    hints = stream.get("behaviorHints") if isinstance(stream.get("behaviorHints"), dict) else {}
                    filename = str(hints.get("filename") or "")
                    src.other_title = not mentions_title(titles, f"{src.release} {filename}")
                    src.other_series = ":" in video_id and any(names_another_series(titles, name) or other_years(name, years)
                                                               for name in (src.release, filename))
                    if kind == "movie" and isinstance(facts.get("year"), int):
                        src.other_year = other_year(src.release, facts["year"])
                    if (season := season_of(video_id)) is not None:
                        src.other_episode = other_episode(src.release, str(hints.get("filename") or ""), season)
                    if (tracks := self.tracks(src.key)):
                        heard(src, tracks)
                    sources.append(src)
                except PARSE_ERRORS as exc:  # una fuente con datos raros se salta, no tumba la lista
                    log.info("Fuente rara de %s: %s", addon.name, exc)
                    continue
                seen.add(index)
        # El plan B de idiomas sabe cuál es el original de este título (latino → original → inglés → castellano).
        ranked = rank(sources, replace(prefs, original=original or ""), kind)
        # «Sin conexión» solo si nadie contestó: un complemento muerto (ThePirateBay+ ya no existe, «Local Files» apagado)
        # hacía decir «No pude conectar con tus complementos» aunque Torrentio sí respondiera que no lo tiene.
        answered = any(streams is not None for _, streams in results)
        self.outcome[f"{kind}:{video_id}"] = "no-addons" if not serving else "offline" if not answered and not ranked else "ok"
        if notices & ACCOUNT_NOTICES:  # tu Real-Debrid no deja: la ficha le pregunta a Real-Debrid cuál de las tres causas
            self.outcome[f"{kind}:{video_id}"] = "debrid-account"
        if failed and not ranked:
            return ranked  # la red falló y no hay nada: no se recuerda, la próxima vez se pregunta otra vez
        with self._lock:
            if len(self._cache) >= CACHE_MAX:  # una entrada por episodio visto: se van las más viejas
                for old in sorted(self._cache, key=lambda k: self._cache[k][0])[:CACHE_MAX // 2]:
                    del self._cache[old]
            # Si algún complemento no respondió (Wi-Fi al despertar), la lista se recuerda solo unos segundos.
            stamp = time.time() - (CACHE_SECONDS - RETRY_FAILED if failed else 0)
            self._cache[key] = (stamp, ranked)
        return ranked

    def cached(self, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        """Las que ya se buscaron (sin ir a internet): para el reproductor, que no puede esperar. Si se buscaron con
        otras preferencias (acabas de elegir latino), sirven igual: los números de fuente no cambian."""
        hit = self._cache.get(cache_key(kind, video_id, prefs))
        if hit and time.time() - hit[0] < CACHE_SECONDS:
            return hit[1]
        fresh = [v for k, v in list(self._cache.items())
                 if k.startswith(f"{kind}:{video_id}:") and time.time() - v[0] < CACHE_SECONDS]
        other = max(fresh, key=lambda v: v[0], default=None)
        # Ordenadas para estas preferencias sin tocar su `score` (la otra lista las comparte).
        return sorted(other[1], key=lambda s: score(s, prefs, kind), reverse=True) if other else []

    def forget(self, kind: str, video_id: str) -> None:
        """Se aprendió algo de una fuente (sus pistas): la próxima búsqueda la vuelve a clasificar."""
        with self._lock:
            for key in [k for k in self._cache if k.startswith(f"{kind}:{video_id}:")]:
                del self._cache[key]

    def forget_all(self) -> None:
        """Cambiaron tus complementos o sus opciones (Torrentio): la próxima búsqueda pregunta de nuevo."""
        with self._lock:
            self._cache.clear()
        self.outcome.clear()

    def get(self, kind: str, video_id: str, prefs: Preferences, index: int) -> Source | None:
        found = self.cached(kind, video_id, prefs)
        if not found:
            return None  # caducó (los enlaces de Real-Debrid vencen): quien llama busca otra vez
        return next((s for s in found if s.index == index), None)
