"""La app del iPhone: cómo se conecta con esta consola (un QR) y qué se lleva de ella.

El QR de «Conectar iPhone» lleva `orbital-ios://pair?u=<dirección de Tailscale>&t=<token>`: lo escaneas con la cámara
del iPhone y la app queda conectada sin escribir nada. Esa dirección es la del túnel de Alexa (el puerto público, que
siempre pide el token). Con eso la app toma de aquí las claves de «Para ti» y la sesión de Trakt (la renueva la
consola: el iPhone nunca guarda la parte que la renueva, así que las dos no se pisan).
"""

from __future__ import annotations

import threading
import time
import uuid
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


# La TV pregunta seguido si hay iPhone (cada vez que abre un menú); `tailscale status` tarda: se recuerda un rato.
_phone_cache: dict = {"at": 0.0, "ready": False}
_phone_lock = threading.Lock()


def phone_ready(config, tailscale_url=None, now=time.monotonic) -> bool:
    """¿Hay un iPhone al que mandarle cosas? (hay token y Tailscale: lo mismo que pide el QR). Se recuerda un minuto
    si sí y 15 s si no, para que al encender Tailscale la opción aparezca pronto."""
    with _phone_lock:
        age = now() - _phone_cache["at"]
        if _phone_cache["at"] and age < (60 if _phone_cache["ready"] else 15):
            return bool(_phone_cache["ready"])
    ready = bool(pair_info(config, tailscale_url)["ready"])
    with _phone_lock:
        _phone_cache.update(at=now(), ready=ready)
    return ready


def forget_phone() -> None:
    with _phone_lock:
        _phone_cache.update(at=0.0, ready=False)


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


# --- bandeja: lo que la TV le manda al iPhone ------------------------------------------------------
INBOX_LIMIT = 20
INBOX_ACTIONS = {"open", "download"}
# Lo que dice la TV tras mandarlo (honesto: el iPhone lo hace cuando abres Orbital ahí, o antes si iOS lo permite).
SENT_TOAST = {"open": "Enviado al iPhone: se abre cuando tengas Orbital a la mano",
              "download": "Se descargará en el iPhone en cuanto abras Orbital ahí (o en segundo plano si iOS lo permite)"}
NOT_CONNECTED = "Conecta tu iPhone en Ajustes › Cuentas"


class PhoneNotConnected(ValueError):
    """No hay iPhone conectado (sin token o sin Tailscale): no hay a dónde mandar nada."""


def send_to_phone(watch, config, action: str, kind: str, meta_id: str, video_id: str | None = None, *, connected=None) -> dict:
    """Deja un pendiente para el iPhone («Enviar al iPhone» abre el título allá; «Descargar en el iPhone» lo baja).

    El iPhone lo recoge en su próximo sondeo de `/api/companion/now` (o en segundo plano, si iOS lo deja) y lo quita
    con `inbox/ack` cuando actúa. Lanza `PhoneNotConnected` sin iPhone y `ValueError` (en palabras) si no hay qué mandar."""
    if action not in INBOX_ACTIONS:
        raise ValueError("Esa acción no existe")
    if kind not in ("movie", "series") or not meta_id:
        raise ValueError("Solo se mandan películas y series")
    if not (connected or phone_ready)(config):
        raise PhoneNotConnected(NOT_CONNECTED)
    try:
        details = watch.title_details(kind, meta_id)
    except Exception as exc:  # noqa: BLE001 - sin internet o Cinemeta caído: se dice en palabras
        raise ValueError("No pude leer ese título; intenta en un momento") from exc
    label = ""
    if kind == "series":
        video_id = video_id or (details.get("resume") or {}).get("video_id") or _first_episode(details)
        label = _episode_label(details, video_id)
    else:
        video_id = video_id or meta_id
    item = {"id": uuid.uuid4().hex[:12], "kind": kind, "meta_id": meta_id, "video_id": video_id,
            "title": details.get("title") or "", "episode_label": label, "poster": details.get("poster"),
            "action": action, "at": int(time.time())}
    return watch.state.inbox_add(item, INBOX_LIMIT)


def _first_episode(details: dict) -> str | None:
    season = next((s for s in details.get("seasons") or [] if s.get("season") != 0 and s.get("episodes")), None)
    return season["episodes"][0]["id"] if season else None


def _episode_label(details: dict, video_id: str | None) -> str:
    """«T2 · E5» (como la tarjeta «Viendo en la TV»)."""
    for season in details.get("seasons") or []:
        for episode in season.get("episodes") or []:
            if episode.get("id") == video_id:
                return f"{'Especial' if season['season'] == 0 else 'T' + str(season['season'])} · E{episode.get('episode')}"
    return ""


def inbox_pending(state) -> list[dict]:
    return state.inbox()


def inbox_ack(state, ids: list[str]) -> int:
    return state.inbox_ack([i for i in ids if isinstance(i, str)][:INBOX_LIMIT * 2])
