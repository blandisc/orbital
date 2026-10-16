"""TV en vivo: la lista de canales (M3U de iptv-org), leída y puesta en español.

Una lista M3U es texto: por canal, una línea `#EXTINF` con sus datos (nombre, logo, categorías), a veces
`#EXTVLCOPT` con el Referer o el User-Agent que pide ese canal, y debajo su dirección:

    #EXTINF:-1 tvg-id="Azteca7.mx@SD" tvg-logo="https://…/logo.png" group-title="General;News",Azteca 7 (720p) [Not 24/7]
    #EXTVLCOPT:http-referrer=https://sitio.mx/
    https://…/playlist.m3u8

La lista se descarga con net.py y se guarda una copia en disco: sin Internet se usa la última que se trajo.
"""

from __future__ import annotations

import logging
import re
import unicodedata
import urllib.request
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from ..net import NET_ERRORS, read_body

log = logging.getLogger(__name__)

SOURCE = "https://iptv-org.github.io/iptv/countries/mx.m3u"
MAX_LIST_BYTES = 8 * 1024 * 1024  # la de México pesa ~30 KB; esto solo corta una respuesta absurda
OTHER = "Otros"

# Las categorías de iptv-org (en inglés) en palabras de la consola. «Undefined» es lo que no trae categoría.
CATEGORY_NAMES = {
    "animation": "Animación", "auto": "Autos", "business": "Negocios", "classic": "Clásicos", "comedy": "Comedia",
    "cooking": "Cocina", "culture": "Cultura", "documentary": "Documentales", "education": "Educación",
    "entertainment": "Entretenimiento", "family": "Familia", "general": "General", "interactive": "Interactivo",
    "kids": "Infantil", "legislative": "Legislativo", "lifestyle": "Estilo de vida", "movies": "Películas",
    "music": "Música", "news": "Noticias", "outdoor": "Aire libre", "public": "Público", "relax": "Relax",
    "religious": "Religión", "science": "Ciencia", "series": "Series", "shop": "Compras", "sports": "Deportes",
    "travel": "Viajes", "weather": "Clima", "undefined": OTHER,
}
ADULT = {"xxx"}  # no se muestra nunca: es una consola de sala
# Cómo se ordenan las pestañas: primero lo que más se ve; el resto, por nombre; «Otros», al final.
CATEGORY_ORDER = ["General", "Noticias", "Entretenimiento", "Deportes", "Películas", "Series", "Infantil", "Animación",
                  "Música", "Cultura", "Educación", "Documentales"]

QUALITY = re.compile(r"\s*\((\d{3,4}[pi])\)", re.I)
TAG = re.compile(r"\s*\[([^\]]+)\]")
# Lo que la lista agrega al nombre y no le dice nada a quien ve la tele: el país, la región y la señal de la estación.
COUNTRY = re.compile(r"\s*\((?:Mexico|México|MX)\)", re.I)
REGION_TAIL = re.compile(r"\s+(?:Latin America|Latinoam[eé]rica|Latam)(?:\s+(?:Mexico|México|North|South))*(?:\s+HD)?$|\s+HD$", re.I)
CALLSIGN = re.compile(r"\s+X[A-Z]{2,4}(?:-(?:TDT|TV|DT))?$")


def display_name(name: str) -> str:
    """«Canal 5 (Mexico)» → «Canal 5»; «Discovery Kids Latin America Mexico» → «Discovery Kids»;
    «Canal 5 (Mexico) XET-TDT» → «Canal 5». «Presumiendo Mexico» se queda: ahí «Mexico» es parte del nombre."""
    clean = COUNTRY.sub("", name)
    for _ in range(3):  # «… XET-TDT HD», «… Latin America North HD»: varias colas
        clean = REGION_TAIL.sub("", CALLSIGN.sub("", clean)).strip(" -·")
    return clean or name


def tidy_names(channels: list[Channel]) -> list[Channel]:
    """El nombre limpio de cada canal; si dos quedarían iguales («Disney Channel Latin America Mexico» y «… North»),
    esos dos se quedan con solo el país quitado, para distinguirlos. El id no cambia (su número y su salud siguen)."""
    clean = [display_name(c.name) for c in channels]
    seen = Counter(fold(n) for n in clean)
    for c, n in zip(channels, clean, strict=True):
        c.name = n if seen[fold(n)] == 1 else (COUNTRY.sub("", c.name).strip(" -·") or c.name)
    return channels
# Solo desde el principio de una palabra: sin el (?<!…), una línea de 20 000 letras sin «=» tardaba 4 s (se
# probaba cada letra como inicio de un atributo), y la lista viene de internet.
ATTRIBUTE = re.compile(r'(?<![\w.-])([\w.-]+)="([^"]*)"')
MAX_LINE = 8192  # una línea más larga no es de un canal de verdad: se corta
HTTP = re.compile(r"^https?://\S+$", re.I)
CONTROL = re.compile(r"[\x00-\x1f\x7f]")


@dataclass
class Channel:
    id: str
    name: str
    url: str
    logo: str | None = None
    categories: list[str] = field(default_factory=lambda: [OTHER])
    quality: str | None = None  # «1080p»
    tags: list[str] = field(default_factory=list)  # «Not 24/7», «Geo-blocked»
    referrer: str | None = None
    user_agent: str | None = None

    @property
    def category(self) -> str:
        return self.categories[0]

    def public(self) -> dict:
        """Lo que ve la interfaz. Sin la dirección ni las cabeceras: la interfaz pide «abre este canal»."""
        return {"id": self.id, "name": self.name, "logo": self.logo, "categories": self.categories,
                "quality": self.quality}


