"""Ajustes › Cuentas › OpenSubtitles en la TV: conectar tu cuenta (usuario y contraseña, desde la TV o el celular) y quitarla.
La contraseña solo viaja a OpenSubtitles; se guarda el token, cifrado en secrets.json. La interfaz nunca ve el token."""

from __future__ import annotations

from fastapi import APIRouter, Body, HTTPException
from fastapi.concurrency import run_in_threadpool

from ..library import opensubtitles
from .deps import Deps


def router(d: Deps) -> APIRouter:
    r = APIRouter()

    def client() -> opensubtitles.OpenSubtitles:
        return d.catalog.watch.opensubtitles

    @r.get("/api/opensubtitles")
    def status() -> dict:
        return client().status()

    @r.post("/api/opensubtitles/login")
    async def login(username: str = Body(""), password: str = Body("")) -> dict:
        try:
            out = await run_in_threadpool(client().login, username, password)
        except opensubtitles.OpenSubtitlesError as exc:
            raise HTTPException(503 if exc.code == "offline" else 422, str(exc)) from exc
        return out

    @r.post("/api/opensubtitles/logout")
    def logout() -> dict:
        client().logout()
        return client().status()

    return r
