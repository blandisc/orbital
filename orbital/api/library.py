"""Biblioteca: lo que hay, volver a escanear, favoritos/ocultos y carátulas."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, RedirectResponse
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from .. import thumbs
from .deps import Deps


class PrefsRequest(BaseModel):
    id: str
    favorite: bool | None = None
    hidden: bool | None = None
    runner: str | None = None
    clear_runner: bool = False


class ArtReplace(BaseModel):
    id: str
    kind: str


def router(d: Deps) -> APIRouter:
    r = APIRouter()
    catalog = d.catalog

    @r.get("/api/library")
    def library() -> dict:
        catalog.watch.refresh_stremio_if_stale()  # en segundo plano; avisa con "library-changed"
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

    @r.get("/api/folders")
    def folders() -> dict:
        """Dónde busca Orbital: cada emulador con su programa y sus carpetas de juegos."""
        counts: dict[str, int] = {}
        for item in catalog.items():
            if item.category == "emulators":
                counts[item.source] = counts.get(item.source, 0) + 1
        return {"emulators": [{"name": e.name, "executable": e.executable, "rom_dirs": list(e.rom_dirs),
                               "games": counts.get(e.id, 0)} for e in catalog.emulators],
                "config": str(d.config.source) if d.config.source else None}

    @r.get("/api/setup")
    def setup() -> dict:
        return catalog.setup_status()

    @r.post("/api/art-replace")
    async def art_replace(req: ArtReplace) -> dict:
        """«No me gusta esta imagen»: la descarta para siempre y busca otra (o queda el respaldo)."""
        if req.kind not in ("cover", "hero", "logo"):
            raise HTTPException(422, "Tipo de imagen desconocido")
        if catalog.get(req.id) is None:
            raise HTTPException(404, "Ese juego ya no está en tu biblioteca")
        found = await run_in_threadpool(catalog.replace_art, req.id, req.kind)
        return {"ok": True, "found": found}

    @r.get("/api/art/{item_id:path}")
    def art(item_id: str, kind: str = "cover", w: int | None = None) -> FileResponse:
        return art_response(catalog, item_id, kind, w)

    @r.get("/api/img")
    def web_art(u: str, w: int = 480):
        """El arte de internet al ancho en que se ve (remote_art.py); si no se pudo, la dirección original."""
        from .. import remote_art

        if not remote_art.allowed(u):
            raise HTTPException(404)
        path = remote_art.sized(u, max(120, min(1280, w)))
        if path is None:
            return RedirectResponse(u, status_code=307)
        return FileResponse(path, media_type=image_type(path), headers={"Cache-Control": "max-age=604800"})

    return r


def art_response(catalog, item_id: str, kind: str = "cover", w: int | None = None) -> FileResponse:
    """El arte de un elemento (la tele y, con token, el iPhone). Solo imágenes que el escaneo asoció a un elemento: nunca
    rutas arbitrarias."""
    item = catalog.get(item_id)
    paths = {"hero": "hero_path", "logo": "logo_path", "icon": "icon_path"}
    path = None if item is None else getattr(item, paths.get(kind, "art_path"))
    if not path or not Path(path).is_file():
        raise HTTPException(404)
    if w is not None and kind in ("cover", "hero"):  # la tarjeta pide la imagen a su tamaño (thumbs.py)
        path = thumbs.thumbnail(Path(path), max(120, min(1280, w)), catalog.thumbs_dir())
    # Windows no siempre conoce .webp: sin esto salía como «application/octet-stream».
    media_type = "image/webp" if str(path).lower().endswith(".webp") else None
    return FileResponse(path, media_type=media_type, headers={"Cache-Control": "max-age=86400"})


def image_type(path: Path) -> str:
    """El tipo por sus primeros bytes (los originales bajados se guardan sin extensión de imagen)."""
    try:
        with open(path, "rb") as f:
            head = f.read(12)
    except OSError:
        return "application/octet-stream"
    if head.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if head.startswith(b"\x89PNG"):
        return "image/png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    if head[:3] == b"GIF":
        return "image/gif"
    return "application/octet-stream"
