"""«Para ti»: el mosaico, las listas (Trakt, TMDB, RAWG y tus juegos), la ficha y conectar Trakt."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..foryou import SERVICE_ERRORS
from ..library import rawg, tmdb, trakt
from .deps import Deps

log = logging.getLogger(__name__)


class DismissRequest(BaseModel):
    key: str


class KeysRequest(BaseModel):
    service: str
    values: list[str]


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/foryou")
    foryou = d.catalog.foryou

    @r.get("")
    def overview() -> dict:
        """Lo que se ve al entrar: qué servicios hay, el riel de listas y el mosaico."""
        return foryou.overview()

    @r.get("/list")
    def items(id: str, kind: str | None = None) -> dict:
        try:
            return {"items": foryou.list_items(id[:120], kind)}
        except KeyError:
            raise HTTPException(404, "Esa lista ya no existe.")
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS as exc:
            log.warning("Para ti: no pude cargar %s: %s", id, exc)
            raise HTTPException(502, "No pude cargar esta lista. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/details")
    def details(key: str, kind: str | None = None) -> dict:
        try:
            return foryou.details(key[:320], kind)
        except KeyError:
            raise HTTPException(404, "No encontré esa sugerencia.")
        except SERVICE_ERRORS:
            return {"overview": ""}  # sin sinopsis no pasa nada

    @r.post("/dismiss")
    def dismiss(body: DismissRequest) -> dict:
        try:
            foryou.dismiss(body.key)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return {"ok": True}

    @r.get("/status")
    def status() -> dict:
        return foryou.status()

    @r.post("/keys")
    def keys(body: KeysRequest) -> dict:
        """Las claves de Trakt, TMDB o RAWG escritas en Ajustes › Cuentas (vacías: se quitan)."""
        try:
            foryou.set_keys(body.service, body.values[:2])
        except (ValueError, tmdb.TmdbKeyError, rawg.RawgKeyError) as exc:
            raise HTTPException(422, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude comprobar la clave. Revisa Internet e inténtalo de nuevo.")
        return foryou.status()

    @r.post("/trakt/link")
    def link() -> dict:
        """Un código para escribir en trakt.tv/activate; Orbital avisa por SSE cuando quedó conectado."""
        try:
            return foryou.start_link()
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        except trakt.TraktError as exc:
            raise HTTPException(502, str(exc) if "Revisa la clave" in str(exc) else "No pude conectar con Trakt. Revisa Internet e inténtalo de nuevo.")

    @r.post("/trakt/cancel")
    def cancel() -> dict:
        foryou.cancel_link()
        return {"ok": True}

    @r.post("/trakt/unlink")
    def unlink() -> dict:
        foryou.unlink()
        return {"ok": True}

    return r
