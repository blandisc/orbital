"""Biblioteca: lo que hay, volver a escanear, favoritos/ocultos y carátulas."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .deps import Deps


class PrefsRequest(BaseModel):
    id: str
    favorite: bool | None = None
    hidden: bool | None = None
    runner: str | None = None
    clear_runner: bool = False


def router(d: Deps) -> APIRouter:
    r = APIRouter()
    catalog = d.catalog

    @r.get("/api/library")
    def library() -> dict:
        catalog.refresh_stremio_if_stale()  # en segundo plano; avisa con "library-changed"
        return {"rows": catalog.grouped(), "hidden": catalog.hidden_count(), "scanning": catalog.scanning}

    @r.post("/api/library/refresh")
    def refresh() -> dict:
        return {"count": catalog.refresh(), "rows": catalog.grouped(), "hidden": catalog.hidden_count()}

    @r.post("/api/prefs")
    def prefs(body: PrefsRequest) -> dict:
        try:
            return catalog.set_prefs(body.id, favorite=body.favorite, hidden=body.hidden,
                                     runner=body.runner, clear_runner=body.clear_runner)
        except KeyError:
            raise HTTPException(404, "Elemento no encontrado")
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @r.post("/api/prefs/unhide-all")
    def unhide_all() -> dict:
        return {"restored": catalog.state.unhide_all()}

    @r.get("/api/setup")
    def setup() -> dict:
        return catalog.setup_status()

    @r.get("/api/art/{item_id:path}")
    def art(item_id: str, kind: str = "cover") -> FileResponse:
        # Solo se sirven imágenes que el escaneo asoció a un elemento: nunca rutas arbitrarias.
        item = catalog.get(item_id)
        path = None if item is None else (item.hero_path if kind == "hero" else item.art_path)
        if not path or not Path(path).is_file():
            raise HTTPException(404)
        return FileResponse(path, headers={"Cache-Control": "max-age=86400"})

    return r
