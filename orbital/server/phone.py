"""Lo que manda el iPhone (o el iPad) por el puerto público y la página para escribir en la tele desde el celular."""

from __future__ import annotations

import ipaddress
import re
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .. import companion, devices
from ..api.play import humane_error  # noqa: F401 - se importa desde aquí
from ..api.ui import SETTINGS  # noqa: F401
from ..config import Config
from ..remote_input import RemoteInput


class CompanionPlayerAction(BaseModel):
    action: str
    delta: float | None = None  # "skip": segundos (±10, ±30); "seek": a qué segundo; "volume": cuánto sube o baja (±5)
    level: int | None = None  # "volume": el nivel exacto (0-100)
    track: int | str | None = None  # "subtitles" / "audio": el id de playing.tracks ("no": sin subtítulos)


class CompanionGame(BaseModel):
    action: str  # "resume" | "home" | "close"


class CompanionConsole(BaseModel):
    power_mode: str | None = None  # "efficiency" | "balanced" | "performance"
    close_app: str | None = Field(None, max_length=80)  # el nombre de la lista de memoria («Chrome»)


class CompanionInput(BaseModel):
    action: str  # up, down, left, right, select, back, home, menu, search, options, pageleft, pageright


class CompanionText(BaseModel):
    text: str
    submit: bool = False
    replace: bool = False  # el texto reemplaza todo el campo (si no, se agrega)


class CompanionSend(BaseModel):
    action: str  # "open" (abrirlo en el iPhone) | "download" (descargarlo en el iPhone)
    kind: str  # "movie" | "series"
    meta_id: str
    video_id: str | None = None  # el episodio (si falta, el que sigue)


MEDIA_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:_.\-]{0,79}$")  # tt0096697, kitsu:12, tmdb:…


class CompanionAck(BaseModel):
    ids: list[str] = []


class ChoiceChange(BaseModel):
    """Lo que el iPhone eligió para un título: solo los campos que cambió (None = olvidar) y la última revisión que vio."""
    audio: str | None = Field(None, max_length=3)
    spanish: str | None = Field(None, max_length=6)
    subtitles: str | None = Field(None, max_length=6)
    forget: list[str] = Field(default_factory=list, max_length=3)
    base_rev: int = Field(0, ge=0)


class ResumeTrack(BaseModel):
    off: bool = False
    lang: str = Field("", max_length=20)
    title: str = Field("", max_length=200)
    url: str = Field("", max_length=1000)


class ResumeIn(BaseModel):
    """Con qué viste un video en el iPhone, iPad o Mac: la huella de la fuente, el audio, los subtítulos y cuándo."""
    video_id: str = Field(..., max_length=120)
    source: str | None = Field(None, max_length=500)
    audio: ResumeTrack | None = None
    subtitle: ResumeTrack | None = None
    at: float = Field(..., ge=0)


class ResumeSync(BaseModel):
    changes: dict[str, ResumeIn] = Field(default_factory=dict, max_length=100)
    want: list[str] = Field(default_factory=list, max_length=100)


def resume_from_device(change: ResumeIn) -> dict:
    """En el formato de la TV (`watch._remember_choice`): `sub` y `audio` como los da el reproductor."""
    sub = None
    if change.subtitle is not None:
        url = change.subtitle.url if change.subtitle.url.startswith(("http://", "https://")) else ""
        sub = {"off": True} if change.subtitle.off else {"off": False, "lang": change.subtitle.lang, "title": change.subtitle.title, "url": url}
    audio = {"lang": change.audio.lang, "title": change.audio.title} if change.audio and not change.audio.off else None
    return {"video_id": change.video_id, "source": change.source or None, "sub": sub, "audio": audio, "at": min(change.at, time.time())}


def resume_for_device(saved: dict) -> dict:
    sub = saved.get("sub") if isinstance(saved.get("sub"), dict) else None
    audio = saved.get("audio") if isinstance(saved.get("audio"), dict) else None
    return {"video_id": saved.get("video_id"), "source": saved.get("source"), "audio": audio,
            "subtitle": sub, "at": float(saved.get("at") or 0)}


class ChoicesSync(BaseModel):
    since: int = Field(0, ge=0)
    changes: dict[str, ChoiceChange] = Field(default_factory=dict, max_length=100)


