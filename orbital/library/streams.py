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
from dataclasses import dataclass, field
from urllib.parse import quote

from ..net import NET_ERRORS
from . import addons

log = logging.getLogger(__name__)

CACHE_SECONDS = 600
REQUEST_TIMEOUT = 15

# Banderas e indicios de idioma en los títulos de Torrentio y compañía. Torrentio solo pone 🇲🇽 cuando el nombre dice
# latino; 🇪🇸 la pone a cualquier «Spanish»: no dice cuál de los dos («es» = español sin saber cuál).
FLAG_LANG = {
    "🇬🇧": "en", "🇺🇸": "en", "🇲🇽": "es-419", "🇪🇸": "es", "🇦🇷": "es-419", "🇫🇷": "fr", "🇮🇹": "it", "🇩🇪": "de",
    "🇵🇹": "pt", "🇧🇷": "pt", "🇷🇺": "ru", "🇯🇵": "ja", "🇰🇷": "ko", "🇨🇳": "zh", "🇮🇳": "hi", "🇵🇱": "pl",
    "🇹🇷": "tr", "🇺🇦": "uk", "🇳🇱": "nl", "🇨🇿": "cs", "🇸🇰": "sk", "🇭🇺": "hu", "🇬🇷": "el", "🇸🇪": "sv",
    "🇩🇰": "da", "🇳🇴": "no", "🇫🇮": "fi", "🇷🇴": "ro", "🇧🇬": "bg", "🇭🇷": "hr", "🇷🇸": "sr", "🇮🇱": "he",
    "🇸🇦": "ar", "🇹🇭": "th", "🇻🇳": "vi", "🇮🇩": "id", "🇱🇹": "lt", "🇱🇻": "lv", "🇪🇪": "et",
}
WORD_LANG = [
    # «LAT», «CAST», «ESP» solo en mayúsculas: en minúsculas son palabras del título («Cast.Away»).
    (re.compile(r"\b(latino|latam|es-?419|spa-la|hispanoam[eé]rica(no)?|latinoam[eé]rica(no)?|latin[ ._-]?american)\b|"
                r"dual[-. ]?lat\b", re.I), "es-419"),
    (re.compile(r"\bLAT\b"), "es-419"),
    (re.compile(r"\b(castellano|castilian|es-es)\b", re.I), "es-ES"),
    (re.compile(r"\bCAST\b"), "es-ES"),
    (re.compile(r"\b(spanish|español|espanol|spa)\b", re.I), "es"),
    (re.compile(r"\bESP\b|\[Esp\]|(?<=/)ES\b|\bES(?=/)"), "es"),  # «EN/FR/ES»
    (re.compile(r"\b(eng|english|ingles)\b|(?<![A-Za-z])EN(?=/)", re.I), "en"),
    (re.compile(r"\b(jpn|japanese|jap)\b", re.I), "ja"),  # «Eng 5.1 AAC Jap 5.1 AAC»
    (re.compile(r"(?i:\b(mvo|dvo|avo)\b)|[А-Яа-яЁё]{4,}"), "ru"),  # voces rusas; un nombre en cirílico es un lanzamiento ruso
    (re.compile(r"(?i:\b(french|fre|vff|vf|vf2|vfq|truefrench)\b)|(?<![-\w])FR\b"), "fr"),
    (re.compile(r"\b(ita|italian)\b", re.I), "it"),
    (re.compile(r"\b(german|deutsch|ger)\b", re.I), "de"),
    (re.compile(r"\b(rus|russian)\b", re.I), "ru"),
    (re.compile(r"\b(hindi)\b", re.I), "hi"),
    # "CZ dabing", "SK dabing", "PL lektor", "dublado": doblajes que antes pasaban por inglés.
    # «CZ», «SK», «PL» solo en mayúsculas y no tras un guion: «x264-pl» es el grupo que lo subió, no polaco.
    (re.compile(r"(?i:\b(cze|czech|cesky|český|dabing)\b)|(?<![-\w])CZ\b"), "cs"),
    (re.compile(r"(?i:\b(slovak|slovensky|slovenský)\b)|(?<![-\w])SK\b"), "sk"),
    (re.compile(r"(?i:\b(polish|polski|lektor)\b)|(?<![-\w])PL\b"), "pl"),
    (re.compile(r"\b(hun|hungarian|magyar)\b", re.I), "hu"),
    (re.compile(r"\b(ptbr|pt-br|dublado|portuguese|portugues|português)\b", re.I), "pt"),
    (re.compile(r"\b(ukr|ukrainian)\b", re.I), "uk"),
    (re.compile(r"\b(turkish|türkçe|turkce)\b", re.I), "tr"),
    (re.compile(r"\b(arabic)\b", re.I), "ar"),
    (re.compile(r"\b(korean|kor)\b", re.I), "ko"),
    # «NORDiC» no: son subtítulos nórdicos con el audio original.
    (re.compile(r"\b(swedish|danish|norwegian|finnish)\b", re.I), "sv"),
]
# Las de WORD_LANG que no se confunden con palabras del título (códigos en mayúsculas, el cirílico): se buscan en todo el
# nombre; las demás, solo en lo técnico («The Italian Job» no es italiano).
CODE_LANG = [
    (re.compile(r"\bLAT\b"), "es-419"), (re.compile(r"\bCAST\b"), "es-ES"),
    (re.compile(r"\bESP\b|\[Esp\]|(?<=/)ES\b|\bES(?=/)"), "es"), (re.compile(r"(?<![A-Za-z])EN(?=/)", re.I), "en"),
    (re.compile(r"[А-Яа-яЁё]{4,}"), "ru"), (re.compile(r"(?<![-\w])FR\b"), "fr"),
    (re.compile(r"(?<![-\w])CZ\b"), "cs"), (re.compile(r"(?<![-\w])SK\b"), "sk"), (re.compile(r"(?<![-\w])PL\b"), "pl"),
]
# Donde empieza lo técnico de un nombre (el año, la temporada, la calidad, el origen o un corchete): antes va el título, y
# sus palabras no son idiomas («The Italian Job», «The Spanish Prisoner», «Russian Doll»).
RELEASE_MARKER = re.compile(
    r"\b(19[2-9]\d|20[0-4]\d)\b|\bs\d{1,2}(e\d{1,3})?\b|\b\d{3,4}p\b|\b4k\b|"
    r"\b(bluray|blu-ray|bdrip|brrip|web-?dl|webrip|hdtv|dvdrip|hdrip|remux|temporada|season)\b|\[", re.I)
