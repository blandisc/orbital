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
import zlib
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass, field
from urllib.parse import quote

from ..net import NET_ERRORS
from . import addons

log = logging.getLogger(__name__)

CACHE_SECONDS = 600
REQUEST_TIMEOUT = 15

# Banderas e indicios de idioma en los títulos de Torrentio y compañía.
FLAG_LANG = {
    "🇬🇧": "en", "🇺🇸": "en", "🇲🇽": "es", "🇪🇸": "es", "🇦🇷": "es", "🇫🇷": "fr", "🇮🇹": "it", "🇩🇪": "de",
    "🇵🇹": "pt", "🇧🇷": "pt", "🇷🇺": "ru", "🇯🇵": "ja", "🇰🇷": "ko", "🇨🇳": "zh", "🇮🇳": "hi", "🇵🇱": "pl",
    "🇹🇷": "tr", "🇺🇦": "uk", "🇳🇱": "nl", "🇨🇿": "cs", "🇸🇰": "sk", "🇭🇺": "hu", "🇬🇷": "el", "🇸🇪": "sv",
    "🇩🇰": "da", "🇳🇴": "no", "🇫🇮": "fi", "🇷🇴": "ro", "🇧🇬": "bg", "🇭🇷": "hr", "🇷🇸": "sr", "🇮🇱": "he",
    "🇸🇦": "ar", "🇹🇭": "th", "🇻🇳": "vi", "🇮🇩": "id", "🇱🇹": "lt", "🇱🇻": "lv", "🇪🇪": "et",
}
WORD_LANG = [
    (re.compile(r"\b(latino|castellano|spanish|español|espanol)\b", re.I), "es"),
    # «LAT», «CAST», «ESP» solo en mayúsculas: en minúsculas son palabras del título («Cast.Away»).
    (re.compile(r"\b(LAT|CAST|ESP)\b"), "es"),
    (re.compile(r"\b(french|vff|vf|vfq|truefrench)\b", re.I), "fr"),
    (re.compile(r"\b(ita|italian)\b", re.I), "it"),
    (re.compile(r"\b(german|deutsch|ger)\b", re.I), "de"),
    (re.compile(r"\b(rus|russian)\b", re.I), "ru"),
    (re.compile(r"\b(hindi)\b", re.I), "hi"),
    # "CZ dabing", "SK dabing", "PL lektor", "dublado": doblajes que antes pasaban por inglés.
    (re.compile(r"\b(cz|cze|czech|cesky|český|dabing)\b", re.I), "cs"),
    (re.compile(r"\b(sk|slovak|slovensky|slovenský)\b", re.I), "sk"),
    (re.compile(r"\b(pl|polish|polski|lektor)\b", re.I), "pl"),
    (re.compile(r"\b(hun|hungarian|magyar)\b", re.I), "hu"),
    (re.compile(r"\b(ptbr|pt-br|dublado|portuguese|portugues|português)\b", re.I), "pt"),
    (re.compile(r"\b(ukr|ukrainian)\b", re.I), "uk"),
    (re.compile(r"\b(turkish|türkçe|turkce)\b", re.I), "tr"),
    (re.compile(r"\b(arabic)\b", re.I), "ar"),
    (re.compile(r"\b(korean|kor)\b", re.I), "ko"),
    (re.compile(r"\b(nordic|swedish|danish|norwegian|finnish)\b", re.I), "sv"),
]
LANG_NAMES = {"en": "Inglés", "es": "Español", "fr": "Francés", "it": "Italiano", "de": "Alemán", "pt": "Portugués",
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

    def public(self) -> dict:
        """Lo que ve la interfaz: nada de URLs ni claves."""
        return {
            "id": self.index, "addon": self.addon, "resolution": self.resolution, "hdr": self.hdr,
            "size": self.size, "seeders": self.seeders, "site": self.site, "cached": self.cached,
            "debrid": self.debrid, "languages": [LANG_NAMES.get(l, l) for l in self.languages],
            "release": self.release, "tags": self.tags, "audio": self.audio_label,
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


def parse(stream: dict, addon: str, transport_url: str, index: int) -> Source:
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
    langs = [FLAG_LANG[f] for f in FLAG_LANG if f in text]
    for pattern, lang in WORD_LANG:
        if pattern.search(first) or pattern.search(filename):
            langs.append(lang)
    if re.search(r"\bdual\b", blob, re.I) and "en" not in langs:
        langs.append("en")  # "dual": casi siempre el original en inglés + el doblaje
    if re.search(r"\bmulti\b", blob, re.I) and "en" not in langs:
        langs.append("en")
    src.languages = list(dict.fromkeys(langs)) or ["en"]  # sin banderas: el idioma original
    src.release = first
    src.tags = [t for t, p in (("REMUX", r"\bremux\b"), ("BluRay", r"\bblu-?ray\b"), ("WEB-DL", r"\bweb-?(dl|rip)\b"),
                                ("x265", r"\b(x265|hevc|h\.?265)\b"), ("AV1", r"\bav1\b"), ("Atmos", r"\batmos\b"),
                                ("5.1", r"\b(5\.1|ddp?5|dts)"), ("Tráiler", r"\btrailer\b"), ("CAM", r"\b(cam|hdcam|ts|telesync)\b"))
                if re.search(p, blob, re.I)]
    return src


@dataclass
class Preferences:
    audio: str = "en"  # idioma de audio preferido
    quality: str = "1080p"  # resolución preferida ("4K" en la TV si quieres)


def score(src: Source, prefs: Preferences, kind: str = "movie") -> float:
    s = 0.0
    if src.cached:
        s += 1000  # arranca al instante
    elif src.debrid:
        s -= 400  # Real-Debrid aún tiene que descargarla
    # Idioma: solo el preferido es lo mejor; "dual" con el preferido, aceptable; sin él, al fondo.
    if src.languages == [prefs.audio]:
        s += 300
    elif prefs.audio in src.languages:
        s += 120
    else:
        s -= 600
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
    s += min(src.seeders, 500) / 10
    return s


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


class StreamFinder:
    """Pide fuentes a los complementos que las dan (en paralelo) y las guarda unos minutos."""

    def __init__(self, registry: addons.AddonRegistry, timeout: float = REQUEST_TIMEOUT) -> None:
        self.registry = registry
        self.timeout = timeout
        self._cache: dict[str, tuple[float, list[Source]]] = {}
        self._down: dict[str, float] = {}
        self.outcome: dict[str, str] = {}  # kind:video -> "ok" | "offline" | "no-addons" (para decir por qué no hay)  # complemento -> hasta cuándo no se le pregunta (no respondió)
        self._lock = threading.Lock()

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
        key = f"{kind}:{video_id}:{prefs.audio}:{prefs.quality}"
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
        for addon, streams in results:
            for stream in streams or []:
                index = stable_index(addon.url, stream)
                while index in seen:  # el mismo enlace dos veces: la segunda, el número siguiente
                    index = (index + 1) % 2**31
                try:
                    sources.append(parse(stream, addon.name, addon.url, index))
                except PARSE_ERRORS as exc:  # una fuente con datos raros se salta, no tumba la lista
                    log.info("Fuente rara de %s: %s", addon.name, exc)
                    continue
                seen.add(index)
        ranked = rank(sources, prefs, kind)
        self.outcome[f"{kind}:{video_id}"] = "no-addons" if not addons else "offline" if failed and not ranked else "ok"
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

    def get(self, kind: str, video_id: str, prefs: Preferences, index: int) -> Source | None:
        hit = self._cache.get(f"{kind}:{video_id}:{prefs.audio}:{prefs.quality}")
        if not hit or time.time() - hit[0] >= CACHE_SECONDS:
            return None  # caducó (los enlaces de Real-Debrid vencen): quien llama busca otra vez
        return next((s for s in hit[1] if s.index == index), None)
