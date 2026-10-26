"""Subtítulos de internet como los ve el iPhone (OrbitalCore · SubtitleVersions.swift y StreamFinder.swift), en Python.

Cada subtítulo de un complemento (OpenSubtitles…) trae, si el complemento lo cuenta, para qué copia se hizo («…WEB-DL-NTb»)
y cuántas veces se bajó. Con eso se ordenan como en el iPhone: primero los hechos para tu copia (mismo grupo y tipo de
fuente), luego los de tu misma versión, luego los más bajados. Con la huella de OpenSubtitles del archivo (su tamaño y
la suma de los primeros y últimos 64 KB) el complemento pone primero los que van a tiempo con esa copia exacta.
"""

from __future__ import annotations

import re
import struct
import urllib.request
from dataclasses import dataclass

from ..net import NET_ERRORS

CHUNK = 65_536
BUILTIN = "https://opensubtitles-v3.strem.io"  # OpenSubtitles, siempre (como el iPhone), aunque no lo tengas instalado

# Para sordos (SDH/CC) y forzados (solo carteles): se esconden al probar, como el iPhone (decisión de Fernando).
HIDDEN = re.compile(r"\b(sdh|cc|hi|hoh|forced|forzados?|signs?|songs?|carteles|signs\s*&\s*songs|for(eign)?\s*parts?)\b"
                    r"|sordos|closed caption", re.I)

ALIASES = {"pob": "pt", "pb": "pt", "spn": "es", "ea": "es", "ze": "zh", "zht": "zh", "zhe": "zh", "chi": "zh", "fre": "fr",
           "ger": "de", "dut": "nl", "gre": "el", "per": "fa", "rum": "ro", "cze": "cs", "slo": "sk", "alb": "sq", "arm": "hy",
           "baq": "eu", "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "mao": "mi", "may": "ms", "tib": "bo", "wel": "cy",
           "english": "en", "spanish": "es", "español": "es", "latino": "es",
           "eng": "en", "spa": "es", "por": "pt", "fra": "fr", "deu": "de", "ita": "it", "jpn": "ja", "kor": "ko", "rus": "ru",
           "zho": "zh", "pol": "pl", "tur": "tr", "ara": "ar", "heb": "he", "hin": "hi", "nld": "nl", "swe": "sv", "nor": "no",
           "dan": "da", "fin": "fi", "ces": "cs", "hun": "hu", "ron": "ro", "ell": "el", "ukr": "uk", "vie": "vi", "tha": "th",
           "ind": "id", "bul": "bg", "hrv": "hr", "srp": "sr", "slk": "sk", "slv": "sl", "est": "et", "lav": "lv", "lit": "lt"}


def language(raw: str | None) -> str | None:
    """Cualquier etiqueta de idioma («spa», «es-419», «pob», «English») → ISO 639-1 («es»); None si no se reconoce."""
    text = (raw or "").strip().lower()
    if not text:
        return None
    text = re.split(r"[-_]", text, maxsplit=1)[0]
    if text in ALIASES:
        return ALIASES[text]
    return text if len(text) == 2 and text.isalpha() else None


@dataclass(frozen=True)
class ReleaseTraits:
    """Lo que dice el nombre de una copia que sirve para saber si un subtítulo le va: el tipo de fuente y el grupo."""
    source: str | None = None  # «WEB-DL», «WEBRip», «BluRay», «HDTV», «DVD»
    group: str | None = None  # «ntb», «flux» (en minúsculas)

    @staticmethod
    def parse(name: str | None) -> ReleaseTraits:
        if not name:
            return ReleaseTraits()
        base = re.sub(r"\.[A-Za-z0-9]{1,4}$", "", name.strip())
        lower = base.lower()
        source = None
        for kind, pattern in (("WEB-DL", r"web[ ._-]?dl|\bweb\b|\bamzn\b|\bnf\b"), ("WEBRip", r"web[ ._-]?rip"),
                              ("BluRay", r"blu[ ._-]?ray|bdrip|brrip|bdremux|\bremux\b"), ("HDTV", r"hdtv|pdtv"),
                              ("DVD", r"dvd[ ._-]?rip|\bdvd\b")):
            if re.search(pattern, lower):
                source = kind  # el último que coincide gana (como el iPhone)
        group = None
        if "-" in base:
            tail = base.rsplit("-", 1)[1].strip(" []()")
            if tail and len(tail) <= 15 and tail.isalnum() and tail.lower() not in ("dl", "rip"):
                group = tail.lower()
        return ReleaseTraits(source, group)

    def match(self, other: ReleaseTraits) -> int:
        """0 nada en común; 1 mismo tipo de fuente; 2 mismo grupo; 3 los dos."""
        return (1 if self.source and self.source == other.source else 0) + (2 if self.group and self.group == other.group else 0)


def hides(option: dict) -> bool:
    return bool(option.get("hearing_impaired") or option.get("forced") or HIDDEN.search(option.get("release") or ""))


