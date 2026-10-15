"""Películas y series: buscar, fichas, fuentes, reproducir, cuenta de Stremio y Mi lista."""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .. import player_ui
from ..library import cinemeta, stremio_api
from .deps import Deps

log = logging.getLogger(__name__)


class PlayRequest(BaseModel):
    kind: str
    id: str
    video_id: str | None = None
    title: str = ""
    source: int | None = None  # None: Orbital elige la recomendada y arranca
    keep: bool = False
    from_start: bool = False  # "Desde el principio"
    touch: bool = False  # lo abriste con el dedo: el reproductor empieza con botones táctiles, no glifos del mando


def stremio_message(exc: Exception) -> str:
    """El error de Stremio en palabras de la consola (no «Session not found»)."""
    from ..watch import expired_session

    if expired_session(exc):
        return "Tu sesión de Stremio caducó: vuelve a conectarla en Ajustes › Cuentas."
    text = str(exc)
    return text if any(c in text for c in "áéíóúñ¿") else f"Stremio no respondió bien ({text}). Inténtalo de nuevo."


def _title_ref(body: dict, missing: str) -> tuple[str, str]:
    kind, meta_id = body.get("kind"), body.get("id")
    if kind not in ("movie", "series") or not isinstance(meta_id, str) or not _clean_id(meta_id):
        raise HTTPException(400, missing)
    return kind, meta_id