def translate(group: str | None) -> list[str]:
    """«Animation;Kids» -> ["Animación", "Infantil"]. Sin categoría (o «Undefined»): ["Otros"]."""
    names: list[str] = []
    for raw in str(group or "").split(";"):
        key = raw.strip().lower()
        if not key:
            continue
        name = CATEGORY_NAMES.get(key) or key[:1].upper() + key[1:]
        if name not in names:
            names.append(name)
    if len(names) > 1 and OTHER in names:
        names.remove(OTHER)  # «Undefined;News» ya sabe qué es
    return names or [OTHER]


def category_sort_key(title: str) -> tuple[int, int, str]:
    if title == OTHER:
        return (2, 0, "")
    if title in CATEGORY_ORDER:
        return (0, CATEGORY_ORDER.index(title), "")
    return (1, 0, fold(title))


def fold(text: str) -> str:
    """Para ordenar y comparar: sin acentos ni mayúsculas."""
    plain = unicodedata.normalize("NFD", str(text or "")).encode("ascii", "ignore").decode()
    return plain.lower().strip()


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", fold(text)).strip("-") or "canal"


def _header(value: str | None, *, url: bool = False) -> str | None:
    """Un Referer o User-Agent de la lista: texto de una línea (o una dirección http). Lo demás se ignora."""
    value = (value or "").strip()
    if not value or CONTROL.search(value) or len(value) > 300:
        return None
    return value if not url or HTTP.match(value) else None


def _title(line: str) -> tuple[dict[str, str], str]:
    """Los atributos de una línea #EXTINF y el nombre (lo que sigue a la primera coma después de ellos:
    los atributos van entre comillas y pueden llevar comas)."""
    body = line.split(":", 1)[1] if ":" in line else ""
    attrs, end = {}, 0
    for match in ATTRIBUTE.finditer(body):
        attrs[match.group(1).lower()] = match.group(2)
        end = match.end()
    comma = body.find(",", end)
    return attrs, body[comma + 1:].strip() if comma >= 0 else ""


def parse_m3u(text: str) -> list[Channel]:
    """Los canales de una lista M3U. Solo direcciones http(s): una lista no puede mandar a mpv a abrir un
    archivo del equipo. Una línea rara se salta; nunca tumba el resto."""
    channels: list[Channel] = []
    taken: set[str] = set()
    pending: dict | None = None
    for raw in text.lstrip("﻿").splitlines():
        line = raw[:MAX_LINE].strip()
        if line.startswith("#EXTINF"):
            attrs, title = _title(line)
            pending = {"attrs": attrs, "title": title, "referrer": None, "user_agent": None}
        elif line.startswith("#EXTVLCOPT:") and pending is not None:
            key, _, value = line[len("#EXTVLCOPT:"):].partition("=")
            key = key.strip().lower()
            if key in ("http-referrer", "http-referer"):
                pending["referrer"] = _header(value, url=True)
            elif key == "http-user-agent":
                pending["user_agent"] = _header(value)
        elif line and not line.startswith("#") and pending is not None:
            channel = _channel(pending, line, taken)
            pending = None
            if channel is not None:
                channels.append(channel)
    return tidy_names(channels)


def _channel(pending: dict, url: str, taken: set[str]) -> Channel | None:
    attrs, title = pending["attrs"], pending["title"]
    if not HTTP.match(url) or not title:
        return None
    raw_groups = {g.strip().lower() for g in attrs.get("group-title", "").split(";")}
    if raw_groups & ADULT:
        return None
    quality = QUALITY.search(title)
    tags = [t.strip() for t in TAG.findall(title)]
    name = TAG.sub("", QUALITY.sub("", title)).strip(" -·") or title
    key = attrs.get("tvg-id") or slug(name)
    channel_id, n = key, 1
    while channel_id in taken:  # el mismo id en dos canales: el segundo se distingue
        n += 1
        channel_id = f"{key}~{n}"
    taken.add(channel_id)
    logo = attrs.get("tvg-logo", "").strip()
    return Channel(id=channel_id, name=name, url=url, logo=logo if HTTP.match(logo) else None,
                   categories=translate(attrs.get("group-title")), quality=quality.group(1).lower() if quality else None,
                   tags=tags, referrer=pending["referrer"], user_agent=pending["user_agent"])


# --- descargar y guardar una copia ---------------------------------------------------------------
def download(url: str = SOURCE, *, timeout: float = 20) -> str:
    """El texto de la lista. Lanza NET_ERRORS si no hay red o la respuesta no sirve."""
    req = urllib.request.Request(url, headers={"User-Agent": "Orbital"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return read_body(res, timeout=timeout, limit=MAX_LIST_BYTES).decode("utf-8", "replace")


def read_copy(path: Path | None) -> list[Channel]:
    """La copia en disco (vacía si no hay o está dañada)."""
    if path is None:
        return []
    try:
        return parse_m3u(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []


def save_copy(path: Path | None, text: str) -> None:
    if path is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)
    except OSError as exc:
        log.warning("No pude guardar la copia de la lista de canales: %s", exc)


def fetch_list(copy: Path | None, *, download_fn: Callable[[], str] = download) -> tuple[list[Channel], bool]:
    """(canales, de_internet). Se baja la lista nueva; si no hay red (o lo que llegó no es una lista, como la
    página de «inicia sesión» de un Wi-Fi público) se usa la copia de la última vez. Sin copia: lista vacía."""
    try:
        text = download_fn()
        fresh = parse_m3u(text) if text.lstrip("﻿").lstrip().startswith("#EXTM3U") else []
        if fresh:
            save_copy(copy, text)
            return fresh, True
        log.warning("La lista de canales llegó vacía o no es una lista M3U: uso la copia guardada")
    except NET_ERRORS as exc:
        log.info("Sin lista de canales nueva (%s): uso la copia guardada", exc)
    return read_copy(copy), False
