"""El puerto público (Alexa, el iPhone, el túnel): qué rutas se abren afuera, con qué clave y con qué tope."""

from __future__ import annotations

import asyncio
import time
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

from .. import __version__, companion, devices
from ..api import (
    addons,
    foryou,
    library,
    media,
)
from ..api.live import VoiceRequest
from ..api.play import humane_error  # noqa: F401 - se importa desde aquí
from ..api.ui import SETTINGS  # noqa: F401
from ..config import Config
from ..foryou import SERVICE_ERRORS, TV_ONLY_PREFIXES
from ..library import trakt
from .base import FailedTokens, invalid_request, log, token_ok
from .phone import (
    KEY_REQUIRED,
    MEDIA_ID,
    QUICK_CODE_WRONG,
    REMOTE_HEADERS,
    ChoicesSync,
    CompanionAck,
    CompanionConsole,
    CompanionGame,
    CompanionInput,
    CompanionPlayerAction,
    CompanionText,
    KeyRequired,
    ResumeSync,
    bearer,
    device_of,
    forget_device,
    key_required,
    remote_page,
    resume_for_device,
    resume_from_device,
    with_key,
)

MAX_PUBLIC_BODY = 16 * 1024


def create_public_app(config: Config, main_app: FastAPI, guard: FailedTokens | None = None) -> FastAPI:
    """App mínima para internet (Alexa y el iPhone a través del túnel): voz, ping, «Ver en la TV» y las claves de «Para ti» para la app del iPhone, siempre con token.

    Corre en otro puerto (server.public_port). Aunque el túnel entregue las peticiones desde
    127.0.0.1, aquí no hay excepciones para "local": sin token no se hace nada.
    """
    public = FastAPI(title="Orbital · Alexa", docs_url=None, redoc_url=None, openapi_url=None)
    public.add_exception_handler(RequestValidationError, invalid_request)  # type: ignore[arg-type]
    public.state.main = main_app
    public.add_exception_handler(KeyRequired, key_required)

    guard = guard or FailedTokens()
    measured: set[tuple[bool, bool]] = set()

    def seen_headers(request: Request) -> None:
        """CX6: ¿el túnel (Funnel) dice quién llama? Se anota una vez por combinación si trae las cabeceras, nunca su valor."""
        combo = ("x-forwarded-for" in request.headers, "tailscale-funnel-request" in request.headers)
        if combo not in measured and len(measured) < 4:
            measured.add(combo)
            log.info("Túnel: X-Forwarded-For %s · Tailscale-Funnel-Request %s", *("sí" if c else "no" for c in combo))

    one_at_a_time: list[asyncio.Lock] = []  # los intentos fallidos esperan en fila, no en paralelo
    waiting = [0]
    MAX_WAITING = 20  # más que esto en fila: 429 al instante (no se acumulan conexiones abiertas)

    @public.middleware("http")
    async def require_token(request: Request, call_next):
        # Un comando de voz cabe en unos cientos de bytes: 5 MB de texto ocupaban el servidor segundos.
        try:
            size = int(request.headers.get("content-length") or 0)
        except ValueError:
            size = MAX_PUBLIC_BODY + 1
        if not request.headers.get("content-length") and "chunked" in request.headers.get("transfer-encoding", "").lower():
            size = MAX_PUBLIC_BODY + 1  # sin tamaño declarado no se puede medir antes de leerlo todo
        if size > MAX_PUBLIC_BODY:
            return JSONResponse({"detail": "Petición demasiado grande"}, status_code=413)
        key = FailedTokens.key(request)
        seen_headers(request)
        if request.url.path == "/clave":  # el código de acceso rápido: la página que lo pide (no lleva nada)
            return await call_next(request)
        if request.url.path.startswith(("/escribir/", "/clave/")):
            code = request.url.path.split("/", 2)[2].strip("/")
            if guard.blocked(key):
                return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
            if request.url.path.startswith("/clave/"):
                code = main_app.state.remote_input.resolve(code) or ""
                request.state.remote_code = code
                if not code and request.method == "GET":
                    await asyncio.sleep(guard.failed(key))
                    return HTMLResponse(remote_page({"ask_code": True, "error": QUICK_CODE_WRONG}), status_code=404,
                                        headers=REMOTE_HEADERS)
            if main_app.state.remote_input.form(code) is not None:
                return await call_next(request)
            await asyncio.sleep(guard.failed(key))
            if request.method == "GET":
                return HTMLResponse(remote_page(None), status_code=404, headers=REMOTE_HEADERS)
            return JSONResponse({"detail": "Este código ya no sirve. Vuelve a abrir el formulario en la TV."}, status_code=404)
        if request.url.path == "/api/devices/pair" and request.method == "POST":  # el código del QR, sin token
            if guard.blocked(key):
                return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
            response = await call_next(request)
            if response.status_code == 404:
                await asyncio.sleep(guard.failed(key))
            return response
        paired = main_app.state.devices
        sent = bearer(request)
        if paired.is_key(sent):  # la llave del aparato (K1-A)
            found, device = paired.check(sent)
            if device is not None:
                guard.succeeded(key)
                request.state.device = device
                return await call_next(request)
            if found in ("removed", "unknown") and not guard.blocked(key):
                guard.failed(key)
                said = ("Esta TV te quitó: vuelve a escanear el código de tu TV" if found == "removed"
                        else "Tu TV es nueva: vuelve a escanear su código")
                return JSONResponse({"code": f"device_{found}", "detail": said}, status_code=401)
        # El token correcto pasa siempre: quien falsifica tu dirección no te deja fuera.
        elif token_ok(request, config.server.token):
            guard.succeeded(key)
            upgrading = request.url.path.startswith("/api/devices/upgrade")  # CX8-A: del token a la llave, con el sí en la TV
            if request.url.path not in devices.ALEXA_PATHS and not upgrading and paired.any():  # K1-13: el token ya solo es de Alexa
                return JSONResponse(KEY_REQUIRED, status_code=401)
            return await call_next(request)
        if guard.blocked(key):
            return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
        if waiting[0] >= MAX_WAITING:
            guard.failed(key)
            return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
        if not one_at_a_time:
            one_at_a_time.append(asyncio.Lock())
        waiting[0] += 1
        try:
            async with one_at_a_time[0]:  # 600 intentos a la vez ya no esperan 5 s en total, sino uno tras otro
                if guard.blocked(key):  # se bloqueó mientras esperaba en la fila
                    return JSONResponse({"detail": "Demasiados intentos"}, status_code=429)
                await asyncio.sleep(guard.failed(key))
        finally:
            waiting[0] -= 1
        return JSONResponse({"detail": "Token inválido"}, status_code=401)

    @public.api_route("/api/ping", methods=["GET", "HEAD"])  # HEAD: los monitores de disponibilidad
    def ping() -> dict:
        return {"ok": True, "service": "orbital", "version": __version__, **companion.contract()}  # F1

    @public.post("/api/voice")
    async def voice_command(body: VoiceRequest) -> dict:
        return await main_app.state.run_voice(body, remote=True)

    @public.get("/api/voice/hints")
    async def voice_hints() -> dict:
        """La pista del iPhone por el túnel: las tres frases de este momento (con token, como todo aquí)."""
        return await run_in_threadpool(main_app.state.voice_hints)

    def saw_phone(request: Request | None = None) -> None:
        """Para Ajustes › Cuentas: en memoria, la hora exacta (¿está abierta ahora?) y en disco, una escritura cada 10
        min como mucho («Lo usaste hace 2 h»). Con la app nueva, por aparato (iPhone e iPad usan el mismo token, y la
        tele decía «Conectado» por el iPad aunque el iPhone hubiera perdido la conexión)."""
        deps = getattr(main_app.state, "deps", None)
        if deps is not None:
            deps.extra["phone_seen"] = time.time()
        state = getattr(main_app.state.catalog, "state", None)
        keyed = device_of(request) if request is not None else None
        device = ({"id": keyed["device_id"], "name": keyed["name"], "kind": keyed["platform"]} if keyed
                  else companion.device_from(request.headers) if request is not None else None)
        if device is not None and deps is not None and state is not None:
            companion.remember_device(state, deps.extra.setdefault("phones", {}), device, time.time())
        if state is not None and time.time() - float(state.settings().get("companion_seen") or 0) > 600:
            state.set_setting("companion_seen", time.time())

    @public.get("/api/companion")
    def companion_keys(request: Request) -> dict:
        """La app del iPhone toma de aquí lo de «Para ti» para no escribirlo dos veces: la clave de TMDB, la aplicación
        de Trakt (su Client ID, que no es secreto; el secreto no sale de aquí) y el país. La sesión de Trakt de la consola
        ya no se presta: el iPhone conecta la suya con un código (cada app con su sesión)."""
        p = config.para_ti
        saw_phone(request)  # Ajustes › Cuentas: el iPhone está conectado (antes decía siempre «Conectar»)
        # Lo primero que pide la app al escanear el QR: la TV lo celebra si tiene el QR a la vista (antes solo se quedaba
        # el código, sin saber si ya había funcionado). Con el QR cerrado la interfaz no dice nada (la app también lo
        # pide al abrirse).
        bus = getattr(main_app.state, "bus", None)
        if bus is not None:
            bus.publish_threadsafe({"type": "phone-linked"})
        foryou = getattr(main_app.state.catalog, "foryou", None)
        key = foryou.key if foryou else (lambda name: getattr(p, name))  # las escritas en la TV, o las de config.yaml
        return {"tmdb_key": key("tmdb_key"), "trakt_client_id": key("trakt_client_id"), "region": p.region,
                "pairing": 2,  # K1-12: esta TV reparte llaves por aparato
                "tv_id": main_app.state.devices.tv_id(),  # TEC-30: una TV reinstalada tiene otro
                **companion.contract()}  # F1: versión del contrato y capacidades

    @public.get("/escribir/{code}")
    def remote_form(code: str) -> HTMLResponse:
        """La página del celular para escribir en la tele (correo, contraseña, una clave)."""
        return HTMLResponse(remote_page(main_app.state.remote_input.form(code)), headers=REMOTE_HEADERS)

    # El código de acceso rápido (Fernando, 3 nov): la misma página sin escanear, desde cualquier navegador.
    @public.get("/clave")
    def quick_code_page() -> HTMLResponse:
        return HTMLResponse(remote_page({"ask_code": True}), headers=REMOTE_HEADERS)

    @public.get("/clave/{short}")
    def quick_code_form(short: str, request: Request) -> HTMLResponse:
        return HTMLResponse(remote_page(main_app.state.remote_input.form(request.state.remote_code)), headers=REMOTE_HEADERS)

    @public.post("/clave/{short}")
    async def quick_code_send(short: str, request: Request) -> JSONResponse:
        return await remote_send(request.state.remote_code, request)

    @public.post("/escribir/{code}")
    async def remote_send(code: str, request: Request) -> JSONResponse:
        try:
            body = await request.json()
        except ValueError:
            body = {}
        remote = main_app.state.remote_input
        values = body.get("values") if isinstance(body, dict) else None
        extra = None
        if remote.purpose(code) == "realdebrid":  # CA2-A: la clave se prueba aquí, nunca en la interfaz
            token = values.get("token") if isinstance(values, dict) else None
            try:
                account = await run_in_threadpool(main_app.state.catalog.watch.check_rd_token, str(token or ""))
            except ValueError as exc:
                return JSONResponse({"detail": remote.fail(code, str(exc))}, status_code=400)
            except ConnectionError as exc:
                return JSONResponse({"detail": str(exc)}, status_code=503)
            extra = {"account": account}
        problem = remote.submit(code, values, extra)
        if problem:
            return JSONResponse({"detail": problem}, status_code=400)
        return JSONResponse({"ok": True, **({"account": extra["account"]} if extra else {})})

    @public.post("/api/stremio/play")
    def play_on_tv(body: media.PlayRequest) -> dict:
        """«Ver en la TV» desde el iPhone: lo mismo que la tarjeta de la TV (la fuente recomendada, donde ibas).
        No da más de lo que ya da la voz («pon The Office»): solo poner un título de Stremio."""
        return main_app.state.play_stremio(body)

    _foryou_public_routes(public, main_app)

    @public.get("/api/companion/now")
    def companion_now(request: Request) -> dict:
        """«Viendo en la TV» del iPhone: qué se ve ahora (o `null` si no hay nada abierto)."""
        # Lo que la TV le dejó al iPhone («Enviar» / «Descargar en el iPhone») viaja aquí: ni una petición de más.
        catalog = main_app.state.catalog
        saw_phone(request)  # lo que el iPhone pide cada 5 s abierto (antes solo contaba /api/companion, que pide al emparejarse)
        return {"playing": companion.now_playing(catalog), "inbox": companion.inbox_pending(catalog.state),
                "game": companion.game_now(catalog, main_app.state.shell),  # el modo acompañante (None sin juego)
                # qué pantalla y si hay un campo de texto (el iPhone enseña «Escribir»); con el reproductor al frente,
                # "player"/"live" y su leyenda
                "ui": companion.ui_state(catalog, main_app.state.shell, main_app.state.ui_state),
                "volume": companion.volume_state(catalog, _volume())}  # {"level", "muted"} y el Extra: la barra del control del iPhone

    @public.get("/api/tv/logo")
    def companion_channel_logo(id: str) -> FileResponse:
        """El logo del canal que se ve (el iPhone lo pinta en «Viendo en la TV»)."""
        path = main_app.state.catalog.tv.logo_path(id[:200])
        if path is None:
            raise HTTPException(404, "Ese canal no tiene logo.")
        return FileResponse(path, headers={"Cache-Control": "public, max-age=86400"})

    @public.post("/api/companion/choices")
    def companion_choices(body: ChoicesSync) -> dict:
        """El audio, la variante y los subtítulos que eligió cada título, en la TV y en el iPhone: el iPhone manda lo que
        cambió y recibe lo que cambió aquí desde `since`. Si la TV lo cambió después de lo que el iPhone vio, gana la TV
        (`rejected`; su valor va en `changed`). No da más que eso: ni historial ni lo que se ve."""
        state = main_app.state.catalog.state
        rejected = []
        for meta_id, change in body.changes.items():
            if not MEDIA_ID.match(meta_id):
                continue
            fields = {k: getattr(change, k) for k in ("audio", "spanish", "subtitles") if getattr(change, k) is not None}
            fields.update({k: None for k in change.forget if k in ("audio", "spanish", "subtitles")})
            if not state.apply_choice(meta_id, fields, change.base_rev):
                rejected.append(meta_id)
        rev, changed = state.choices_since(body.since)
        for meta_id in rejected:  # lo que ganó la TV vuelve aunque sea viejo
            prefs = state.prefs(f"stremio:{meta_id}")
            changed[meta_id] = {**{k: prefs[k] for k in ("audio", "spanish", "subtitles") if isinstance(prefs.get(k), str)},
                                "rev": prefs.get("rev") or 0}
        return {"rev": rev, "changed": changed, "rejected": rejected}

    @public.post("/api/companion/resume")
    def companion_resume(body: ResumeSync) -> dict:
        """«Continuar» en cualquier aparato: el iPhone, iPad o Mac manda con qué fuente, audio y subtítulos vio cada video
        (gana lo más reciente, de aquí o de allá) y recibe lo que la TV recuerda de los títulos que pide en `want`."""
        watch = main_app.state.catalog.watch
        for meta_id, change in body.changes.items():
            if MEDIA_ID.match(meta_id) and MEDIA_ID.match(change.video_id):
                watch.apply_resume(meta_id, resume_from_device(change))
        wanted = [m for m in body.want if MEDIA_ID.match(m)]
        return {"resume": {m: resume_for_device(v) for m, v in watch.resumes_for(wanted).items()}}

    @public.post("/api/companion/inbox/ack")
    def companion_inbox_ack(body: CompanionAck) -> dict:
        """El iPhone ya actuó sobre estos pendientes: se quitan de la bandeja."""
        return {"removed": companion.inbox_ack(main_app.state.catalog.state, body.ids)}

    # La libreta de pedidos a Real-Debrid, para el iPhone (contrato «requests»): sin claves ni enlaces. Por ahora con el
    # token del túnel; pasa a la llave de cada aparato cuando existan (AD-3).
    # La lista de complementos, para el iPhone (corte S6, contrato `routes`): direcciones tapadas.
    @public.get("/api/addons")
    def companion_addons(request: Request, full: int = 0) -> JSONResponse:
        if full:  # las direcciones completas: solo con llave de aparato (contrato, secrets)
            with_key(request)
        return JSONResponse(main_app.state.catalog.watch.addon_list.shared(full=bool(full)),
                            headers={"Cache-Control": "no-store"})

    @public.put("/api/addons")
    async def companion_addons_put(request: Request):
        return await addons.addons_put(main_app.state.catalog.watch, request, device_of(request))

    # Las llaves por aparato (K1-A, contrato «devices»).
    @public.post("/api/devices/pair")
    async def pair_device(request: Request) -> JSONResponse:
        try:
            body = await request.json()
        except ValueError:
            body = {}
        body = body if isinstance(body, dict) else {}
        try:
            sent = bearer(request)
            got = main_app.state.devices.pair(body.get("code"), body.get("name"), body.get("platform"),
                                              previous=sent if devices.Devices.is_key(sent) else "")
        except devices.PairError as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status)
        bus = getattr(main_app.state, "bus", None)
        if bus is not None:
            bus.publish_threadsafe({"type": "phone-linked", "name": got["name"], "platform": got["platform"],
                                    "invited_by": got.get("invited_by")})
            bus.publish_threadsafe({"type": "settings-changed"})
        log.info("Aparato emparejado: %s (%s)", got["name"], got["platform"])
        return JSONResponse({"device_id": got["device_id"], "key": got["key"], "tv_name": "Orbital",
                             "tv_id": main_app.state.devices.tv_id()},
                            headers={"Cache-Control": "no-store"})

    @public.get("/api/devices")
    def companion_devices(request: Request) -> dict:
        mine = device_of(request)
        if mine is None:
            raise KeyRequired()
        return {"devices": main_app.state.devices.listing(this=mine["device_id"])}

    @public.delete("/api/devices/{device_id}")
    def companion_device_remove(device_id: str, request: Request) -> dict:
        mine = device_of(request)
        if mine is None:
            raise KeyRequired()
        if not devices.may_remove(mine, device_id):  # CX5: un iPad solo se quita a sí mismo
            raise HTTPException(403, "Solo tu iPhone o la TV pueden quitar otro aparato")
        if not forget_device(main_app, device_id):
            raise HTTPException(404, "Ese aparato ya no está")
        return {"devices": main_app.state.devices.listing(this=mine["device_id"])}

    @public.post("/api/devices/invite")
    def companion_device_invite(request: Request) -> JSONResponse:
        """CX4-A: la invitación de un toque para un iPad (viaja por iCloud). Solo la pide un iPhone, con su llave."""
        mine = device_of(request)
        if mine is None:
            raise KeyRequired()
        if mine["platform"] != "iphone":
            raise HTTPException(403, "Solo tu iPhone puede invitar a tu iPad.")
        return JSONResponse(main_app.state.devices.invite(mine["device_id"]), headers={"Cache-Control": "no-store"})

    @public.post("/api/devices/upgrade")
    async def companion_device_upgrade(request: Request) -> JSONResponse:
        """CX8-A: un iPhone con el token de antes pide su llave sin volver a escanear; la TV pregunta en pantalla."""
        if device_of(request) is not None:
            raise HTTPException(409, "Este aparato ya tiene su propia conexión.")
        try:
            body = await request.json()
        except ValueError:
            body = {}
        body = body if isinstance(body, dict) else {}
        try:
            ident = main_app.state.devices.ask_upgrade(body.get("name"), body.get("platform"))
        except devices.PairError as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status)
        pending = main_app.state.devices.pending_upgrade()
        bus = getattr(main_app.state, "bus", None)
        if bus is not None and pending:
            bus.publish_threadsafe({"type": "device-upgrade", **pending})
        return JSONResponse({"id": ident, "detail": "Confirma en la TV"}, status_code=202)

    @public.get("/api/devices/upgrade/{ident}")
    def companion_device_upgrade_result(ident: str) -> JSONResponse:
        state, got = main_app.state.devices.upgrade_result(ident)
        if state == "waiting":
            return JSONResponse({"detail": "Confirma en la TV"}, status_code=202)
        if state == "denied":
            return JSONResponse({"detail": "La TV dijo que no"}, status_code=403)
        if state != "ok" or got is None:
            return JSONResponse({"detail": "Ya no sirve: vuelve a pedirlo, o escanea el código de tu TV"}, status_code=404)
        return JSONResponse({"device_id": got["device_id"], "key": got["key"], "tv_name": "Orbital",
                             "tv_id": main_app.state.devices.tv_id()}, headers={"Cache-Control": "no-store"})

    @public.get("/api/realdebrid")
    def companion_debrid(request: Request, full: int = 0) -> JSONResponse:
        """Tu Real-Debrid para el iPhone; con ?full=1 la clave entera («Usar la de la TV»), solo con llave."""
        watch = main_app.state.catalog.watch
        device = with_key(request) if full else device_of(request)
        if device is None:
            raise KeyRequired()
        out = addons.run_debrid_status(watch)
        if full:
            out["token"] = watch.rd_token()
            watch.events.publish({"type": "toast", "message": f"«{device['name']}» tomó la clave de Real-Debrid",
                                  "detail": "Si no fuiste tú, quítalo en Ajustes › Cuentas"})
        return JSONResponse(out, headers={"Cache-Control": "no-store"})

    @public.put("/api/realdebrid")
    async def companion_debrid_put(request: Request) -> JSONResponse:
        """«Pasar a la TV»: la clave fija de tu Real-Debrid, probada antes de guardarla (contrato, secrets)."""
        device = with_key(request, "rd_put")
        try:
            body = await request.json()
        except ValueError:
            body = {}
        token = body.get("token") if isinstance(body, dict) else None
        if not isinstance(token, str) or not 20 <= len(token.strip()) <= 128:
            raise HTTPException(422, "Esa no parece una clave de Real-Debrid")
        try:
            out = await run_in_threadpool(main_app.state.catalog.watch.set_rd_token, token.strip(), device["name"])
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc
        except ConnectionError as exc:
            raise HTTPException(503, str(exc)) from exc
        return JSONResponse(out, headers={"Cache-Control": "no-store"})

    @public.put("/api/opensubtitles")
    async def companion_opensubtitles_put(request: Request) -> JSONResponse:
        """«Pasar a la TV»: tu cuenta de OpenSubtitles del iPhone (usuario y token, nunca la contraseña)."""
        with_key(request, "rd_put")  # el mismo límite que cambiar una clave (5 por hora)
        try:
            body = await request.json()
        except ValueError:
            body = {}
        token = body.get("token") if isinstance(body, dict) else None
        user = body.get("username") if isinstance(body, dict) else None
        if not isinstance(token, str) or not 10 <= len(token) <= 4096 or not isinstance(user, str) or not user.strip():
            raise HTTPException(422, "Esa no parece una cuenta de OpenSubtitles")
        watch = main_app.state.catalog.watch
        watch.opensubtitles.adopt({**body, "username": user.strip()})
        return JSONResponse(watch.opensubtitles.status(), headers={"Cache-Control": "no-store"})

    @public.get("/api/realdebrid/requests")
    def companion_debrid_requests() -> dict:
        return main_app.state.catalog.watch.rd.listing()

    @public.post("/api/realdebrid/requests")
    async def companion_debrid_request_in(request: Request) -> dict:
        raw = await addons.request_entry(request)
        return await run_in_threadpool(addons.receive_request, main_app.state.catalog.watch, raw)

    remote_bucket = {"tokens": 20.0, "at": time.monotonic()}  # el pad manda ~10 por segundo al mantener

    def remote_allowed() -> bool:
        now = time.monotonic()
        remote_bucket["tokens"] = min(20.0, remote_bucket["tokens"] + (now - remote_bucket["at"]) * 15)
        remote_bucket["at"] = now
        if remote_bucket["tokens"] < 1:
            return False
        remote_bucket["tokens"] -= 1
        return True

    @public.post("/api/companion/input")
    def companion_input(body: CompanionInput) -> dict:
        """El control remoto del iPhone: un botón, como si fuera del mando (a la interfaz o al reproductor)."""
        if not remote_allowed():
            raise HTTPException(429, "Más despacio")
        try:
            target = companion.remote_input(main_app.state.catalog, main_app.state.shell, body.action)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        return {"ok": True, "target": target}

    @public.post("/api/companion/text")
    def companion_text(body: CompanionText) -> dict:
        """«Escribir» del control del iPhone: el texto al campo con foco de la tele (sin QR)."""
        if not remote_allowed():
            raise HTTPException(429, "Más despacio")
        companion.remote_text(main_app.state.catalog, body.text, body.submit, body.replace)
        return {"ok": True}

    @public.get("/api/art/{item_id:path}")
    def companion_art(item_id: str, kind: str = "cover", w: int | None = None):
        """El arte de un juego para el iPhone (portada, fondo, logo): lo mismo que la tele, con el token del puerto público."""
        return library.art_response(main_app.state.catalog, item_id, kind, w)

    @public.get("/api/companion/console")
    def companion_console() -> dict:
        """Cómo está la consola mientras juegas (el iPhone lo pide cada ~30 s): batería, energía, wifi, mandos, memoria."""
        return companion.console_state(main_app.state.catalog)

    @public.post("/api/companion/console")
    def companion_console_set(body: CompanionConsole) -> dict:
        """Del iPhone: modo de energía o cerrar un programa (nunca el juego ni Orbital)."""
        try:
            return companion.console_action(main_app.state.catalog, body.power_mode, body.close_app)
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except (ValueError, PermissionError) as exc:
            raise HTTPException(409, str(exc))

    @public.post("/api/companion/game")
    def companion_game(body: CompanionGame) -> dict:
        """Volver al juego, ir al Inicio o cerrarlo desde el iPhone."""
        try:
            return {"game": companion.game_action(main_app.state.catalog, main_app.state.shell, body.action)}
        except companion.NothingPlaying as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(400, str(exc))

    @public.post("/api/companion/player")
    def companion_player(body: CompanionPlayerAction) -> dict:
        """Un botón de la tarjeta «Viendo en la TV»: pausa, adelantar, siguiente episodio o canal…"""
        try:
            now = companion.control_player(main_app.state.catalog, body.action, body.delta, body.level, body.track)
        except companion.NothingPlaying as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {"playing": now}

    # El iPhone llega por el túnel (a veces con datos móviles): Para ti y las listas viajan comprimidas (~5 veces menos).
    # Las conexiones en vivo (SSE) quedan fuera solas; la tele no lo necesita (todo es local).
    public.add_middleware(GZipMiddleware, minimum_size=1024)
    return public


