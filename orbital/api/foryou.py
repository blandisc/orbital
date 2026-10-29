"""«Para ti»: el mosaico, las listas (Trakt, TMDB, RAWG y tus juegos), la ficha y conectar Trakt."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from .. import companion
from ..foryou import SERVICE_ERRORS
from ..library import rawg, tmdb, trakt
from .deps import Deps

log = logging.getLogger(__name__)


class DismissRequest(BaseModel):
    key: str


class KeysRequest(BaseModel):
    service: str
    values: list[str]


class ListRef(BaseModel):
    id: str
    kind: str | None = None


class ListsRequest(BaseModel):
    lists: list[ListRef]


class SaveRequest(BaseModel):
    kind: str
    id: str
    where: str  # «watchlist», «favorites» (tus favoritos de Trakt) o «list:123»
    add: bool


def router(d: Deps) -> APIRouter:
    r = APIRouter(prefix="/api/foryou")
    foryou = d.catalog.foryou

    @r.get("")
    def overview() -> dict:
        """Lo que se ve al entrar: qué servicios hay, el riel de listas y el mosaico."""
        return foryou.overview()

    def one(list_id: str, kind: str | None) -> dict:
        try:
            return foryou.list_payload(list_id[:120], kind)
        except KeyError:
            raise HTTPException(404, "Esa lista ya no existe.")
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS as exc:
            log.warning("Para ti: no pude cargar %s: %s", list_id, exc)
            raise HTTPException(502, "No pude cargar esta lista. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/list")
    def items(id: str, kind: str | None = None) -> dict:
        return one(id, kind)

    @r.post("/lists")
    def many(body: ListsRequest) -> dict:
        """Varias listas en una sola petición (los estantes de Películas y series): antes eran ~70 al arrancar. Cada una
        llega con lo suyo o con su error, y una que falla no tumba a las demás."""
        from concurrent.futures import ThreadPoolExecutor

        def safe(ref: ListRef) -> dict:
            try:
                return one(ref.id, ref.kind)
            except HTTPException as exc:
                return {"items": [], "error": exc.detail, "status": exc.status_code}

        wanted = body.lists[:120]
        with ThreadPoolExecutor(max_workers=4, thread_name_prefix="listas") as pool:  # como las 4 colas que tenía la interfaz
            payloads = list(pool.map(safe, wanted))
        return {"lists": [{"id": ref.id, "kind": ref.kind, **payload} for ref, payload in zip(wanted, payloads, strict=True)]}

    @r.get("/ratings")
    def ratings(ids: str = "") -> dict:
        """«movie:tt1,series:tt2» → {"tt1": 8.1, …}: la calificación de IMDb (ordenar una lista)."""
        wanted = [tuple(p.split(":", 1)) for p in ids[:4000].split(",") if p.count(":") == 1]
        return {"ratings": foryou.imdb_ratings([(k, i) for k, i in wanted])}

    @r.get("/saved")
    def saved(kind: str, id: str) -> dict:
        """«Guardar en…»: si está en tu watchlist, en tus favoritos y en cuáles de tus listas de Trakt."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            return foryou.saved_in(kind, id[:20])
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude leer tus listas de Trakt. Revisa tu conexión e inténtalo de nuevo.")

    @r.post("/save")
    def save(body: SaveRequest) -> dict:
        """Añadir o quitar de tu watchlist, de tus favoritos o de una de tus listas de Trakt."""
        if body.kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            foryou.save_to(body.kind, body.id[:20], body.where[:40], body.add)
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        except (trakt.TraktAuthError, trakt.TraktFavoritesFull) as exc:  # reconectar, o quitar un favorito: dicho tal cual
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude cambiar tu lista de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True}

    @r.get("/title-extras")
    def title_extras(kind: str, id: str) -> dict:
        """Frase, clasificación, créditos y «Más como esto» de un título (la ficha, como el iPhone)."""
        return foryou.title_extras(kind, id[:20])

    @r.get("/title-ratings")
    def title_ratings(kind: str, id: str) -> dict:
        """IMDb, TMDB y Trakt de un título (la ficha, como el iPhone)."""
        return foryou.title_ratings(kind, id[:20])

    @r.get("/person/{person_id}")
    def person(person_id: int) -> dict:
        """Una persona del reparto: foto, biografía y filmografía (TMDB), como el iPhone."""
        try:
            return foryou.person(person_id)
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude traer a la persona %s: %s", person_id, exc)
            raise HTTPException(502, "No pude traer a esta persona de TMDB. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/tmdb-imdb")
    def tmdb_imdb(kind: str, id: int) -> dict:
        """El IMDb de un título de la filmografía (para abrir su ficha)."""
        try:
            imdb = foryou.tmdb_imdb(kind, id)
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude abrir este título. Revisa tu conexión e inténtalo de nuevo.")
        if not imdb:
            raise HTTPException(404, "Este título no está en Stremio.")
        return {"imdb": imdb}

    @r.get("/decide")
    def decide(time: str | None = None, mood: str | None = None, kind: str | None = None, genres: str = "",
               watched: bool = False) -> dict:
        """«¿Qué vemos?»: tres propuestas que caben en tu tiempo y tu ánimo, como el iPhone."""
        return foryou.decide(time, mood, kind, [g for g in genres[:300].split(",") if g], watched)

    @r.post("/decide/skip")
    def decide_skip(body: DismissRequest) -> dict:
        """«Hoy no»: esa propuesta no vuelve en 24 horas."""
        foryou.skip_today(body.key.removeprefix("video:"))
        return {"ok": True}

    @r.get("/calendar")
    def calendar_month(month: str = "") -> dict:
        """El mes de estrenos de las series que sigues (vista calendario), como el iPhone. `month`: AAAA-MM (si no, este)."""
        import re as _re
        from datetime import date as _date

        today = _date.today()
        m = _re.fullmatch(r"(\d{4})-(\d{2})", month or "")
        year, mon = (int(m[1]), int(m[2])) if m else (today.year, today.month)
        if not 1 <= mon <= 12 or abs((year - today.year) * 12 + mon - today.month) > 24:
            raise HTTPException(400, "Mes inválido")
        if not foryou.trakt.linked:
            raise HTTPException(409, "Conecta Trakt (Ajustes › Cuentas) para ver lo que sale de tus series.")
        try:
            return foryou.calendar_month(year, mon)
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude leer tu calendario de Trakt. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/year")
    def year() -> dict:
        """«Tu año»: lo que viste este año según Trakt (horas, racha, tu género, el mapa y lo que más viste)."""
        try:
            review = foryou.year_review()
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude leer tu historial de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        if review is None:
            raise HTTPException(409, "Conecta Trakt (Ajustes › Cuentas) para ver tu año.")
        return review

    @r.get("/watched")
    def watched() -> dict:
        """Los IMDb de lo que ya viste en Trakt (para «Ocultar lo que ya vi»)."""
        return {"ids": foryou.watched_ids()}

    @r.get("/details")
    def details(key: str, kind: str | None = None) -> dict:
        try:
            return foryou.details(key[:320], kind)
        except KeyError:
            raise HTTPException(404, "No encontré esa sugerencia.")
        except SERVICE_ERRORS:
            return {"overview": ""}  # sin sinopsis no pasa nada

    @r.get("/logo/{imdb}")
    def logo(imdb: str) -> Response:
        """El logo del título sin su aire transparente (ver ForYou.trimmed_logo)."""
        png = foryou.trimmed_logo(imdb[:20])
        if png is None:
            raise HTTPException(404, "Sin logo.")
        return Response(png, media_type="image/png", headers={"Cache-Control": "public, max-age=604800"})

    @r.post("/dismiss")
    def dismiss(body: DismissRequest) -> dict:
        try:
            foryou.dismiss(body.key)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        return {"ok": True}

    @r.get("/today")
    def today() -> dict:
        """{IMDb: «19:00»} de lo que sale hoy de tus series (el Inicio lo marca «Sale hoy»)."""
        return {"airing": foryou.airing_today()}

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

    @r.get("/trakt/qr.svg")
    def trakt_qr() -> Response:
        """El QR de la página de Trakt donde se escribe el código (no lleva el código: ese se ve grande en la pantalla)."""
        return Response(companion.qr_svg("https://trakt.tv/activate"), media_type="image/svg+xml",
                        headers={"Cache-Control": "max-age=86400"})

    @r.post("/trakt/cancel")
    def cancel() -> dict:
        foryou.cancel_link()
        return {"ok": True}

    @r.post("/trakt/unlink")
    def unlink() -> dict:
        foryou.unlink()
        return {"ok": True}

    return r