def _companion_routes(app: FastAPI, config: Config) -> None:
    """«Conectar iPhone» en la TV: el QR y «Enviar/Descargar en el iPhone» (solo en el puerto local, el de la consola)."""
    from fastapi import Body
    from fastapi.responses import Response

    @app.get("/api/companion/phone")
    def phone() -> dict:
        """¿Hay iPhone conectado? (la TV solo ofrece «Enviar al iPhone» si sí)."""
        return {"ready": companion.phone_ready(config)}

    @app.post("/api/companion/send")
    def send_to_phone(body: CompanionSend) -> dict:
        try:
            item = companion.send_to_phone(app.state.catalog.watch, config, body.action[:20], body.kind[:20], body.meta_id[:80],
                                           body.video_id[:120] if body.video_id else None)
        except companion.PhoneNotConnected as exc:
            raise HTTPException(409, str(exc))
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        return {"item": item, "message": companion.SENT_TOAST[item["action"]]}

    def full() -> dict | None:
        if len(app.state.devices.listing()) >= devices.MAX_DEVICES:
            return {"ready": False, "reason": "Ya hay 10 aparatos conectados. Quita uno en Ajustes › Cuentas y vuelve a intentar."}
        return None

    @app.get("/api/companion/pair")
    def pair() -> dict:
        return full() or companion.pair_info(config)  # sin el código: ese va solo dentro del QR

    @app.get("/api/companion/pair.svg")
    def pair_svg() -> Response:
        if full():
            return Response(status_code=409)
        info = companion.pair_info(config, code=app.state.devices.code())
        if not info["ready"]:
            return Response(status_code=409)
        return Response(companion.qr_svg(info["link"]), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})

    @app.post("/api/companion/pair/close")
    def pair_close() -> dict:
        """Se cerró «Conectar iPhone»: el código del QR muere con la pantalla (K1-11)."""
        app.state.devices.close_code()
        return {"ok": True}

    @app.get("/api/devices")
    def paired_devices() -> dict:
        return {"devices": app.state.devices.listing()}

    @app.get("/api/devices/upgrade")
    def upgrade_pending() -> dict:
        return {"pending": app.state.devices.pending_upgrade()}

    @app.post("/api/devices/upgrade/{ident}")
    def upgrade_decide(ident: str, yes: bool = Body(False, embed=True)) -> dict:
        """«¿Darle llave a iPhone de Fernando?» (CX8-A): sin este sí no hay llave."""
        try:
            done = app.state.devices.decide_upgrade(ident, yes)
        except devices.PairError as exc:
            raise HTTPException(exc.status, exc.detail) from exc
        if not done:
            raise HTTPException(404, "Ya no está esperando: que lo vuelva a pedir")
        if yes:
            app.state.bus.publish_threadsafe({"type": "settings-changed"})
        return {"devices": app.state.devices.listing()}

    @app.delete("/api/devices/{device_id}")
    def remove_device(device_id: str) -> dict:
        """«Quitar» en Ajustes › Cuentas: la llave deja de servir al instante (sin Deshacer: ya no existe)."""
        if not forget_device(app, device_id):
            raise HTTPException(404, "Ese aparato ya no está")
        return {"devices": app.state.devices.listing()}


def forget_device(app: FastAPI, device_id: str) -> bool:
    """Quita un aparato: su llave y su prendido en tus complementos. Avisa a la interfaz (Cuentas se pone al día)."""
    if not app.state.devices.remove(device_id):
        return False
    watch = getattr(app.state.catalog, "watch", None)
    if watch is not None:
        watch.addon_list.forget_device(device_id)
    app.state.bus.publish_threadsafe({"type": "settings-changed"})
    return True


def bearer(request: Request) -> str:
    header = request.headers.get("authorization", "").strip()
    return header[7:].strip() if header[:7].lower() == "bearer " else header


def device_of(request: Request) -> dict | None:
    """El aparato que habla (su llave ya se revisó en el puerto público), o None con el token del túnel."""
    return getattr(request.state, "device", None)


KEY_REQUIRED = {"code": "device_key_required", "detail": "Vuelve a escanear el código de tu TV"}


class KeyRequired(Exception):  # noqa: N818 — 401 {code, detail} tal cual (contrato, devices › errors)
    """Falta la llave de aparato."""