# «DUBBED» sin idioma (RARBG, GalaxyRG): doblaje al inglés de una película extranjera, no su audio original.
DUBBED_WORD = re.compile(r"\bdubbed\b", re.I)
# Sitios de un solo idioma: lo que suben ahí va doblado a ese idioma (MejorTorrent = castellano, Cinecalidad = latino).
SITE_LANG = {"mejortorrent": "es-ES", "wolfmax4k": "es-ES", "cinecalidad": "es-419", "ilcorsaronero": "it",
             "rutor": "ru", "rutracker": "ru", "torrent9": "fr", "comando": "pt", "bludv": "pt", "besttorrents": "pl"}
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
RES = [("4K", re.compile(r"\b(2160p|4k|uhd)\b", re.I)), ("1080p", re.compile(r"\b1080p\b", re.I)),
       ("720p", re.compile(r"\b720p\b", re.I)), ("480p", re.compile(r"\b(480p|sd)\b", re.I))]
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
            "other_title": self.other_title, "checked": self.checked,
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


FIND_DEADLINE = 8.0  # s para juntar fuentes: lo que llegó, se usa
DOWN_SECONDS = 120.0  # s que se salta un complemento que no respondió
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


def parse(stream: dict, addon: str, transport_url: str, index: int, original: str | None = None) -> Source:
    """`original`: el idioma original del título según TMDB ("en", "ja", "es-ES"…); None si no se sabe."""
    name = str(stream.get("name") or "")
    text = str(stream.get("title") or stream.get("description") or "")
    blob = f"{name}\n{text}"
    first = text.split("\n", 1)[0].strip()
    hints = stream.get("behaviorHints") if isinstance(stream.get("behaviorHints"), dict) else {}
    filename = str(hints.get("filename") or "")
    src = Source(index=index, addon=addon.split()[0] if addon.split() else "", stream=stream, transport_url=transport_url)
    binge = hints.get("bingeGroup")
    src.binge = binge if isinstance(binge, str) and binge else None
    src.cached = "[RD+]" in name or "+]" in name.split("\n")[0]
    src.debrid = bool(re.search(r"\[(RD|AD|PM|DL|TB|OC)[ +\]]", name))
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


