"""La app local: la interfaz web, la API y lo que se arranca y se apaga con el servidor."""

from __future__ import annotations

import asyncio
import contextlib
import logging
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .. import __version__, devices
from .. import quick as system_audio
from ..api import (
    addons,
    diagnostics,
    downloads,
    foryou,
    library,
    live,
    media,
    onedrive,
    opensubtitles,
    play,
    quick,
    tv,
    ui,
    update,
)
from ..api.deps import Deps
from ..api.live import SseHub
from ..api.play import humane_error  # noqa: F401 - se importa desde aquí
from ..api.ui import SETTINGS  # noqa: F401
from ..catalog import Catalog
from ..config import Config
from ..library_watch import LibraryWatcher
from ..remote_input import RemoteInput
from ..roku import RokuTv
from ..shell import ConsoleShell
from ..voice import VoiceController
from .base import (
    STORE_DELAY,
    WEB_DIR,
    WebFiles,
    emulator_updates_for,
    invalid_request,
    is_local_request,
    paused_path,
    register_web_types,
    token_ok,
)
from .phone import _companion_routes, _remote_input_routes


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False,
               log_path: Path | None = None, updater=None) -> FastAPI:
    """`shortcuts`: activa los atajos globales del mando (Home, Select+Start, Legion L)."""
    register_web_types()
    catalog = catalog or Catalog(config)
    if kiosk is not None:
        catalog.kiosk = kiosk
    if shortcuts and catalog.tones is None:  # de verdad (no en pruebas): el tono de cada fondo, medido una vez (V3)
        from ..art_tone import ArtTones
        catalog.tones = ArtTones(catalog.thumbs_dir())
        catalog.warm_tones()
    shell = ConsoleShell(catalog, kiosk, pause_file=paused_path() if shortcuts else None)
    catalog.before_launch = shell.close_previous  # abrir algo nuevo cierra lo anterior (no queda olvidado)
    d = Deps(config=config, catalog=catalog, shell=shell, voice=VoiceController(catalog, kiosk, RokuTv(config.tv)), hub=SseHub(),
             kiosk=kiosk, log_path=log_path, started=time.time())

    d.extra["emulator_updates"] = emulator_updates_for(d)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        d.hub.loop = asyncio.get_running_loop()
        unsubscribe = catalog.events.subscribe(d.hub.publish_threadsafe)
        if shortcuts:
            # De verdad (no en pruebas): la interfaz abre ya, con su animación de arranque, mientras
            # se escanea la biblioteca; al terminar avisa (library-changed). Antes no se veía nada
            # hasta que acababa el escaneo de Steam, emuladores y Stremio.
            def scan() -> None:
                try:
                    catalog.refresh()
                finally:
                    catalog.scanning = False
                    d.hub.publish_threadsafe({"type": "library-changed"})
                shell.start()
                # Juegos nuevos con Orbital abierto: vigila las carpetas de juegos (antes solo se buscaba al arrancar).
                catalog.library_watch = LibraryWatcher(catalog.watched_folders, catalog.rescan_for_new)
                catalog.library_watch.start()
                try:  # de qué trata cada juego de Steam y GeForce NOW: con calma, después de todo lo demás
                    time.sleep(STORE_DELAY)
                    catalog.warm_store()
                except Exception:  # noqa: BLE001 - la tienda nunca tumba a Orbital
                    logging.getLogger("orbital.server").exception("Fichas de la tienda de Steam")

            # Con la biblioteca del último arranque, la interfaz entra ya; si no, espera el escaneo.
            catalog.scanning = not catalog.load_snapshot()  # antes de que la interfaz pregunte
            catalog.tv.start()  # revisa los canales de TV con calma (y cada ~6 h)
            catalog.foryou.warm()  # Para ti listo antes de que la TV o el iPhone lo pidan
            d.extra["emulator_updates"].start()  # versiones nuevas de los emuladores: avisa o instala (según Ajustes)
            catalog.watch.ytdlp.start()  # yt-dlp (los tráilers): se baja solo y se mantiene al día
            # Un solo volumen: el reproductor mueve el de Windows (el de Ajustes rápidos y Alexa). Solo aquí, en la Orbital de
            # verdad: en pruebas movería el volumen real de la computadora.
            catalog.watch.player.system_volume = (system_audio.volume, system_audio.set_volume)
            # Con DWM lleno los videos se traban: se libera en reposo y al volver de un juego (solo aquí: en pruebas
            # reiniciaría DWM). Al abrir un video ya no: salía escondido detrás de Orbital (2026-11-03). Si acaba de
            # reiniciarse, el video espera a que Windows vuelva a dibujar (dwm_release.wait_settled).
            from .. import dwm_release

            catalog.watch.player.before_open = dwm_release.wait_settled
            # Y al volver de un juego (los emuladores Vulkan le dejan memoria a DWM): mientras la tele regresa a 4K.
            catalog.sessions.release_video_memory = lambda: dwm_release.release_if_full("al volver de un juego")
            threading.Thread(target=scan, daemon=True, name="first-scan").start()
            from .. import remote_art

            remote_art.prune_later()  # el caché de arte de internet no crece sin fin (A5)
            from ..playback import close_orphan_players

            # Un mpv que quedó de un cierre brusco (encima de todo, con la tubería ocupada): fuera, en segundo plano.
            threading.Thread(target=close_orphan_players, daemon=True, name="mpv-orphans").start()
        else:
            await run_in_threadpool(catalog.refresh)
        status = asyncio.create_task(live.watch_status(d))
        problems = live.ProblemNotifier(d.hub.publish_threadsafe) if shortcuts else None
        if problems:
            logging.getLogger("orbital").addHandler(problems)
        yield
        # Orbital se cierra con un video abierto: se cierra bien (lo visto se guarda) y no queda un mpv
        # huérfano con la tubería ocupada para el siguiente.
        player = getattr(catalog, "player", None)
        if player is not None and getattr(player, "playing", False):
            with contextlib.suppress(Exception):
                await run_in_threadpool(player.stop)
        catalog.tv.stop()
        if catalog.library_watch is not None:
            catalog.library_watch.stop()
        d.extra["emulator_updates"].stop()
        catalog.watch.ytdlp.stop()
        if problems:
            logging.getLogger("orbital").removeHandler(problems)
        status.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await status
        unsubscribe()

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.add_exception_handler(RequestValidationError, invalid_request)  # type: ignore[arg-type]
    app.state.deps = d
    app.state.catalog = catalog
    app.state.bus = d.hub
    app.state.shell = shell
    app.state.remote_input = RemoteInput(publish=catalog.events.publish)
    from ..credentials import Credentials
    app.state.devices = d.extra["devices"] = devices.Devices(getattr(catalog, "credentials", None) or Credentials(None))  # K1-A
    app.state.ui_state = d.extra.setdefault("ui_state", {"screen": "home", "text_field": False})  # lo cuenta la interfaz (POST /api/ui/state)

    @app.middleware("http")
    async def security(request: Request, call_next):
        # Bloquea páginas web ajenas que intenten lanzar cosas contra localhost.
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != f"{request.url.scheme}://{request.url.netloc}":
            return JSONResponse({"detail": "Origen no permitido"}, status_code=403)
        if not is_local_request(request) and not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    for part in (library.router(d), play.router(d), media.router(d), ui.router(d),
                 live.router(d, is_local_request), diagnostics.router(d), quick.router(d),
                 update.router(d, updater), foryou.router(d), tv.router(d), onedrive.router(d), downloads.router(d),
                 addons.router(d, is_local_request), opensubtitles.router(d)):
        app.include_router(part)
    _companion_routes(app, config)
    _remote_input_routes(app, config)
    app.state.run_voice = d.extra["run_voice"]
    app.state.voice_hints = d.extra["voice_hints"]
    app.state.play_stremio = d.extra["play_stremio"]
    app.mount("/", WebFiles(directory=WEB_DIR, html=True), name="web")
    return app