def _clean_id(value) -> bool:
    """Un id de Cinemeta/Stremio que se puede mandar por internet (un sustituto Unicode suelto daba 500)."""
    if not isinstance(value, str) or not value.strip() or len(value) > 200:
        return False
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/stremio")
    catalog = d.catalog

    @r.get("/search")
    def search(q: str = "") -> dict:
        q = q.strip()[:120]  # nadie busca con más de 120 letras (y la URL de Cinemeta tiene límite)
        if len(q) < 2:
            return {"results": []}
        # Películas y series a la vez (antes una tras otra: con internet lento, el doble de espera).
        with ThreadPoolExecutor(max_workers=2) as pool:
            movies = pool.submit(catalog.cinemeta.search, "movie", q)
            series = pool.submit(catalog.cinemeta.search, "series", q)
            try:
                return {"results": cinemeta.search_results(q, movies.result(), series.result())}
            except cinemeta.CinemetaError:
                raise HTTPException(502, "Sin conexión con el catálogo de películas y series. Tus juegos siguen aquí.")

    @r.get("/title/{kind}/{meta_id}")
    def title(kind: str, meta_id: str) -> dict:
        """La ficha: datos, reparto, temporadas y dónde ibas."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            return catalog.watch.title_details(kind, meta_id)
        except cinemeta.TitleNotFound:
            raise HTTPException(404, "No encontré ese título.")
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar la ficha. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/episodes/{meta_id}")
    def episodes(meta_id: str) -> dict:
        try:
            meta = catalog.cinemeta.meta("series", meta_id)
        except cinemeta.TitleNotFound:
            raise HTTPException(404, "No encontré esa serie.")
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar los episodios. Revisa tu conexión e inténtalo de nuevo.")
        return {"id": meta_id, "title": meta.get("name") or "", "seasons": cinemeta.seasons(meta),
                "background": meta.get("background") or None, **cinemeta.describe_meta(meta)}

    @r.get("/sources")
    def sources(kind: str, id: str, video: str | None = None) -> dict:
        """Fuentes ordenadas por tus preferencias; la primera es la recomendada. Sin URLs."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        prefs, _ = catalog.watch.language_for(id)  # el idioma que recuerda este título, igual que al reproducir
        try:
            found = catalog.watch.stream_sources(kind, video or id, prefs)
        except stremio_api.StremioError as exc:
            raise HTTPException(409, stremio_message(exc))
        except Exception as exc:  # noqa: BLE001 - nunca «Internal Server Error» en la pantalla de fuentes
            log.exception("No pude buscar fuentes")
            raise HTTPException(502, "No pude conectar con tus complementos de Stremio. Revisa Internet e inténtalo de nuevo.") from exc
        if not found:
            raise HTTPException(404, catalog.watch.no_sources_message(kind, video or id))
        try:  # título, póster y fondo para la pantalla (de caché casi siempre)
            meta = catalog.cinemeta.meta(kind, id)
            info = {"title": meta.get("name") or "", "poster": meta.get("poster"), "background": meta.get("background"),
                    **cinemeta.describe_meta(meta)}
        except cinemeta.CinemetaError:
            info = {}
        return {"sources": [s.public() for s in found], "audio": prefs.audio, "quality": prefs.quality, "meta": info}

    @r.post("/play")
    def play(body: PlayRequest) -> dict:
        """Con `source`: esa fuente. Sin ella (y con el reproductor de Orbital): la recomendada, directo."""
        kind, meta_id = body.kind, body.id
        if kind not in ("movie", "series") or not _clean_id(meta_id) or (body.video_id is not None and not _clean_id(body.video_id)):
            raise HTTPException(400, "Falta qué reproducir")
        title = body.title or "Stremio"
        video_id = body.video_id or (meta_id if kind == "movie" else None)
        player_ui.set_touch(body.touch)
        try:
            if body.source is not None and video_id:
                catalog.watch.play_source(kind, meta_id, video_id, body.source, title, keep=body.keep,
                                    from_start=body.from_start)
                return {"ok": True, "reveal": catalog.revealing}
            if video_id and catalog.native_player:
                chosen = catalog.watch.play_best(kind, meta_id, video_id, title, keep=body.keep, from_start=body.from_start)
                return {"ok": True, "reveal": catalog.revealing, **chosen}
        except stremio_api.StremioError as exc:
            raise HTTPException(409, stremio_message(exc))
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except ValueError as exc:
            raise HTTPException(409, stremio_message(exc))
        except OSError as exc:  # el reproductor no abrió (falta, sin permiso…)
            raise HTTPException(500, f"No pude abrir el reproductor: {exc.strerror or exc}")
        catalog.sessions.play_stremio(kind, meta_id, body.video_id, title)
        return {"ok": True}

    @r.post("/login")
    def login(body: dict) -> dict:
        """Conectar Stremio desde la consola. La contraseña solo viaja a Stremio: no se guarda ni se
        registra; Orbital guarda la clave de sesión que devuelve (igual que `orbital stremio login`)."""
        email, password = str(body.get("email") or "").strip(), str(body.get("password") or "")
        if not email or not password:
            raise HTTPException(422, "Escribe tu correo y tu contraseña de Stremio")
        try:
            key = catalog.stremio_client.login(email, password)
            count = catalog.watch.link_stremio(key)
        except stremio_api.StremioUnreachable:
            raise HTTPException(502, "No pude conectar con Stremio. Revisa tu conexión a internet e inténtalo de nuevo.")
        except stremio_api.StremioError as exc:
            text = str(exc)
            if text.startswith(("No pude conectar", "Stremio respondió HTTP")):
                raise HTTPException(502, "No pude conectar con Stremio. Revisa Internet e inténtalo de nuevo.")
            if any(w in text.lower() for w in ("passphrase", "password", "user not found", "wrong", "invalid")):
                raise HTTPException(401, "El correo o la contraseña no son correctos.")
            raise HTTPException(401, "Stremio no aceptó esos datos. Revísalos e inténtalo de nuevo.")
        return {"ok": True, "count": count}

    @r.post("/logout")
    def logout() -> dict:
        catalog.watch.unlink_stremio()
        return {"ok": True}

    @r.post("/library")
    def my_list(body: dict) -> dict:
        """Mi lista: añadir o quitar."""
        kind, meta_id = _title_ref(body, "Falta qué añadir")
        if not isinstance(body.get("add"), bool):  # "false" (texto) no es «quitar»: se rechaza
            raise HTTPException(422, "Falta si añadir o quitar")
        try:
            catalog.watch.set_in_library(kind, meta_id, body["add"])
        except stremio_api.StremioError as exc:
            raise HTTPException(409, stremio_message(exc))
        return {"ok": True, "in_library": body["add"]}

    @r.post("/trailer")
    def trailer(body: dict) -> dict:
        kind, meta_id = _title_ref(body, "Falta de qué título")
        try:
            catalog.watch.play_trailer(kind, meta_id)
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar el tráiler. Revisa tu conexión.")
        return {"ok": True}

    @r.post("/dismiss")
    def dismiss(body: dict) -> dict:
        """Quitar de Seguir viendo."""
        meta_id = body.get("id").removeprefix("stremio:") if isinstance(body.get("id"), str) else ""
        if not meta_id:
            raise HTTPException(400, "Falta qué quitar")
        try:
            catalog.watch.dismiss_continue(meta_id)
        except stremio_api.StremioError as exc:
            raise HTTPException(409, stremio_message(exc))
        return {"ok": True}

    return r