FLAG_RE = re.compile("|".join(map(re.escape, FLAG_LANG)))
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


def score(src: Source, prefs: Preferences, kind: str = "movie") -> float:
    s = 0.0
    if src.cached:
        s += 1000  # arranca al instante
    elif src.debrid:
        s -= 400  # Real-Debrid aún tiene que descargarla
    s += language_score(src, prefs)
    order = ["4K", "1080p", "720p", "480p", ""]
    want = order.index(prefs.quality) if prefs.quality in order else 1
    have = order.index(src.resolution) if src.resolution in order else len(order) - 1
    s += 200 - 60 * abs(have - want) - (40 if have > want else 0)  # peor que lo pedido pesa más
    gb = src.size / 1e9
    # Demasiado grande para transmitir con soltura (REMUX de 95 GB); en 4K lo normal ya es 15-60 GB.
    too_big = {"4K": 60, "1080p": 25}.get(src.resolution, 15) * (1 if kind == "movie" else .3)
    if gb > too_big:
        s -= 150
    if src.size and gb < (0.7 if kind == "movie" else 0.12):
        s -= 120  # sospechosamente pequeño: mala calidad
    if "DV" in src.hdr and "HDR" not in src.hdr and "HDR10+" not in src.hdr:
        s -= 200  # Dolby Vision sin HDR de respaldo: colores raros en pantallas sin DV
    if "Tráiler" in src.tags or "CAM" in src.tags:
        s -= 2000
    if "3D" in src.tags:
        s -= 1500
    if "Reescalada" in src.tags:
        s -= 150
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
    if prefs.audio != "es":
        how = langs.get(prefs.audio)
        return LANG_POINTS[how] if how else WRONG_LANGUAGE
    wanted = prefs.spanish if prefs.spanish in SPANISH_VARIANTS else None
    best = float(WRONG_LANGUAGE)
    for code in SPANISH:
        if code not in langs:
            continue
        points = LANG_POINTS[langs[code]]
        if wanted and code == "es":
            points -= 100  # español sin saber cuál: después del que pediste, antes que otro idioma
        elif wanted and code != wanted:
            points -= 250  # el otro doblaje
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
    return f"{kind}:{video_id}:{prefs.audio}:{prefs.spanish}:{prefs.quality}"


