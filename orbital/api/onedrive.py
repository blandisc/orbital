"""OneDrive: conectar la cuenta (código en la tele), elegir la carpeta de tus videos y lo encontrado (ver onedrive_library.py)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Response
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from .. import companion
from ..foryou import video_item
from ..library import onedrive
from ..onedrive_library import Linker
from .deps import Deps


class ClientRequest(BaseModel):
    id: str = Field("", max_length=200)


class FileRequest(BaseModel):
    id: str = Field(max_length=200)
    name: str = ""


class FolderRequest(BaseModel):
    path: str = Field("", max_length=1000)


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/onedrive")
    library = d.catalog.onedrive
    linker = Linker(library)

    def friendly(exc: Exception) -> HTTPException:
        if isinstance(exc, onedrive.OneDriveAuthError):
            return HTTPException(409, str(exc))
        return HTTPException(502, str(exc) if isinstance(exc, onedrive.OneDriveError) else "No pude conectar con OneDrive.")

    @r.get("")
    def status() -> dict:
        return library.status()

    @r.post("/client")
    def set_client(body: ClientRequest) -> dict:
        """El ID de la aplicación que registraste en Microsoft (Ajustes › Cuentas › Clave de OneDrive). Vacío: se quita."""
        value = body.id.strip()
        if value and not all(c.isalnum() or c == "-" for c in value):
            raise HTTPException(422, "Ese no parece un ID de aplicación (es como 1a2b3c4d-…).")
        library.client.credentials.set(onedrive.CLIENT_KEY, value or None)
        return library.status()

    @r.post("/link")
    def link() -> dict:
        try:
            return linker.start()
        except onedrive.OneDriveError as exc:
            raise HTTPException(502, str(exc))

    @r.post("/cancel")
    def cancel() -> dict:
        linker.cancel()
        return {"ok": True}

    @r.post("/unlink")
    def unlink() -> dict:
        library.client.unlink()
        d.catalog.notify({"type": "onedrive-changed"})
        return library.status()

    @r.get("/qr.svg")
    def qr() -> Response:
        """El QR de la página de Microsoft donde se escribe el código (el código se ve grande en la pantalla)."""
        return Response(companion.qr_svg("https://www.microsoft.com/link"), media_type="image/svg+xml",
                        headers={"Cache-Control": "max-age=86400"})

    @r.get("/folders")
    async def folders(path: str = "") -> dict:
        """Las carpetas de esa carpeta (para elegir dónde están tus videos; lo recorres tú en Ajustes)."""
        try:
            return {"path": path.strip("/"), "folders": await run_in_threadpool(library.client.folders, path[:1000])}
        except onedrive.OneDriveError as exc:
            raise friendly(exc)

    @r.post("/folder")
    def set_folder(body: FolderRequest) -> dict:
        library.set_folder(body.path)
        return library.status()

    @r.post("/scan")
    def scan() -> dict:
        library.scan_soon()
        return library.status()

    @r.get("/library")
    def mi_media() -> dict:
        """Mi media: tu carpeta como biblioteca (recién agregado, sagas, lo que ya viste y lo que no se reconoció)."""
        library.maybe_rescan()
        lib = library.library()
        foryou = d.catalog.foryou
        lib["sagas"] = foryou.sagas([t["imdb"] for t in lib["titles"] if t["kind"] == "movie"])
        lib["watched"] = [t["imdb"] for t in lib["titles"] if t["imdb"] in set(foryou.watched_ids())]
        return lib

    @r.post("/play-file")
    def play_file(body: FileRequest) -> dict:
        """Un video «Sin ficha», tal cual (con el reproductor de Orbital)."""
        from .. import player

        try:
            url = library.file_url(body.id)
        except onedrive.OneDriveError as exc:
            raise HTTPException(502, str(exc))
        mpv = player.find_mpv()
        if not url or not mpv:
            raise HTTPException(404, "Ese archivo ya no está en tu OneDrive." if not url else "Falta el reproductor de Orbital (mpv).")
        d.catalog.watch.play_native(mpv, url, "movie", f"onedrive:{body.id}", f"onedrive:{body.id}", body.name[:200] or "Video",
                                    from_start=True)
        return {"ok": True}

    @r.get("/titles")
    def titles() -> dict:
        """«En tu OneDrive»: una tarjeta por película o serie reconocida."""
        library.maybe_rescan()
        return {"items": [video_item(e, "En tu OneDrive") for e in library.titles()]}

    return r