def _volume() -> dict | None:
    from .. import quick

    try:
        return quick.volume()
    except OSError:
        return None


def _is_game_list(list_id: str) -> bool:
    return list_id == "mygames" or list_id.startswith("rawg:")


def _foryou_public_routes(public: FastAPI, main_app: FastAPI) -> None:
    """«Para ti» para el iPhone por el túnel: la misma curaduría de la consola (misma caché), sin juegos
    (el iPhone solo enseña películas y series)."""

    def foryou_of() -> Any:
        return main_app.state.catalog.foryou

    @public.get("/api/foryou")
    def overview() -> dict:
        data = foryou_of().overview()
        # Ni juegos ni lo que solo arma la TV (premios, estudios, años…): el iPhone calcula los suyos.
        data["lists"] = [row for row in data["lists"] if not _is_game_list(row["id"]) and not row["id"].startswith(TV_ONLY_PREFIXES)]
        data["mosaic"] = [item for item in data["mosaic"] if item.get("kind") != "game"]
        return data

    @public.get("/api/foryou/list")
    def items(id: str, kind: str | None = None) -> dict:
        list_id = id[:120]
        if _is_game_list(list_id) or list_id.startswith(TV_ONLY_PREFIXES):
            raise HTTPException(404, "Esa lista ya no existe.")
        try:
            return foryou_of().list_payload(list_id, kind)
        except KeyError:
            raise HTTPException(404, "Esa lista ya no existe.")
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude cargar esta lista. Revisa tu conexión e inténtalo de nuevo.")

    @public.get("/api/foryou/details")
    def details(key: str, kind: str | None = None) -> dict:
        value = key[:320]
        if value.startswith(("rawg:", "game:")):
            raise HTTPException(404, "No encontré esa sugerencia.")
        try:
            return foryou_of().details(value, kind)
        except KeyError:
            raise HTTPException(404, "No encontré esa sugerencia.")
        except SERVICE_ERRORS:
            return {"overview": ""}  # sin sinopsis no pasa nada

    @public.post("/api/foryou/dismiss")
    def dismiss(body: foryou.DismissRequest) -> dict:
        try:
            foryou_of().dismiss(body.key)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return {"ok": True}
