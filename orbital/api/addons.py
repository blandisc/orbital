"""Ajustes › Complementos («La TV sin Stremio», S1): tu lista, traerla de Stremio, prender, apagar, ordenar y quitar.

Prender, ordenar y configurar desde aquí es solo para la pantalla de la propia consola. La lista que cambias en el iPhone
llega por GET/PUT /api/addons (corte S6, design/addons-contract.json), con las direcciones tapadas. La libreta de pedidos a
Real-Debrid (GET/POST /api/realdebrid/requests, corte S2) la leen y la escriben los dos: no lleva claves ni enlaces.
"""

from __future__ import annotations

import json
import urllib.parse
from collections.abc import Callable

from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from ..library import addon_list, realdebrid, stremio_api
from .deps import Deps


class ChangeRequest(BaseModel):
    id: str = Field(max_length=100)
    action: str = Field(pattern="^(on|off|up|down|remove)$")


class RestoreRequest(BaseModel):
    id: str = Field(max_length=100)


class SourceRequest(BaseModel):
    source: str = Field(pattern="^(own|stremio)$")


class CancelRequest(BaseModel):
    hash: str = Field(pattern="^[0-9a-f]{40}$")


MAX_REQUEST_BODY = 16 * 1024  # contrato «requests»: post_body_bytes


async def request_entry(request: Request) -> dict:
    """El cuerpo de POST /api/realdebrid/requests: una entrada de la libreta, de 16 KB como mucho."""
    body = await request.body()
    if len(body) > MAX_REQUEST_BODY:
        raise HTTPException(413, "Petición demasiado grande")
    try:
        return json.loads(body)
    except ValueError as exc:
        raise HTTPException(422, "Ese pedido no tiene la forma acordada") from exc


def run_debrid_status(watch) -> dict:
    status = watch.debrid_status(fresh=True)
    return {k: v for k, v in status.items() if k != "token"}


async def addons_put(watch, request: Request, keyed: dict | None = None) -> JSONResponse:
    """PUT /api/addons: 200 con lo guardado, 409 con la lista actual, 422 si algo no cuadra (contrato, `routes`)."""
    body = await request.body()
    if len(body) > 64 * 1024:
        raise HTTPException(413, "Petición demasiado grande")
    try:
        raw = json.loads(body)
    except ValueError as exc:
        raise HTTPException(422, "La lista no tiene la forma acordada") from exc
    device = urllib.parse.unquote(request.headers.get("x-orbital-device", "iPhone"))[:60]
    try:
        saved = await run_in_threadpool(watch.receive_addons, raw, device, keyed)
    except addon_list.Conflict as exc:
        return JSONResponse(exc.current, status_code=409)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return JSONResponse(saved)


def receive_request(watch, raw: object) -> dict:
    try:
        return watch.rd.receive(raw)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


def router(d: Deps, is_local: Callable[[Request], bool]) -> APIRouter:
    r = APIRouter()
    watch = d.catalog.watch

    def local_only(request: Request) -> None:
        if not is_local(request):
            raise HTTPException(403, "Tus complementos solo se cambian en la TV")

    @r.get("/api/addons/status")
    def status(request: Request) -> dict:
        local_only(request)
        return watch.addon_status()

    @r.post("/api/addons/change")
    def change(body: ChangeRequest, request: Request) -> dict:
        local_only(request)
        try:
            return watch.change_addon(body.id, body.action)
        except KeyError as exc:
            raise HTTPException(404, "Ese complemento ya no está") from exc
        except ValueError as exc:
            raise HTTPException(409, str(exc)) from exc

    @r.post("/api/addons/restore")
    def restore(body: RestoreRequest, request: Request) -> dict:
        local_only(request)
        try:
            return watch.restore_addon(body.id)
        except KeyError as exc:
            raise HTTPException(404, "Ya no se puede deshacer") from exc

    # Corte S6: la lista viaja con el iPhone (design/addons-contract.json). Con el token del túnel mientras no haya llaves
    # por aparato (AD-3): las direcciones van tapadas y una con clave no entra.
    @r.get("/api/addons")
    def shared_addons() -> dict:
        return watch.addon_list.shared()

    @r.put("/api/addons")
    async def receive_addons(request: Request) -> JSONResponse:
        return await addons_put(watch, request)

    @r.post("/api/addons/torrentio")
    def torrentio_options(body: dict, request: Request) -> dict:
        """Ajustes › Complementos › Torrentio (corte S3): tus opciones; se guardan al cambiarlas."""
        local_only(request)
        options = body.get("options")
        if not isinstance(options, dict):
            raise HTTPException(422, "Faltan las opciones de Torrentio")
        return watch.set_torrentio(options)

    @r.post("/api/stremio/bring")
    async def bring_stremio(request: Request) -> dict:
        """«Traer de tu Stremio» (SS-8, corte S5): complementos y Mi lista, una vez; desde ahí Stremio es respaldo."""
        local_only(request)
        try:
            done = await run_in_threadpool(watch.bring_from_stremio)
        except ValueError as exc:
            raise HTTPException(409, str(exc)) from exc
        except stremio_api.StremioError as exc:
            raise HTTPException(502, "No pude leer tu Stremio. Revisa Internet e inténtalo de nuevo.") from exc
        return {**watch.addon_status(), "done": done}

    @r.post("/api/addons/source")
    def source(body: SourceRequest, request: Request) -> dict:
        local_only(request)
        try:
            return watch.set_addon_source(body.source)
        except ValueError as exc:  # 4 nov: ya no se regresa a los complementos de tu cuenta de Stremio
            raise HTTPException(422, "Tus complementos ya salen siempre de tu lista") from exc

    # La libreta de pedidos a Real-Debrid (design/addons-contract.json, «requests»): la lee «Tus pedidos» y el iPhone.
    @r.get("/api/realdebrid/requests")
    def debrid_requests() -> dict:
        return watch.rd.listing()

    @r.post("/api/realdebrid/requests")
    async def debrid_request_in(request: Request) -> dict:
        raw = await request_entry(request)
        return await run_in_threadpool(receive_request, watch, raw)

    @r.get("/api/realdebrid")
    def debrid_account() -> dict:
        """Tu Real-Debrid, revisado ahora (P6-A): usuario, Premium, vencimiento y la clave tapada; nunca entera."""
        return run_debrid_status(watch)

    @r.post("/api/realdebrid/requests/cancel")
    def debrid_cancel(body: CancelRequest, request: Request) -> dict:
        """«Cancelar pedido» en la TV: se quita de tu Real-Debrid y queda la lápida."""
        local_only(request)
        try:
            watch.rd.cancel(body.hash)
        except realdebrid.RealDebridError as exc:
            raise HTTPException(409, str(exc)) from exc
        return watch.rd.listing()

    return r