def ranked(options: list[dict], lang: str, release: str | None) -> list[dict]:
    """Los de ese idioma, sin sordos ni forzados, en el orden del iPhone: tu copia primero, luego los más bajados (y,
    empatados, como los dio el complemento: con la huella, los de tu archivo exacto van primero)."""
    mine = ReleaseTraits.parse(release)
    picked = [(i, o) for i, o in enumerate(options) if language(o.get("lang")) == lang and not hides(o)]
    for _, o in picked:
        o["match"] = mine.match(ReleaseTraits.parse(o.get("release")))
    picked.sort(key=lambda p: (-p[1]["match"], -(p[1].get("downloads") or -1), p[0]))
    return [o for _, o in picked]


def badge(match: int) -> str:
    """Lo que dice la franja: por qué está ahí, sin prometer de más (lo mismo que el iPhone)."""
    return "Hecho para tu copia" if match >= 2 else "Misma versión" if match == 1 else ""


# --- la huella de OpenSubtitles ---------------------------------------------------------------------------------------
def fingerprint(head: bytes, tail: bytes, size: int) -> tuple[str, int] | None:
    """(huella en hexadecimal, tamaño): la suma de 64 bits del tamaño y de los primeros y últimos 64 KB, en palabras de
    8 bytes little-endian (la de OpenSubtitles)."""
    if len(head) < CHUNK or len(tail) < CHUNK or size < CHUNK:
        return None
    total = size
    for data in (head[:CHUNK], tail[-CHUNK:]):
        for (word,) in struct.iter_unpack("<Q", data):
            total = (total + word) & 0xFFFFFFFFFFFFFFFF
    return f"{total:016x}", size


def remote_fingerprint(url: str, timeout: float = 10) -> tuple[str, int] | None:
    """La huella de un video en línea con dos pedidos de 64 KB (el principio y el final). None si el servidor no los da."""
    def part(first: int, last: int) -> tuple[bytes, str]:
        request = urllib.request.Request(url, headers={"Range": f"bytes={first}-{last}", "User-Agent": "Orbital"})
        with urllib.request.urlopen(request, timeout=timeout) as reply:  # noqa: S310 - la URL es la de la fuente que ves
            if reply.status != 206:
                raise OSError(f"HTTP {reply.status}")
            return reply.read(CHUNK), reply.headers.get("Content-Range") or ""
    try:
        head, span = part(0, CHUNK - 1)
        size = int(span.rsplit("/", 1)[1])
        tail, _ = part(size - CHUNK, size - 1)
    except (*NET_ERRORS, OSError, ValueError, IndexError):
        return None
    return fingerprint(head, tail, size)


def parse_options(subs: list, source: str) -> list[dict]:
    """La respuesta `subtitles` de un complemento → opciones con lo que cuente de más (la copia, las descargas, si es
    para sordos o forzado), como el iPhone."""
    out = []
    for sub in subs if isinstance(subs, list) else []:
        if not isinstance(sub, dict):
            continue
        url, lang = sub.get("url"), sub.get("lang")
        if not isinstance(url, str) or not url.startswith(("http://", "https://")) or not isinstance(lang, str):
            continue
        release = next((sub[k] for k in ("release", "releaseName", "release_name", "title") if isinstance(sub.get(k), str)), None)
        downloads = next((sub[k] for k in ("downloads", "download_count") if isinstance(sub.get(k), int)), None)
        out.append({"url": url, "lang": lang, "release": release, "downloads": downloads, "source": source,
                    "hearing_impaired": bool(sub.get("hearing_impaired") or sub.get("hearingImpaired")),
                    "forced": bool(sub.get("foreign_parts_only") or sub.get("forced"))})
    return out


TIMESTAMP = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})")


def last_cue(text: str) -> float | None:
    """El último momento con subtítulo (s) de un .srt/.vtt/.ass: para saber si es de otra edición del video."""
    found = TIMESTAMP.findall(text[-20_000:])
    if not found:
        return None
    h, m, s, ms = found[-1]
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms.ljust(3, "0")) / 1000


# Otra edición: el subtítulo se hizo para una copia más lenta (23.976 cuadros por segundo) y tú ves la de 25 (PAL): sus
# tiempos se pasan del final del video. `sub-speed` de mpv multiplica los tiempos del subtítulo.
PAL_SPEED = 23.976 / 25


def edition_speed(video_seconds: float | None, subtitle_end: float | None) -> float | None:
    """La velocidad (`sub-speed`) que lo pone a tiempo si es de otra edición; None si parece de la tuya. Solo el caso
    seguro: el subtítulo sigue después de que acaba el video (al revés no se distingue de unos créditos largos)."""
    if not video_seconds or not subtitle_end or video_seconds < 600:
        return None
    if subtitle_end > video_seconds + 5 and subtitle_end * PAL_SPEED <= video_seconds:
        return PAL_SPEED
    return None
