"""Música: lo que suena en Windows (Apple Music, Spotify, un navegador…) y controlarlo con el mando.

Usa los controles de medios de Windows (GlobalSystemMediaTransportControlsSessionManager): la misma
fuente que el recuadro de volumen de Windows. No necesita cuenta de desarrollador de Apple: la app de
Apple Music para Windows (Microsoft Store) publica ahí lo que suena y acepta pausa/siguiente/anterior.

El reproductor de películas de Orbital (mpv) se deja fuera: ese se maneja por su cuenta.
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path

log = logging.getLogger(__name__)

APPLE_MUSIC_FAMILY = "AppleInc.AppleMusicWin_nzyj5cx40ttqa"
APPLE_MUSIC_URI = rf"shell:AppsFolder\{APPLE_MUSIC_FAMILY}!App"
APPLE_MUSIC_STORE = "ms-windows-store://pdp/?productid=9PFHDD62MXS1"
IGNORED_APPS = ("mpv.exe",)  # el reproductor de Orbital
APP_NAMES = {"AppleInc.AppleMusicWin": "Apple Music", "Spotify": "Spotify", "MSEdge": "Edge",
             "Chrome": "Chrome", "Microsoft.ZuneMusic": "Reproductor multimedia"}
PLAYING, PAUSED = 4, 5  # GlobalSystemMediaTransportControlsSessionPlaybackStatus


def available() -> bool:
    if sys.platform != "win32":
        return False
    try:
        import winrt.windows.media.control  # noqa: F401
    except ImportError:
        return False
    return True


def apple_music_installed() -> bool:
    return (Path(os.environ.get("LOCALAPPDATA", "")) / "Packages" / APPLE_MUSIC_FAMILY).is_dir()


def app_name(app_id: str) -> str:
    return next((name for key, name in APP_NAMES.items() if key.lower() in app_id.lower()),
                Path(app_id.split("!")[0]).stem or app_id)


async def _session():
    from winrt.windows.media.control import GlobalSystemMediaTransportControlsSessionManager as Manager

    manager = await Manager.request_async()
    sessions = [s for s in manager.get_sessions()
                if not any(ignored in (s.source_app_user_model_id or "").lower() for ignored in IGNORED_APPS)]
    if not sessions:
        return None
    # Primero lo que suena; entre iguales, Apple Music; si no, la que Windows considera actual.
    current = manager.get_current_session()

    def rank(s):
        status = s.get_playback_info().playback_status
        return (status != PLAYING, "applemusic" not in (s.source_app_user_model_id or "").lower(),
                s is not current)
    return sorted(sessions, key=rank)[0]


async def _now_playing() -> dict | None:
    session = await _session()
    if session is None:
        return None
    props = await session.try_get_media_properties_async()
    app_id = session.source_app_user_model_id or ""
    return {"app": app_name(app_id), "app_id": app_id, "title": props.title or "", "artist": props.artist or "",
            "album": props.album_title or "", "playing": session.get_playback_info().playback_status == PLAYING,
            "has_art": props.thumbnail is not None}


async def _command(action: str) -> bool:
    session = await _session()
    if session is None:
        return False
    call = {"toggle": session.try_toggle_play_pause_async, "play": session.try_play_async,
            "pause": session.try_pause_async, "next": session.try_skip_next_async,
            "previous": session.try_skip_previous_async}[action]
    return bool(await call())


async def _art() -> bytes | None:
    from winrt.windows.storage.streams import Buffer, InputStreamOptions

    session = await _session()
    if session is None:
        return None
    props = await session.try_get_media_properties_async()
    if props.thumbnail is None:
        return None
    stream = await props.thumbnail.open_read_async()
    size = int(stream.size)
    buffer = Buffer(size)
    await stream.read_async(buffer, size, InputStreamOptions.READ_AHEAD)
    return bytes(memoryview(buffer))[: buffer.length]


def _run(coro, default):
    """Llamada a WinRT desde un hilo normal (cada una con su propio ciclo asyncio)."""
    if not available():
        coro.close()
        return default
    try:
        return asyncio.run(coro)
    except Exception as exc:  # noqa: BLE001 - sin música o sin permiso: como si no sonara nada
        log.debug("Controles de medios de Windows: %s", exc)
        return default


def now_playing() -> dict | None:
    """{"app", "title", "artist", "album", "playing", "has_art"} o None si nada suena ni está en pausa."""
    return _run(_now_playing(), None)


def command(action: str) -> bool:
    if action not in ("toggle", "play", "pause", "next", "previous"):
        raise ValueError(action)
    return _run(_command(action), False)


def art() -> bytes | None:
    return _run(_art(), None)
