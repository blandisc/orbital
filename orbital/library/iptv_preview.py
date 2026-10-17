"""La vista previa de un canal (TV en vivo · la miniatura en vivo y sin sonido del canal enfocado).

La interfaz nunca ve la dirección de un canal: pide `preview.m3u8?id=…` y Orbital trae la lista HLS del canal (con sus
cabeceras, si las pide), se queda con la calidad más baja (la miniatura no necesita más y gasta menos internet) y
reescribe cada pedazo para que también pase por Orbital (`preview-seg?…`, firmado: no es un proxy abierto). Así se ven
también los canales que no dejan que una página los lea directo (sin permiso CORS) o que piden su propio User-Agent.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import threading
import time
import urllib.request
from urllib.parse import quote, urljoin

from ..net import read_body
from .iptv import Channel

PLAYLIST_LIMIT = 512 * 1024
SEGMENT_LIMIT = 12 * 1024 * 1024
TIMEOUT = 8
VARIANT_TTL = 60  # la calidad elegida de cada canal se recuerda un minuto (la lista en vivo se pide cada pocos segundos)
_SECRET = secrets.token_bytes(32)  # por arranque: las firmas de un Orbital anterior no sirven
_URI_ATTR = re.compile(r'URI="([^"]+)"')


class PreviewError(Exception):
    """El canal no dio una lista HLS que se pueda enseñar en miniatura."""


def sign(channel_id: str, url: str) -> str:
    return hmac.new(_SECRET, f"{channel_id}\n{url}".encode(), hashlib.sha256).hexdigest()[:32]


def valid(channel_id: str, url: str, signature: str) -> bool:
    return hmac.compare_digest(sign(channel_id, url), signature or "")


def _headers(channel: Channel) -> dict:
    headers = {"User-Agent": channel.user_agent or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Orbital"}
    if channel.referrer:
        headers["Referer"] = channel.referrer
    return headers


ORIGIN = "http://127.0.0.1:8710"  # la página de Orbital: si el canal le da permiso CORS, la tele baja el video directo


def fetch(channel: Channel, url: str, limit: int) -> tuple[bytes, str, str, bool]:
    """(contenido, dirección final tras redirecciones, tipo, ¿deja que una página lo lea directo?)."""
    req = urllib.request.Request(url, headers={**_headers(channel), "Origin": ORIGIN})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
        cors = res.headers.get("Access-Control-Allow-Origin", "") in ("*", ORIGIN)
        return read_body(res, timeout=TIMEOUT, limit=limit), res.geturl(), res.headers.get("Content-Type", ""), cors


def lowest_variant(text: str, base: str) -> str | None:
    """En una lista maestra, la dirección de la calidad más baja (por BANDWIDTH). None si no es maestra."""
    lines = text.splitlines()
    best: tuple[int, str] | None = None
    for i, line in enumerate(lines):
        if not line.startswith("#EXT-X-STREAM-INF"):
            continue
        bandwidth = re.search(r"BANDWIDTH=(\d+)", line)
        uri = next((u.strip() for u in lines[i + 1:] if u.strip() and not u.startswith("#")), None)
        if uri:
            value = int(bandwidth.group(1)) if bandwidth else 1 << 40
            if best is None or value < best[0]:
                best = (value, urljoin(base, uri))
    return best[1] if best else None


def rewrite(text: str, base: str, channel_id: str, direct: bool = False) -> str:
    """Cada pedazo (y las llaves o el mapa de inicio) apunta a Orbital, firmado; o, si el canal deja que la página lo lea
    (`direct`), a su dirección completa: la tele lo baja directo, más rápido y sin cargar a Orbital."""
    def local(uri: str) -> str:
        absolute = urljoin(base, uri.strip())
        if direct:
            return absolute
        return f"preview-seg?c={quote(channel_id, safe='')}&u={quote(absolute, safe='')}&s={sign(channel_id, absolute)}"

    out = []
    for line in text.splitlines():
        if line.startswith("#"):
            out.append(_URI_ATTR.sub(lambda m: f'URI="{local(m.group(1))}"', line) if 'URI="' in line else line)
        elif line.strip():
            out.append(local(line))
        else:
            out.append(line)
    return "\n".join(out) + "\n"


class Previews:
    def __init__(self) -> None:
        self._variants: dict[str, tuple[float, str]] = {}
        self._lock = threading.Lock()

    def playlist(self, channel: Channel) -> str:
        """La lista de la calidad más baja del canal, con los pedazos pasando por Orbital."""
        with self._lock:
            cached = self._variants.get(channel.id)
        url = cached[1] if cached and time.monotonic() - cached[0] < VARIANT_TTL else channel.url
        body, final, _, cors = fetch(channel, url, PLAYLIST_LIMIT)
        text = body.decode("utf-8", "replace")
        if "#EXTM3U" not in text[:1024]:
            raise PreviewError("no es una lista HLS")
        variant = lowest_variant(text, final)
        if variant:
            with self._lock:
                self._variants[channel.id] = (time.monotonic(), variant)
            body, final, _, cors = fetch(channel, variant, PLAYLIST_LIMIT)
            text = body.decode("utf-8", "replace")
            if lowest_variant(text, final):
                raise PreviewError("lista maestra anidada")
        # Directo solo si el canal da permiso y no pide cabeceras propias (la página no puede mandarlas).
        direct = cors and not channel.user_agent and not channel.referrer
        return rewrite(text, final, channel.id, direct=direct)

    def segment(self, channel: Channel, url: str):
        """(pedazos, tipo): se van pasando mientras llegan. Antes se bajaba el pedazo entero (hasta 4 MB en un canal sin
        calidades) y la miniatura tardaba tanto que se daba por perdida."""
        res = urllib.request.urlopen(urllib.request.Request(url, headers=_headers(channel)), timeout=TIMEOUT)
        # Pedazos grandes (menos vueltas entre hilos): el que pasa por aquí es un canal sin permiso CORS o con cabeceras.
        kind = res.headers.get("Content-Type", "") or "video/mp2t"

        def chunks():
            sent = 0
            try:
                while chunk := res.read(256 * 1024):
                    sent += len(chunk)
                    if sent > SEGMENT_LIMIT:
                        return
                    yield chunk
            finally:
                res.close()
        return chunks(), kind
