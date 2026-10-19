"""Descargas para ver sin internet: la lista, bajar una película o un episodio, verla del disco y quitarla."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .deps import Deps


class DownloadRequest(BaseModel):
    kind: str
    meta_id: str
    video_id: str
    title: str
    detail: str = ""
    poster: str | None = None
    season: int | None = None
    episode: int | None = None


class PlayRequest(BaseModel):
    from_start: bool = False


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/downloads")
    downloads = d.catalog.downloads

    @r.get("")
    def listing() -> dict:
        return {"items": downloads.list(), "folder": str(downloads.folder)}

    @r.post("")
    def add(body: DownloadRequest) -> dict:
        try:
            return downloads.add(body.kind, body.meta_id[:20], body.video_id[:40], body.title[:200], detail=body.detail[:120],
                                 poster=body.poster, season=body.season, episode=body.episode)
        except ValueError as exc:
            raise HTTPException(400, str(exc))

    @r.post("/{job_id}/retry")
    def retry(job_id: str) -> dict:
        if not downloads.retry(job_id[:80]):
            raise HTTPException(404, "Esa descarga ya no está.")
        return {"ok": True}

    @r.delete("/{job_id}")
    def remove(job_id: str) -> dict:
        if not downloads.remove(job_id[:80]):
            raise HTTPException(404, "Esa descarga ya no está.")
        return {"ok": True}

    @r.post("/play/{video_id}")
    def play(video_id: str, body: PlayRequest) -> dict:
        if not d.catalog.watch.play_downloaded(video_id[:40], from_start=body.from_start):
            raise HTTPException(404, "Esa descarga ya no está en el disco.")
        return {"ok": True}

    return r
