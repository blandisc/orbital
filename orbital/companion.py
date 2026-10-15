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


class NothingPlaying(Exception):
    """Nada se está viendo ahora mismo: no hay «Viendo en la TV» que enseñar ni que controlar."""


PLAYER_ACTIONS = {"toggle", "pause", "play", "skip", "next", "previous", "stop", "mute"}


def now_playing(catalog) -> dict | None:
    """Lo que se ve ahora en la TV, para la tarjeta «Viendo en la TV» del iPhone. None si no hay nada abierto."""
    running = catalog.launcher.status()
    if running is None or running.get("id") != "media:player":
        return None
    return catalog.watch.player.now_playing()


def control_player(catalog, action: str, delta: float | None = None) -> dict | None:
    """Un botón de la tarjeta del iPhone. Devuelve lo que quedó viendo (None si se detuvo).

    Lanza `NothingPlaying` si no hay nada abierto, y `ValueError` (en palabras) si la acción no
    aplica a lo que se ve (adelantar la TV en vivo, episodio de una película…)."""
    if action not in PLAYER_ACTIONS:
        raise ValueError("Esa acción no existe")
    if now_playing(catalog) is None:
        raise NothingPlaying("No hay nada en la TV ahora mismo")
    player, segment = catalog.watch.player, catalog.watch.player.segment
    live = bool(segment and segment.live)
    if action == "stop":
        player.stop()
        return None
    if action == "mute":
        muted = not bool(player.mpv.get("mute"))
        player.mpv.command("set_property", "mute", muted)
        return now_playing(catalog)
    if action in ("toggle", "pause", "play"):
        if live:
            raise ValueError("La TV en vivo no se pausa")
        paused = (not bool(player.mpv.get("pause"))) if action == "toggle" else action == "pause"
        player.set_pause(paused)
        return now_playing(catalog)
    if action == "skip":
        if live:
            raise ValueError("La TV en vivo no se adelanta")
        if not isinstance(delta, (int, float)):
            raise ValueError("Falta cuánto adelantar")
        player.seek(float(delta))
        return now_playing(catalog)
    # next / previous
    step = 1 if action == "next" else -1
    meta = segment.meta if segment else {}
    if live:
        _zap_channel(catalog, meta, step)
    elif meta.get("kind") == "series" and player.on_episode:
        player.on_episode(meta, step)
    else:
        raise ValueError("Esto no tiene episodios")
    return now_playing(catalog)


def _zap_channel(catalog, meta: dict, step: int) -> None:
    """Cambia de canal (TV en vivo): el siguiente o el anterior en la misma lista."""
    tv = catalog.tv
    guide = tv.guide(meta, meta.get("list"))
    channels = guide.get("channels") or []
    if len(channels) < 2:
        return
    here = next((i for i, c in enumerate(channels) if c.get("current")), -1)
    target = channels[(here + step) % len(channels)] if here >= 0 else channels[0 if step > 0 else -1]
    tv.tune(meta, target["id"], guide.get("category"))