class StreamFinder:
    """Pide fuentes a los complementos que las dan (en paralelo) y las guarda unos minutos."""

    def __init__(self, registry: addons.AddonRegistry, timeout: float = REQUEST_TIMEOUT) -> None:
        self.registry = registry
        self.timeout = timeout
        self._cache: dict[str, tuple[float, list[Source]]] = {}
        self._down: dict[str, float] = {}
        self.outcome: dict[str, str] = {}  # kind:video -> "ok" | "offline" | "no-addons" (para decir por qué no hay)  # complemento -> hasta cuándo no se le pregunta (no respondió)
        self._lock = threading.Lock()
        # Lo que se sabe del título y de cada fuente fuera de los complementos (los pone Watch):
        # facts(kind, video_id) -> {"original": "en" | "ja" | "es-ES"…, "titles": [...]} (de TMDB/Cinemeta);
        # tracks(key) -> las pistas de audio que mpv vio al reproducir esa fuente, o None.
        self.facts: Callable[[str, str], dict | None] = lambda kind, video_id: None
        self.tracks: Callable[[str], list[dict] | None] = lambda key: None

    def addons(self) -> list[addons.Addon]:
        return self.registry.addons()

    def _get_json(self, addon: addons.Addon, path: str) -> dict:
        return addons.fetch_json(f"{addon.base}/{path}", self.timeout)

    def _fetch(self, addon: addons.Addon, kind: str, video_id: str) -> list[dict] | None:
        """Las fuentes de un complemento; None si la red falló (para no recordar «no hay» 10 minutos)."""
        try:
            streams = self._get_json(addon, f"stream/{kind}/{quote(video_id, safe='')}.json").get("streams")
            streams = streams if isinstance(streams, list) else []
        except NET_ERRORS as exc:
            log.info("Sin fuentes de %s: %s", addon.name, exc)
            return None
        return [s for s in streams if isinstance(s, dict) and (s.get("url") or s.get("infoHash"))]

    def subtitles(self, kind: str, video_id: str, lang: str) -> list[str]:
        """URLs de subtítulos en tu idioma de tus addons (OpenSubtitles…), por si el video no trae."""
        codes = {lang, LANG_CODES.get(lang, lang)}
        urls = []
        for addon in self.addons():
            if not addon.handles("subtitles", kind, video_id):
                continue
            try:
                subs = self._get_json(addon, f"subtitles/{kind}/{quote(video_id, safe='')}.json").get("subtitles")
                subs = subs if isinstance(subs, list) else []
            except NET_ERRORS as exc:
                log.info("Sin subtítulos de %s: %s", addon.name, exc)
                continue
            urls += [s["url"] for s in subs if isinstance(s, dict) and isinstance(s.get("url"), str)
                     and s["url"].startswith(("http://", "https://")) and s.get("lang") in codes]
        return urls

    def find(self, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        key = cache_key(kind, video_id, prefs)
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        serving = [a for a in self.addons() if a.handles("stream", kind, video_id)]
        # Un complemento caído no se espera otra vez durante unos minutos (si todos lo están, se prueban).
        now = time.time()
        alive = [a for a in serving if self._down.get(a.url, 0) <= now] or serving
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
                self._down[addon.url] = now + DOWN_SECONDS
                log.info("%s no respondió a tiempo: se omite unos minutos", addon.name)
            else:
                self._down.pop(addon.url, None)
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
        for addon, streams in results:
            for stream in streams or []:
                index = stable_index(addon.url, stream)
                while index in seen:  # el mismo enlace dos veces: la segunda, el número siguiente
                    index = (index + 1) % 2**31
                try:
                    src = parse(stream, addon.name, addon.url, index, original)
                    hints = stream.get("behaviorHints") if isinstance(stream.get("behaviorHints"), dict) else {}
                    src.other_title = not mentions_title(titles, f"{src.release} {hints.get('filename') or ''}")
                    if (tracks := self.tracks(src.key)):
                        heard(src, tracks)
                    sources.append(src)
                except PARSE_ERRORS as exc:  # una fuente con datos raros se salta, no tumba la lista
                    log.info("Fuente rara de %s: %s", addon.name, exc)
                    continue
                seen.add(index)
        ranked = rank(sources, prefs, kind)
        self.outcome[f"{kind}:{video_id}"] = "no-addons" if not serving else "offline" if failed and not ranked else "ok"
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

    def get(self, kind: str, video_id: str, prefs: Preferences, index: int) -> Source | None:
        found = self.cached(kind, video_id, prefs)
        if not found:
            return None  # caducó (los enlaces de Real-Debrid vencen): quien llama busca otra vez
        return next((s for s in found if s.index == index), None)
