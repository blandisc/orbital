"""Una versión (Source) y cómo se lee lo que dice un complemento: tamaño, calidad, avisos de la cuenta, si es al instante."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from urllib.parse import urlparse

from .languages import FLAG_RE, MARKS, audio_languages, set_languages
from .rules import _WAITS, LANG_NAMES, RES, SEEDERS, SITE, SIZE, UNITS, _number


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


FIND_DEADLINE = _number(_WAITS, "find_deadline_s", 8.0)  # s para juntar fuentes: lo que llegó, se usa

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