async def key_required(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(KEY_REQUIRED, status_code=401)


def with_key(request: Request, kind: str = "secret") -> dict:
    """Lo que lleva una clave (contrato, secrets): solo con llave de aparato, solo desde loopback (Tailscale) y con su
    límite por hora."""
    device = device_of(request)
    if device is None:
        raise KeyRequired()
    client = request.client.host if request.client else ""
    try:
        loopback = ipaddress.ip_address(client).is_loopback
    except ValueError:
        loopback = False
    if not loopback:
        raise HTTPException(403, "Esto solo viaja por Tailscale")
    if not request.app.state.main.state.devices.allow(device["device_id"], kind):
        raise HTTPException(429, "Ya fueron muchas veces esta hora. Inténtalo más tarde.")
    return device


def _remote_input_routes(app: FastAPI, config: Config) -> None:
    """Escribir desde el celular (remote_input.py): la TV pide un código, enseña su QR y recoge lo escrito. Solo local."""
    from fastapi import Body, HTTPException
    from fastapi.responses import Response

    remote: RemoteInput = app.state.remote_input
    urls: dict[str, str] = {}

    @app.post("/api/remote-input")
    def remote_start(title: str = Body(""), fields: list = Body(default_factory=list), purpose: str | None = Body(None)) -> dict:
        info = companion.tunnel_info(config)  # el celular entra por el túnel de Tailscale (ya no hace falta Alexa)
        if not info["ready"]:
            return {"ready": False, "reason": info.get("reason", "")}
        if purpose == "realdebrid":  # CA2-A: los campos y las palabras los pone el servidor, no la interfaz
            code = remote.start(*RD_FORM, purpose="realdebrid", lead=RD_LEAD, submit_label="Usar esta clave")
        else:
            code = remote.start(title, fields)
        if code is None:
            raise HTTPException(422, "Formulario sin campos")
        urls.clear()
        urls[code] = f"https://{info['host']}/escribir/{code}"
        return {"ready": True, "code": code, "host": info["host"], "words": remote.words(code), "short": remote.short(code),
                "minutes": (remote.form(code) or {}).get("minutes", 10)}

    @app.post("/api/realdebrid/remote/confirm")
    def debrid_remote_confirm(code: str = Body("", embed=True)) -> dict:
        """«¿Usar la cuenta fernando?» → Sí: la clave que llegó del celular se guarda (la interfaz nunca la ve)."""
        values = remote.take(code, purpose="realdebrid")
        urls.pop(code, None)
        if values is None:
            raise HTTPException(409, "Ese código ya no sirve. Vuelve a abrir Conectar Real-Debrid.")
        return save_debrid_key(app, values.get("token", ""), "celular")

    @app.post("/api/realdebrid/key")
    def debrid_key(token: str = Body("", embed=True)) -> dict:
        """La clave pegada en la TV (TEC-4, sin túnel o sin celular): probada antes de guardarla."""
        return save_debrid_key(app, token, "tv")

    @app.get("/api/remote-input/qr.svg")
    def remote_qr(code: str = "") -> Response:
        if remote.form(code) is None or code not in urls:
            return Response(status_code=404)
        return Response(companion.qr_svg(urls[code]), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})

    @app.get("/api/remote-input/take")
    def remote_take(code: str = "") -> Response:
        values = remote.take(code)
        if values is None:
            return Response(status_code=204)
        urls.pop(code, None)
        return JSONResponse({"values": values}, headers={"Cache-Control": "no-store"})

    @app.post("/api/remote-input/cancel")
    def remote_cancel(code: str = Body("", embed=True)) -> dict:
        remote.cancel(code or None)
        urls.pop(code, None)
        return {"ok": True}


RD_FORM = ("Conectar Real-Debrid", [{"name": "token", "label": "Tu clave de Real-Debrid", "secret": True}])

RD_LEAD = "Ábrela en real-debrid.com/apitoken, cópiala y pégala aquí."


def save_debrid_key(app: FastAPI, token: object, source: str) -> dict:
    watch = app.state.catalog.watch
    try:
        return watch.set_rd_token(str(token or ""), "TV" if source == "tv" else "celular", source=source)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    except ConnectionError as exc:
        raise HTTPException(503, str(exc)) from exc


QUICK_CODE_WRONG = "Ese código no es el de tu TV, o ya cambió. Revisa la pantalla de la TV y escríbelo otra vez."

REMOTE_PAGE = Path(__file__).parent.with_name("remote_input_page.html")

# La página del celular no carga nada de fuera ni se deja incrustar; sin «Referer» (la dirección lleva el código).
REMOTE_HEADERS = {"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY",
                  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
                                             "connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"}


def remote_page(form: dict | None) -> str:
    import json
    data = json.dumps(form, ensure_ascii=False).replace("<", "\\u003c")  # que un nombre no cierre el <script>
    return REMOTE_PAGE.read_text(encoding="utf-8").replace("/*FORM*/null", data, 1)
