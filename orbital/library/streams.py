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
import json
import logging
import re
import threading
import time
import urllib.error
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from urllib.parse import quote

log = logging.getLogger(__name__)

CACHE_SECONDS = 600
REQUEST_TIMEOUT = 15

# Banderas e indicios de idioma en los títulos de Torrentio y compañía.
FLAG_LANG = {
    "🇬🇧": "en", "🇺🇸": "en", "🇲🇽": "es", "🇪🇸": "es", "🇦🇷": "es", "🇫🇷": "fr", "🇮🇹": "it", "🇩🇪": "de",
    "🇵🇹": "pt", "🇧🇷": "pt", "🇷🇺": "ru", "🇯🇵": "ja", "🇰🇷": "ko", "🇨🇳": "zh", "🇮🇳": "hi", "🇵🇱": "pl",
    "🇹🇷": "tr", "🇺🇦": "uk", "🇳🇱": "nl",
}
WORD_LANG = [
    (re.compile(r"\b(lat|latino|castellano|spanish|español|espanol|esp|cast)\b", re.I), "es"),
    (re.compile(r"\b(french|vff|vf|truefrench)\b", re.I), "fr"),
    (re.compile(r"\b(ita|italian)\b", re.I), "it"),
    (re.compile(r"\b(german|deutsch|ger)\b", re.I), "de"),
    (re.compile(r"\b(rus|russian)\b", re.I), "ru"),
    (re.compile(r"\b(hindi)\b", re.I), "hi"),
]
LANG_NAMES = {"en": "Inglés", "es": "Español", "fr": "Francés", "it": "Italiano", "de": "Alemán", "pt": "Portugués",
              "ru": "Ruso", "ja": "Japonés", "ko": "Coreano", "zh": "Chino", "hi": "Hindi", "pl": "Polaco",
              "tr": "Turco", "uk": "Ucraniano", "nl": "Neerlandés"}
# ISO 639-2, como etiquetan los addons de subtítulos (OpenSubtitles: "eng", "spa"…).
LANG_CODES = {"en": "eng", "es": "spa", "fr": "fre", "it": "ita", "de": "ger", "pt": "por", "ja": "jpn"}
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

    def public(self) -> dict:
        """Lo que ve la interfaz: nada de URLs ni claves."""
        return {
            "id": self.index, "addon": self.addon, "resolution": self.resolution, "hdr": self.hdr,
            "size": self.size, "seeders": self.seeders, "site": self.site, "cached": self.cached,
            "debrid": self.debrid, "languages": [LANG_NAMES.get(l, l) for l in self.languages],
            "release": self.release, "tags": self.tags,
        }


def parse(stream: dict, addon: str, transport_url: str, index: int) -> Source:
    name = str(stream.get("name") or "")
    text = str(stream.get("title") or stream.get("description") or "")
    blob = f"{name}\n{text}"
    first = text.split("\n", 1)[0].strip()
    filename = (stream.get("behaviorHints") or {}).get("filename") or ""
    src = Source(index=index, addon=addon.split()[0] if addon else "", stream=stream, transport_url=transport_url)
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
        src.size = int(float(m.group(1).replace(",", "")) * UNITS[m.group(2).upper()])
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
    """Pide fuentes a los addons de la cuenta (en paralelo) y las guarda unos minutos."""

    def __init__(self, stremio_client, timeout: float = REQUEST_TIMEOUT) -> None:
        self.client = stremio_client
        self.timeout = timeout
        self._addons: tuple[float, list[dict]] = (0.0, [])
        self._cache: dict[str, tuple[float, list[Source]]] = {}
        self._lock = threading.Lock()

    def addons(self, auth_key: str) -> list[dict]:
        if time.time() - self._addons[0] < CACHE_SECONDS:
            return self._addons[1]
        result = self.client.request("addonCollectionGet", {"authKey": auth_key, "update": True})
        addons = []
        for addon in (result.get("addons") or []) if isinstance(result, dict) else []:
            manifest = addon.get("manifest") or {}
            resources = [r if isinstance(r, str) else (r or {}).get("name") for r in manifest.get("resources", [])]
            if {"stream", "subtitles"} & set(resources) and addon.get("transportUrl"):
                addons.append({"name": manifest.get("name") or "Addon", "url": addon["transportUrl"],
                               "types": manifest.get("types") or [], "resources": resources})
        self._addons = (time.time(), addons)
        return addons

    def _get_json(self, addon: dict, path: str) -> dict:
        base = addon["url"].rsplit("/manifest.json", 1)[0]
        req = urllib.request.Request(f"{base}/{path}", headers={"User-Agent": "Orbital"})
        with urllib.request.urlopen(req, timeout=self.timeout) as res:
            return json.load(res) or {}

    def _fetch(self, addon: dict, kind: str, video_id: str) -> list[dict]:
        try:
            streams = self._get_json(addon, f"stream/{kind}/{quote(video_id)}.json").get("streams") or []
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            log.info("Sin fuentes de %s: %s", addon["name"], exc)
            return []
        return [s for s in streams if isinstance(s, dict) and (s.get("url") or s.get("infoHash"))]

    def subtitles(self, auth_key: str, kind: str, video_id: str, lang: str) -> list[str]:
        """URLs de subtítulos en tu idioma de tus addons (OpenSubtitles…), por si el video no trae."""
        codes = {lang, LANG_CODES.get(lang, lang)}
        urls = []
        for addon in self.addons(auth_key):
            if "subtitles" not in addon.get("resources", []):
                continue
            try:
                subs = self._get_json(addon, f"subtitles/{kind}/{quote(video_id)}.json").get("subtitles") or []
            except (urllib.error.URLError, TimeoutError, ValueError) as exc:
                log.info("Sin subtítulos de %s: %s", addon["name"], exc)
                continue
            urls += [s["url"] for s in subs if isinstance(s, dict) and s.get("url") and s.get("lang") in codes]
        return urls

    def find(self, auth_key: str, kind: str, video_id: str, prefs: Preferences) -> list[Source]:
        key = f"{kind}:{video_id}:{prefs.audio}:{prefs.quality}"
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.time() - hit[0] < CACHE_SECONDS:
                return hit[1]
        addons = [a for a in self.addons(auth_key)
                  if "stream" in a.get("resources", ["stream"]) and (not a["types"] or kind in a["types"])]
        with ThreadPoolExecutor(max_workers=max(1, len(addons))) as pool:
            results = list(pool.map(lambda a: (a, self._fetch(a, kind, video_id)), addons))
        sources, index = [], 0
        for addon, streams in results:
            for stream in streams:
                sources.append(parse(stream, addon["name"], addon["url"], index))
                index += 1
        ranked = rank(sources, prefs, kind)
        with self._lock:
            self._cache[key] = (time.time(), ranked)
        return ranked

    def get(self, kind: str, video_id: str, prefs: Preferences, index: int) -> Source | None:
        hit = self._cache.get(f"{kind}:{video_id}:{prefs.audio}:{prefs.quality}")
        return next((s for s in hit[1] if s.index == index), None) if hit else None
