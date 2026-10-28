"""Películas y series: buscar, fichas, fuentes, reproducir, cuenta de Stremio y Mi lista."""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .. import player_ui, watch
from ..library import cinemeta, stremio_api
from .deps import Deps

log = logging.getLogger(__name__)


class Track(BaseModel):
    """Una pista de audio o subtítulos, como la etiquetan los dos reproductores (idioma y nombre)."""
    off: bool = False  # subtítulos quitados
    lang: str = Field("", max_length=20)
    title: str = Field("", max_length=200)
    url: str = Field("", max_length=2000)  # subtítulos de un complemento (OpenSubtitles…)


class PlayRequest(BaseModel):
    kind: str
    id: str
    video_id: str | None = None
    title: str = ""
    source: int | None = None  # None: Orbital elige la recomendada y arranca
    keep: bool = False
    from_start: bool = False  # "Desde el principio"
    remember: bool = False  # «Versión» › «Desde aquí»: la serie sigue con el idioma de esta versión
    touch: bool = False  # lo abriste con el dedo: el reproductor empieza con botones táctiles, no glifos del mando
    keyboard: bool = False  # lo abriste con el teclado: la barra enseña las teclas
    # «Ver en la TV» desde el reproductor del iPhone: lo que venías viendo ahí, para seguir igual en la TV.
    position: float | None = Field(None, ge=0, le=86400 * 2)  # el segundo exacto
    source_key: str | None = Field(None, max_length=500)  # la huella de la fuente (streams.Source.key)
    audio: Track | None = None
    subtitle: Track | None = None

    def handoff(self) -> dict | None:
        if self.position is None and not self.source_key and self.audio is None and self.subtitle is None:
            return None
        sub = self.subtitle.model_dump() if self.subtitle else None
        if sub and not sub["url"].startswith(("http://", "https://")):
            sub["url"] = ""  # solo direcciones web: nada de rutas de archivo
        return {"position": self.position, "source": self.source_key,
                "audio": {"lang": self.audio.lang, "title": self.audio.title} if self.audio else None, "subtitle": sub}


def stremio_message(exc: Exception) -> str:
    """El error de Stremio en palabras de la consola (no «Session not found»)."""
    from ..watch import expired_session

    if expired_session(exc):
        return "Tu sesión de Stremio caducó: vuelve a conectarla en Ajustes › Cuentas."
    text = str(exc)
    if text == stremio_api.NOT_LINKED:
        return text
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


# Los géneros que se piden por estante (los nombres de Cinemeta).
GENRES = {"Horror", "Comedy", "Action", "Sci-Fi", "Drama", "Animation", "Thriller", "Romance", "Crime", "Documentary", "Adventure", "Family"}


class ArtChoice(BaseModel):
    meta_id: str = Field(max_length=20)
    which: str = Field(max_length=12)  # "poster" | "background"
    url: str | None = Field(default=None, max_length=300)


