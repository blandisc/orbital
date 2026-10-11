"""API HTTP + interfaz web de Orbital."""

from __future__ import annotations

import asyncio
import hmac
import ipaddress
import json
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import __version__, system
from .catalog import Catalog
from .config import Config
from .library import cinemeta, stremio_api
from .shell import ConsoleShell
from .voice import VoiceController

log = logging.getLogger(__name__)
WEB_DIR = Path(__file__).parent / "web"
_FORWARD_HEADERS = ("x-forwarded-for", "forwarded", "cf-connecting-ip", "x-real-ip")


class LaunchRequest(BaseModel):
    id: str
    runner: str | None = None
    keep: bool = False  # abrir sin cerrar lo que estaba abierto


class PrefsRequest(BaseModel):
    id: str
    favorite: bool | None = None
    hidden: bool | None = None
    runner: str | None = None
    clear_runner: bool = False


class PlayRequest(BaseModel):
    kind: str
    id: str
    video_id: str | None = None
    title: str = ""
    source: int | None = None  # None: Orbital elige la recomendada y arranca
    keep: bool = False
    from_start: bool = False  # "Desde el principio"


# Ajustes que se pueden cambiar desde la interfaz (y sus valores válidos).
SETTINGS = {
    "audio": {"en", "es"},
    "subtitles": {"en", "es", "forced", ""},
    "quality": {"4K", "1080p", "720p"},
    "sub_scale": {.85, 1.0, 1.25, 1.5},
    "text_size": {"normal", "large", "xlarge"},
    "safe_area": {0, 2, 4, 6},
    "reduce_motion": {True, False},
    "sounds": {True, False},
    "haptics": {True, False},
    "welcomed": {True, False},  # ya vio "Tu consola" (la pantalla de primer uso)
}


def humane_error(exc: Exception, what: str = "") -> str:
    """Errores de Windows/Python en palabras de persona (lo técnico se queda en el log)."""
    if isinstance(exc, FileNotFoundError):
        name = Path(exc.filename).stem if getattr(exc, "filename", None) else (what or "el programa")
        return f"No encuentro {name}. ¿Lo moviste o lo desinstalaste? Actualiza la biblioteca desde el menú (☰)."
    if isinstance(exc, PermissionError):
        return f"Windows no me deja abrir {what or 'esto'}. Prueba abrirlo una vez desde el escritorio."
    text = str(exc)
    if "WinError" in text or "Errno" in text:
        return f"No pude abrir {what or 'esto'}."
    return text


class VoiceRequest(BaseModel):
    intent: str | None = None
    slots: dict[str, str] | None = None
    text: str | None = None


class EventBus:
    """Reparte eventos (toasts, navegación por voz) a las pantallas conectadas vía SSE."""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue] = set()
        self.loop: asyncio.AbstractEventLoop | None = None

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=100)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._subscribers.discard(queue)

    def publish(self, event: dict) -> None:
        for queue in list(self._subscribers):
            if not queue.full():
                queue.put_nowait(event)

    def publish_threadsafe(self, event: dict) -> None:
        """Para hilos que no son el del servidor (p. ej. el vigilante de procesos)."""
        if self.loop and not self.loop.is_closed():
            self.loop.call_soon_threadsafe(self.publish, event)


_LOCAL_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}


def is_local_request(request: Request) -> bool:
    """Local = viene del propio equipo, NO atravesó un proxy/túnel y va dirigida a localhost.

    Comprobar el Host importa: un túnel como Tailscale Funnel entrega las peticiones desde
    127.0.0.1 y sin garantía de cabeceras de reenvío, pero con Host "tu-equipo.ts.net".
    También evita ataques de DNS rebinding desde páginas web.
    """
    if any(h in request.headers for h in _FORWARD_HEADERS):
        return False
    try:
        hostname = urlsplit("//" + request.headers.get("host", "")).hostname or ""
    except ValueError:
        return False
    if hostname not in _LOCAL_HOSTNAMES:
        return False
    client = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(client).is_loopback
    except ValueError:
        return False


def token_ok(request: Request, expected: str) -> bool:
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    return bool(token) and bool(expected) and hmac.compare_digest(token, expected)


def paused_path() -> Path:
    """Qué quedó congelado (para descongelarlo si Orbital se cierra de golpe)."""
    return Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "state") / "orbital" / "paused.json"


