"""La app del iPhone: cómo se conecta con esta consola (un QR) y qué se lleva de ella.

El QR de «Conectar iPhone» lleva `orbital-ios://pair?u=<dirección de Tailscale>&t=<token>`: lo escaneas con la cámara
del iPhone y la app queda conectada sin escribir nada. Esa dirección es la del túnel de Alexa (el puerto público, que
siempre pide el token). Con eso la app toma de aquí las claves de «Para ti» y la sesión de Trakt (la renueva la
consola: el iPhone nunca guarda la parte que la renueva, así que las dos no se pisan).
"""

from __future__ import annotations

from urllib.parse import quote, urlencode

from . import alexa_setup
from .qrcodegen import QrCode

SCHEME = "orbital-ios://pair"


def pair_link(url: str, token: str) -> str:
    return f"{SCHEME}?{urlencode({'u': url, 't': token}, quote_via=quote)}"


def pair_info(config, tailscale_url=None) -> dict:
    """Si se puede conectar el iPhone y, si no, qué falta (en palabras)."""
    token = config.server.token
    if not token or config.server.token_is_ephemeral:
        return {"ready": False, "reason": "Primero configura Alexa (Ajustes › Mantenimiento): el iPhone usa el mismo token."}
    url = (tailscale_url or alexa_setup.tailscale_url)()
    if not url:
        return {"ready": False, "reason": "No encontré Tailscale. El iPhone entra por el mismo túnel que Alexa: enciéndelo y vuelve a intentar."}
    return {"ready": True, "host": url.removeprefix("https://"), "link": pair_link(url, token)}


def qr_svg(text: str, *, border: int = 2) -> str:
    """El QR como SVG en negro sobre blanco (como lo leen todas las cámaras); la pantalla lo pone sobre su tarjeta."""
    qr = QrCode.encode_text(text, QrCode.Ecc.MEDIUM)
    size = qr.get_size() + border * 2
    path = "".join(f"M{x + border},{y + border}h1v1h-1z" for y in range(qr.get_size()) for x in range(qr.get_size()) if qr.get_module(x, y))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" shape-rendering="crispEdges">'
            f'<rect width="100%" height="100%" fill="#fff"/><path d="{path}" fill="#000"/></svg>')


def trakt_session(trakt) -> dict | None:
    """Una sesión de Trakt vigente para el iPhone (renovada aquí si estaba por caducar), sin la parte que la renueva."""
    if trakt is None or not trakt.linked:
        return None
    try:
        access = trakt.access_token()
    except Exception:  # sin internet o la sesión se cayó: el iPhone lo intenta luego
        return None
    return {"access_token": access, "expires_at": trakt.session_expiry()} if access else None