def trakt_meta(e: dict) -> dict:
    """Un resultado de Trakt en la forma de Cinemeta (para search_results): el póster de siempre (metahub, por IMDb)."""
    year = str(e.get("year") or "")
    return {"id": e["imdb"], "name": e["title"], "releaseInfo": year, "genres": e.get("genres") or [],
            "description": e.get("overview") or "", "poster": f"https://images.metahub.space/poster/medium/{e['imdb']}/img"}


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
            movies = pool.submit(search_kind, "movie", q)
            series = pool.submit(search_kind, "series", q)
            try:
                return {"results": cinemeta.search_results(q, movies.result(), series.result())}
            except cinemeta.CinemetaError:
                raise HTTPException(502, "Sin conexión con el catálogo de películas y series. Tus juegos siguen aquí.")

    def search_kind(kind: str, q: str) -> list[dict]:
        """Cinemeta; si falla (un «HTTP 550» pasajero), una vez más; y si sigue, la búsqueda de Trakt (sin sesión), como
        el iPhone. Lanza CinemetaError solo si todo falló."""
        error: cinemeta.CinemetaError | None = None
        for _ in range(2):
            try:
                return catalog.cinemeta.search(kind, q)
            except cinemeta.CinemetaError as exc:
                error = exc
        trakt = getattr(getattr(catalog, "foryou", None), "trakt", None)
        if trakt is not None and trakt.configured:
            try:
                return [trakt_meta(e) for e in trakt.search(kind, q)]
            except Exception:  # noqa: BLE001 - Trakt también caído: se dice lo de Cinemeta
                pass
        raise error or cinemeta.CinemetaError("Sin resultados")

    @r.get("/genre")
    def genre(kind: str = "movie", genre: str = "") -> dict:
        """Lo más popular de un género en el catálogo de Stremio (Películas y series · estantes por género)."""
        if kind not in ("movie", "series") or genre not in GENRES:
            raise HTTPException(400, "Género inválido")
        try:
            return {"items": [catalog.describe(i) for i in cinemeta.catalog_items(kind, catalog.cinemeta.genre(kind, genre), 15)]}
        except cinemeta.CinemetaError:
            raise HTTPException(502, "Sin conexión con el catálogo de películas y series.")

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

    @r.get("/art")
    def art_choices(kind: str, id: str) -> dict:
        """«Cambiar el arte»: los pósters y fondos que se pueden elegir y los que tiene ahora."""
        if kind not in ("movie", "series") or not id.startswith("tt"):
            raise HTTPException(400, "Solo películas y series")
        try:
            return catalog.watch.art_choices(kind, id[:20])
        except LookupError as exc:
            raise HTTPException(404, str(exc))

    @r.post("/art")
    def set_art(body: ArtChoice) -> dict:
        """Elegiste un póster o un fondo (o `url` vacío: el de siempre). Se ve ya en la biblioteca, Para ti y la ficha."""
        try:
            art = catalog.watch.set_art(body.meta_id[:20], body.which, body.url or None)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        catalog.apply_art(body.meta_id[:20])
        return {"ok": True, "art": art}

    @r.get("/remembered")
    def remembered() -> dict:
        """Lo que recuerda cada título (el idioma y los subtítulos que elegiste viéndolo; vale aquí y en el iPhone)."""
        return {"titles": catalog.watch.remembered()}

    @r.post("/remembered/forget")
    def forget_remembered(body: dict) -> dict:
        meta_id = body.get("id") if isinstance(body, dict) else None
        if not isinstance(meta_id, str) or not 0 < len(meta_id) <= 80:
            raise HTTPException(400, "Título inválido")
        catalog.state.forget_choices(meta_id)
        return {"titles": catalog.watch.remembered()}

    @r.get("/sources")
    def sources(kind: str, id: str, video: str | None = None) -> dict:
        """Fuentes ordenadas por tus preferencias; la primera es la recomendada. Sin URLs."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        prefs, subtitles = catalog.watch.language_for(id)  # el idioma que recuerda este título, igual que al reproducir
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
        # La que pondría «Ver» (con «Continuar», la de antes) y cómo va a sonar: la ficha lo dice bajo el botón.
        chosen = catalog.watch.choose_source(kind, video or id, prefs, catalog.watch.resume_choice(id, video or id))
        recommended = {"id": chosen.index, "line": watch.version_line(chosen, prefs, subtitles),
                       "note": watch.version_note(chosen, prefs)} if chosen else None
        downloads = catalog.watch.downloads
        if recommended and downloads is not None and downloads.file_for(video or id):
            recommended["line"] = "Tu descarga · sin internet"  # «Ver» la pone del disco
        return {"sources": [s.public() for s in found], "audio": prefs.audio, "spanish": prefs.spanish,
                "quality": prefs.quality, "meta": info, "recommended": recommended}

    @r.post("/play")
    def play(body: PlayRequest) -> dict:
        """Con `source`: esa fuente. Sin ella (y con el reproductor de Orbital): la recomendada, directo."""
        kind, meta_id = body.kind, body.id
        if kind not in ("movie", "series") or not _clean_id(meta_id) or (body.video_id is not None and not _clean_id(body.video_id)):
            raise HTTPException(400, "Falta qué reproducir")
        title = body.title or "Stremio"
        video_id = body.video_id or (meta_id if kind == "movie" else None)
        player_ui.set_input("touch" if body.touch else "keyboard" if body.keyboard else "gamepad")
        if kind == "series" and not video_id and catalog.native_player:
            # Una serie sin episodio (la elegiste en la lista del iPhone): su ficha en la tele, como la voz, para elegir
            # el episodio o seguir donde ibas (antes abría la app de Stremio).
            if d.kiosk is not None:
                d.kiosk.open()
            catalog.events.publish({"type": "open-view", "view": {"serie": meta_id}, "message": f"Abriendo {title}"})
            return {"ok": True, "opened": "title"}
        try:
            if body.source is not None and video_id:
                catalog.watch.play_source(kind, meta_id, video_id, body.source, title, keep=body.keep,
                                    from_start=body.from_start)
                if body.remember:
                    catalog.watch.remember_version(kind, meta_id, video_id, body.source)
                return {"ok": True, "reveal": catalog.revealing}
            if video_id and catalog.native_player:
                chosen = catalog.watch.play_best(kind, meta_id, video_id, title, keep=body.keep, from_start=body.from_start,
                                                 handoff=body.handoff())
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

    d.extra["play_stremio"] = play  # «Ver en la TV» del iPhone entra por el puerto público (server.create_public_app)

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
            reveal = catalog.watch.play_trailer(kind, meta_id, keep=body.get("keep") is True)
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except cinemeta.CinemetaError:
            raise HTTPException(502, "No pude cargar el tráiler. Revisa tu conexión.")
        return {"ok": True, "reveal": reveal}

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