def create_app(config: Config, catalog: Catalog | None = None, kiosk=None, shortcuts: bool = False) -> FastAPI:
    """`shortcuts`: activa los atajos globales del mando (Home, Select+Start, Legion L)."""
    catalog = catalog or Catalog(config)
    if kiosk is not None:
        catalog.kiosk = kiosk
    voice = VoiceController(catalog, kiosk)
    bus = EventBus()
    shell = ConsoleShell(catalog, kiosk, pause_file=paused_path() if shortcuts else None)
    catalog.before_launch = shell.close_previous  # abrir algo nuevo cierra lo anterior (no queda olvidado)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        bus.loop = asyncio.get_running_loop()
        catalog.listeners.append(bus.publish_threadsafe)
        if shortcuts:
            # De verdad (no en pruebas): la interfaz abre ya, con su animación de arranque, mientras
            # se escanea la biblioteca; al terminar avisa (library-changed). Antes no se veía nada
            # hasta que acababa el escaneo de Steam, emuladores y Stremio.
            def scan() -> None:
                try:
                    catalog.refresh()
                finally:
                    catalog.scanning = False
                    bus.publish_threadsafe({"type": "library-changed"})
                shell.start()

            catalog.scanning = True  # antes de que la interfaz pregunte
            threading.Thread(target=scan, daemon=True, name="first-scan").start()
        else:
            await run_in_threadpool(catalog.refresh)
        yield
        catalog.listeners.remove(bus.publish_threadsafe)

    app = FastAPI(title="Orbital", version=__version__, lifespan=lifespan)
    app.state.catalog = catalog
    app.state.bus = bus
    app.state.shell = shell
    app.state.alexa_last = None  # última vez que llegó un comando de voz remoto

    @app.middleware("http")
    async def security(request: Request, call_next):
        # Bloquea páginas web ajenas que intenten lanzar cosas contra localhost.
        origin = request.headers.get("origin")
        if origin and origin.rstrip("/") != f"{request.url.scheme}://{request.url.netloc}":
            return JSONResponse({"detail": "Origen no permitido"}, status_code=403)
        if not is_local_request(request) and not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    @app.get("/api/health")
    def health() -> dict:
        return {"ok": True, "version": __version__}

    @app.get("/api/library")
    def library() -> dict:
        catalog.refresh_stremio_if_stale()  # en segundo plano; avisa con "library-changed"
        return {"rows": catalog.grouped(), "hidden": catalog.hidden_count(), "scanning": catalog.scanning}

    @app.post("/api/library/refresh")
    def refresh() -> dict:
        return {"count": catalog.refresh(), "rows": catalog.grouped(), "hidden": catalog.hidden_count()}

    @app.post("/api/prefs")
    def prefs(body: PrefsRequest) -> dict:
        try:
            return catalog.set_prefs(body.id, favorite=body.favorite, hidden=body.hidden,
                                     runner=body.runner, clear_runner=body.clear_runner)
        except KeyError:
            raise HTTPException(404, "Elemento no encontrado")
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @app.post("/api/prefs/unhide-all")
    def unhide_all() -> dict:
        return {"restored": catalog.state.unhide_all()}

    @app.get("/api/system")
    async def system_info() -> dict:
        return {"wifi": await run_in_threadpool(system.wifi), "alexa_last": app.state.alexa_last}

    @app.post("/api/launch")
    def launch(body: LaunchRequest) -> dict:
        running = catalog.launcher.status()
        if running and running["id"] == body.id and not body.runner and shell.resume():
            return {"ok": True, "resumed": True}
        try:
            item = catalog.launch(body.id, body.runner, keep=body.keep)
        except KeyError:
            raise HTTPException(404, "Ese juego ya no está en tu biblioteca")
        except (OSError, RuntimeError, ValueError) as exc:
            log.warning("No se pudo abrir %s: %s", body.id, exc)
            found = catalog.get(body.id)
            raise HTTPException(500, humane_error(exc, found.title if found else ""))
        # `reveal`: la pantalla de carga espera el evento launch-ready (el juego ya está listo).
        return {"ok": True, "title": item.title, "reveal": catalog.revealing}

    @app.post("/api/launch/reveal")
    def launch_reveal() -> dict:
        """B en la pantalla de carga: mostrar ya el juego (o lo que haya)."""
        catalog.reveal_now()
        return {"ok": True}

    @app.get("/api/status")
    def status() -> dict:
        running = catalog.launcher.status()
        if running is not None:
            running["paused"] = shell.is_paused
        return {"running": running}

    @app.get("/api/ui")
    def ui_info() -> dict:
        return {"can_exit": kiosk is not None, "stremio_linked": catalog.stremio_linked,
                "player": "orbital" if catalog.native_player else "stremio",
                # Alexa configurada (token fijo): la interfaz enseña frases que puedes decirle.
                "alexa": bool(config.server.token) and not config.server.token_is_ephemeral}

    @app.post("/api/ui/exit")
    async def ui_exit() -> dict:
        if kiosk is None:
            raise HTTPException(409, "Esta ventana no la abrió Orbital: ciérrala tú (Alt+F4)")
        # Se cierra un instante después para que la respuesta llegue a la página.
        asyncio.get_running_loop().call_later(0.4, lambda: threading.Thread(target=kiosk.close, daemon=True).start())
        return {"ok": True}

    @app.post("/api/stop")
    def stop() -> dict:
        # También cierra un emulador abierto desde ES-DE si se pidió con Select+Start.
        return {"stopped": shell.stop_game()}

    # --- Stremio: explorar en Orbital, reproducir en Stremio ---------------------
    @app.get("/api/stremio/search")
    def stremio_search(q: str = "") -> dict:
        if len(q.strip()) < 2:
            return {"results": []}
        # Películas y series a la vez (antes una tras otra: con internet lento, el doble de espera).
        with ThreadPoolExecutor(max_workers=2) as pool:
            movies, series = pool.submit(catalog.cinemeta.search, "movie", q), pool.submit(catalog.cinemeta.search, "series", q)
            try:
                return {"results": cinemeta.search_results(q, movies.result(), series.result())}
            except cinemeta.CinemetaError:
                raise HTTPException(502, "Sin conexión con el catálogo de películas y series. Tus juegos siguen aquí.")

    @app.get("/api/stremio/title/{kind}/{meta_id}")
    def stremio_title(kind: str, meta_id: str) -> dict:
        """La ficha: datos, reparto, temporadas y dónde ibas."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            return catalog.title_details(kind, meta_id)
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar la ficha. Revisa tu conexión e inténtalo de nuevo.")

    @app.get("/api/stremio/episodes/{meta_id}")
    def stremio_episodes(meta_id: str) -> dict:
        try:
            meta = catalog.cinemeta.meta("series", meta_id)
        except cinemeta.CinemetaError as exc:
            raise HTTPException(502, str(exc))
        return {"id": meta_id, "title": meta.get("name") or "", "seasons": cinemeta.seasons(meta),
                "background": meta.get("background") or None, **cinemeta.describe_meta(meta)}

    @app.get("/api/stremio/sources")
    def stremio_sources(kind: str, id: str, video: str | None = None) -> dict:
        """Fuentes ordenadas por tus preferencias; la primera es la recomendada. Sin URLs."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            found = catalog.stream_sources(kind, video or id)
        except stremio_api.StremioError as exc:
            raise HTTPException(409, str(exc))
        prefs = catalog.stream_prefs
        try:  # título, póster y fondo para la pantalla (de caché casi siempre)
            meta = catalog.cinemeta.meta(kind, id)
            info = {"title": meta.get("name") or "", "poster": meta.get("poster"), "background": meta.get("background"),
                    **cinemeta.describe_meta(meta)}
        except cinemeta.CinemetaError:
            info = {}
        return {"sources": [s.public() for s in found], "audio": prefs.audio, "quality": prefs.quality, "meta": info}

    @app.post("/api/stremio/play")
    def stremio_play(body: PlayRequest) -> dict:
        """Con `source`: esa fuente. Sin ella (y con el reproductor de Orbital): la recomendada, directo."""
        kind, meta_id = body.kind, body.id
        if kind not in ("movie", "series") or not meta_id:
            raise HTTPException(400, "Falta qué reproducir")
        title = body.title or "Stremio"
        video_id = body.video_id or (meta_id if kind == "movie" else None)
        try:
            if body.source is not None and video_id:
                catalog.play_source(kind, meta_id, video_id, body.source, title, keep=body.keep,
                                    from_start=body.from_start)
                return {"ok": True, "reveal": catalog.revealing}
            if video_id and catalog.native_player:
                chosen = catalog.play_best(kind, meta_id, video_id, title, keep=body.keep, from_start=body.from_start)
                return {"ok": True, "reveal": catalog.revealing, **chosen}
        except stremio_api.StremioError as exc:
            raise HTTPException(409, str(exc))
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        catalog.play_stremio(kind, meta_id, body.video_id, title)
        return {"ok": True}

    @app.post("/api/stremio/login")
    def stremio_login(body: dict) -> dict:
        """Conectar Stremio desde la consola. La contraseña solo viaja a Stremio: no se guarda ni se
        registra; Orbital guarda la clave de sesión que devuelve (igual que `orbital stremio login`)."""
        email, password = str(body.get("email") or "").strip(), str(body.get("password") or "")
        if not email or not password:
            raise HTTPException(422, "Escribe tu correo y tu contraseña de Stremio")
        try:
            key = catalog.stremio_client.login(email, password)
            count = catalog.link_stremio(key)
        except stremio_api.StremioError as exc:
            raise HTTPException(401, f"Stremio no aceptó esos datos: {exc}")
        return {"ok": True, "count": count}

    @app.post("/api/stremio/logout")
    def stremio_logout() -> dict:
        catalog.unlink_stremio()
        return {"ok": True}

    @app.post("/api/stremio/library")
    def stremio_library(body: dict) -> dict:
        """Mi lista: añadir o quitar."""
        kind, meta_id = body.get("kind"), str(body.get("id") or "")
        if kind not in ("movie", "series") or not meta_id:
            raise HTTPException(400, "Falta qué añadir")
        try:
            catalog.set_in_library(kind, meta_id, bool(body.get("add")))
        except stremio_api.StremioError as exc:
            raise HTTPException(409, str(exc))
        return {"ok": True, "in_library": bool(body.get("add"))}

    @app.post("/api/stremio/trailer")
    def stremio_trailer(body: dict) -> dict:
        kind, meta_id = body.get("kind"), str(body.get("id") or "")
        if kind not in ("movie", "series") or not meta_id:
            raise HTTPException(400, "Falta de qué título")
        try:
            catalog.play_trailer(kind, meta_id)
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar el tráiler. Revisa tu conexión.")
        return {"ok": True}

    @app.post("/api/stremio/dismiss")
    def stremio_dismiss(body: dict) -> dict:
        """Quitar de Seguir viendo."""
        meta_id = str(body.get("id") or "").removeprefix("stremio:")
        if not meta_id:
            raise HTTPException(400, "Falta qué quitar")
        try:
            catalog.dismiss_continue(meta_id)
        except stremio_api.StremioError as exc:
            raise HTTPException(409, str(exc))
        return {"ok": True}

    @app.get("/api/controllers")
    async def controllers() -> dict:
        from .gamepad import connected_controllers
        return {"controllers": await run_in_threadpool(connected_controllers)}

    @app.get("/api/setup")
    def setup() -> dict:
        return catalog.setup_status()

    @app.get("/api/settings")
    def get_settings() -> dict:
        prefs = catalog.stream_prefs
        return {"audio": prefs.audio, "quality": prefs.quality, "subtitles": catalog.subtitles_lang,
                "sub_scale": float(catalog.setting("sub_scale", 1.0) or 1.0), "text_size": "normal", "safe_area": 4,
                "reduce_motion": False, "sounds": True, "haptics": True, **catalog.state.settings(),
                "stremio_linked": catalog.stremio_linked, "alexa": bool(config.server.token)
                and not config.server.token_is_ephemeral, "alexa_last": app.state.alexa_last}

    @app.post("/api/settings")
    def set_settings(body: dict) -> dict:
        for key, value in body.items():
            if key not in SETTINGS or value not in SETTINGS[key]:
                raise HTTPException(422, f"Ajuste inválido: {key}")
            catalog.state.set_setting(key, value)
        return get_settings()

    @app.get("/api/windows")
    def open_windows() -> dict:
        """Ventanas abiertas (como Alt+Tab), para saltar entre ellas con el mando."""
        return {"windows": shell.open_windows()}

    @app.post("/api/windows/focus")
    def focus_window(body: dict) -> dict:
        if not shell.focus_window(int(body.get("id", 0))):
            raise HTTPException(404, "Esa ventana ya no está abierta")
        return {"ok": True}

    @app.post("/api/power")
    def power(body: dict) -> dict:
        action = body.get("action")
        if action not in system.POWER_ACTIONS:
            raise HTTPException(400, "Acción desconocida")
        # Un instante después, para que la respuesta llegue a la interfaz.
        threading.Timer(0.6, system.power, args=(action,)).start()
        return {"ok": True}

    @app.post("/api/ui/reload")
    def ui_reload(body: dict | None = None) -> dict:
        """Recarga la interfaz abierta (tras actualizar Orbital no hace falta reiniciarlo).
        `view`: abrir directo una vista — {"buscar": "dune"} o {"serie": "tt0386676"}."""
        view = {k: str(v) for k, v in (body or {}).get("view", {}).items() if k in ("buscar", "serie", "seccion", "fuentes")}
        bus.publish_threadsafe({"type": "reload", "view": view})
        return {"ok": True}

    @app.post("/api/ui/show")
    def ui_show() -> dict:
        """El ícono del escritorio con Orbital ya abierto: trae (o reabre) la ventana en vez de otra copia."""
        if kiosk is None:
            raise HTTPException(409, "Esta interfaz no la abrió Orbital")
        threading.Thread(target=kiosk.open, daemon=True).start()
        return {"ok": True}

    @app.post("/api/ui/resume")
    def ui_resume() -> dict:
        """Vuelve al juego ("Seguir jugando")."""
        shell.hold = None
        return {"ok": shell.resume()}

    async def run_voice(body: VoiceRequest, remote: bool) -> dict:
        if remote:
            app.state.alexa_last = time.time()
        if body.intent:
            result = await run_in_threadpool(voice.handle_intent, body.intent, body.slots)
        elif body.text:
            result = await run_in_threadpool(voice.handle_text, body.text)
        else:
            raise HTTPException(422, "Envía 'intent' o 'text'")
        for event in result.events:
            bus.publish(event)
        return result.as_dict()

    app.state.run_voice = run_voice

    @app.post("/api/voice")
    async def voice_command(body: VoiceRequest, request: Request) -> dict:
        return await run_voice(body, remote=not is_local_request(request))

    @app.get("/api/events")
    async def events(request: Request) -> StreamingResponse:
        queue = bus.subscribe()

        async def stream():
            try:
                yield ": conectado\n\n"
                while not await request.is_disconnected():
                    try:
                        event = await asyncio.wait_for(queue.get(), timeout=15)
                        yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                    except asyncio.TimeoutError:
                        yield ": ping\n\n"
            finally:
                bus.unsubscribe(queue)

        return StreamingResponse(stream(), media_type="text/event-stream")

    @app.get("/api/art/{item_id:path}")
    def art(item_id: str, kind: str = "cover") -> FileResponse:
        # Solo se sirven imágenes que el escaneo asoció a un elemento: nunca rutas arbitrarias.
        item = catalog.get(item_id)
        path = None if item is None else (item.hero_path if kind == "hero" else item.art_path)
        if not path or not Path(path).is_file():
            raise HTTPException(404)
        return FileResponse(path, headers={"Cache-Control": "max-age=86400"})

    app.mount("/", WebFiles(directory=WEB_DIR, html=True), name="web")
    return app


class WebFiles(StaticFiles):
    """La interfaz siempre se revalida (ETag): tras actualizar Orbital, Edge no mezcla CSS o JS viejos."""

    def file_response(self, *args, **kwargs):
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "no-cache"
        return response


def create_public_app(config: Config, main_app: FastAPI) -> FastAPI:
    """App mínima para internet (Alexa a través del túnel): solo voz y ping, siempre con token.

    Corre en otro puerto (server.public_port). Aunque el túnel entregue las peticiones desde
    127.0.0.1, aquí no hay excepciones para "local": sin token no se hace nada.
    """
    public = FastAPI(title="Orbital · Alexa", docs_url=None, redoc_url=None, openapi_url=None)

    @public.middleware("http")
    async def require_token(request: Request, call_next):
        if not token_ok(request, config.server.token):
            return JSONResponse({"detail": "Token inválido"}, status_code=401)
        return await call_next(request)

    @public.get("/api/ping")
    def ping() -> dict:
        return {"ok": True, "service": "orbital", "version": __version__}

    @public.post("/api/voice")
    async def voice_command(body: VoiceRequest) -> dict:
        return await main_app.state.run_voice(body, remote=True)

    return public
