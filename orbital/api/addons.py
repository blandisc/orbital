"""Ajustes › Complementos («La TV sin Stremio», S1): tu lista, traerla de Stremio, prender, apagar, ordenar y quitar.

Lo de Complementos es solo para la pantalla de la propia consola: con la llave de otro aparato (o la de Alexa) no se llega
aquí. Lo que el iPhone manda (PUT /api/addons, design/addons-contract.json) llega con S6. La libreta de pedidos a Real-Debrid
(GET/POST /api/realdebrid/requests, corte S2) sí la leen y la escriben los dos: no lleva claves ni enlaces.
"""

from __future__ import annotations

import json
from collections.abc import Callable

from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from ..library import realdebrid, stremio_api
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

    @r.post("/api/addons/import")
    async def bring(request: Request) -> dict:
        local_only(request)
        try:
            done = await run_in_threadpool(watch.import_addons)
        except ValueError as exc:
            raise HTTPException(409, str(exc)) from exc
        except stremio_api.StremioError as exc:
            raise HTTPException(502, "No pude leer tus complementos de Stremio. Revisa Internet e inténtalo de nuevo.") from exc
        return {**watch.addon_status(), "done": done}

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

    @r.post("/api/addons/source")
    def source(body: SourceRequest, request: Request) -> dict:
        local_only(request)
        return watch.set_addon_source(body.source)

    # La libreta de pedidos a Real-Debrid (design/addons-contract.json, «requests»): la lee «Tus pedidos» y el iPhone.
    @r.get("/api/realdebrid/requests")
    def debrid_requests() -> dict:
        return watch.rd.listing()

    @r.post("/api/realdebrid/requests")
    async def debrid_request_in(request: Request) -> dict:
        raw = await request_entry(request)
        return await run_in_threadpool(receive_request, watch, raw)

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
