"""TV en vivo: los canales por categoría y abrir uno en el reproductor."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from .deps import Deps

log = logging.getLogger(__name__)


class PlayRequest(BaseModel):
    id: str = Field(max_length=200)
    category: str = Field(default="todos", max_length=80)  # la lista por la que saltan ▲▼ (la pestaña de la que vienes)
    keep: bool = False  # abrir sin cerrar lo que estaba abierto


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/tv")
    tv = d.catalog.tv

    @r.get("")
    def overview() -> dict:
        """Pestañas de categoría y canales (con su número), más si se está revisando y si falta Internet."""
        return tv.overview()

    @r.post("/play")
    def play(body: PlayRequest) -> dict:
        try:
            result = tv.play(body.id, body.category, keep=body.keep)
            if result.get("tuned"):
                d.shell.resume()  # ya había un canal al aire: se sintonizó ahí mismo y solo falta traer su ventana al frente
            return result
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except OSError as exc:  # mpv no abrió (falta, sin permiso…)
            log.warning("No pude abrir el canal %s: %s", body.id, exc)
            raise HTTPException(500, f"No pude abrir el reproductor: {exc.strerror or exc}")

    @r.get("/logo")
    def logo(id: str = Query(max_length=200)) -> FileResponse:
        """El logo del canal, parejo y guardado en disco (se baja la primera vez). La TV no pide imágenes a internet."""
        path = tv.logo_path(id)
        if path is None:
            raise HTTPException(404, "Ese canal no tiene logo.")
        return FileResponse(path, media_type="image/png", headers={"Cache-Control": "public, max-age=86400"})

    @r.post("/refresh")
    def refresh() -> dict:
        """Buscar la lista y revisar los canales ahora (en segundo plano: el aviso llega por SSE)."""
        return {"ok": True, "started": tv.refresh(background=True)}

    return r
