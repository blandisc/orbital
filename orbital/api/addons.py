"""Ajustes › Complementos («La TV sin Stremio», S1): tu lista, traerla de Stremio, prender, apagar, ordenar y quitar.

Solo para la pantalla de la propia consola: con la llave de otro aparato (o la de Alexa) no se llega aquí. Lo que el
iPhone manda (PUT /api/addons, design/addons-contract.json) llega con S6.
"""

from __future__ import annotations

from collections.abc import Callable

from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from ..library import stremio_api
from .deps import Deps


class ChangeRequest(BaseModel):
    id: str = Field(max_length=100)
    action: str = Field(pattern="^(on|off|up|down|remove)$")


class RestoreRequest(BaseModel):
    id: str = Field(max_length=100)


class SourceRequest(BaseModel):
    source: str = Field(pattern="^(own|stremio)$")


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

    return r
