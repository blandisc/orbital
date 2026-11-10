"""«Para ti»: el mosaico, las listas (Trakt, TMDB, RAWG y tus juegos), la ficha y conectar Trakt."""

from __future__ import annotations

import logging
import time

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


class MatchRequest(BaseModel):
    kind: str
    id: str
    add: bool = True


class FollowRequest(BaseModel):
    id: str
    following: bool


class DropRequest(BaseModel):
    kind: str
    id: str
    dropped: bool = True
    following: bool = False  # regresar a «Viendo» con la campana prendida (como estaba antes de dejarla)


class TitleRef(BaseModel):
    kind: str
    id: str


class ManyRequest(BaseModel):
    where: str  # «watchlist» o «list:123»
    items: list[TitleRef]
    add: bool


class ItemsRequest(BaseModel):
    items: list[TitleRef]
    undo: bool = False


class ListManageRequest(BaseModel):
    action: str  # create · rename · privacy · delete · duplicate · reorder
    where: str = ""
    name: str = ""
    privacy: str = ""
    ids: list[str] = []


class ViewingRequest(BaseModel):
    action: str  # add · move · remove · undo
    kind: str
    id: str
    video_id: str | None = None
    viewing_id: int | None = None
    at: float | None = None  # segundos (la fecha nueva, o cuándo marcaste la que se deshace)


class IdsRequest(BaseModel):
    ids: list[int]


class NoteRequest(BaseModel):
    kind: str
    id: str
    text: str = ""


class SeasonRateRequest(BaseModel):
    id: str
    season: int
    stars: int | None = None


class RateRequest(BaseModel):
    kind: str
    id: str
    stars: int | None = None  # 1–5; None quita la calificación


class WatchedRequest(BaseModel):
    kind: str
    id: str
    video_id: str | None = None  # un episodio; sin él, la película o la serie completa
    when: str = "now"  # «now», «released», «unknown» o un momento (segundos, como texto)


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
            except Exception:  # noqa: BLE001 - un error inesperado en una lista no deja a Películas y series sin las demás
                log.exception("Para ti: la lista %s falló", ref.id)
                return {"items": [], "error": "No pude cargar esta lista.", "status": 500}

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

    def _trakt_call(fn, failed: str):
        """Lo que cambia tu cuenta de Trakt: reconectar dicho tal cual (409); sin red, en palabras (502)."""
        try:
            return fn()
        except ValueError as exc:
            raise HTTPException(400, str(exc))
        except trakt.TraktAuthError as exc:
            raise HTTPException(409, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, failed)

    @r.get("/filter")
    def filter_titles(kind: str = "movie", genre: str = "", decade: str = "", rating: str = "", fame: str = "",
                      platform: str = "", country: str = "", count: bool = False) -> dict:
        """El filtro avanzado (como el del iPhone): cuántos hay y, si no es solo contar, los primeros 20."""
        f = {"genre": genre[:30], "decade": decade[:6], "rating": rating[:2], "fame": fame[:10], "platform": platform[:20], "country": country[:2]}
        try:
            return foryou.filtered(kind, f, count_only=count)
        except tmdb.TmdbError as exc:
            raise HTTPException(409 if "clave" in str(exc) else 502, str(exc))
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude buscar con tu filtro. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/collections")
    def collections() -> dict:
        """Colecciones: los premios y las listas famosas, con cuántas ya viste de cada una."""
        return {"collections": foryou.collections(), "trakt": foryou.trakt.linked}

    @r.get("/match")
    def match_deck(mood: str = "") -> dict:
        """El mazo de hoy de «¿Qué vemos hoy?» (sin lo visto; del ánimo, si lo eliges)."""
        try:
            return {"cards": foryou.match_deck(mood or None)[:80], "trakt": foryou.trakt.linked}
        except SERVICE_ERRORS:
            raise HTTPException(502, "No pude armar el mazo. Revisa tu conexión e inténtalo de nuevo.")

    @r.post("/match")
    def match(body: MatchRequest) -> dict:
        """«Guardar» en «¿Qué vemos hoy?»: a «Tu match perfecto» de Trakt; «none» sin Trakt (la interfaz usa Mi lista)."""
        if body.kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        where = _trakt_call(lambda: foryou.save_match(body.kind, body.id[:20], body.add),
                            "No pude guardarla en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"where": where}

    @r.get("/rating")
    def rating(kind: str, id: str) -> dict:
        """Tus estrellas (1–5) de un título, o null."""
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            return {"stars": foryou.my_rating(kind, id[:20])}
        except SERVICE_ERRORS:
            return {"stars": None}

    @r.post("/rating")
    def rate(body: RateRequest) -> dict:
        """Calificar con estrellas (como el iPhone), o quitarlas."""
        if body.kind not in ("movie", "series") or (body.stars is not None and not 1 <= body.stars <= 5):
            raise HTTPException(400, "Calificación inválida")
        _trakt_call(lambda: foryou.rate(body.kind, body.id[:20], body.stars),
                    "No pude guardar tu calificación en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True}

    @r.get("/letterboxd")
    def title_letterboxd(kind: str, id: str) -> dict:
        """Letterboxd en la ficha: su promedio, sus reseñas populares y, con tu usuario, tu reseña."""
        return foryou.title_letterboxd(kind, id[:20])

    @r.get("/follow")
    def following(id: str) -> dict:
        """¿Sigues esta serie (la campana) y la dejaste? (el botón de estado de la ficha, G1-A)."""
        return foryou.gestor.state_of(id[:20])

    # --- el gestor tipo Trakt (G1–G4, como el iPhone): orbital/gestor.py ---------------------------------------------
    def _pairs(items: list[TitleRef]) -> list[tuple[str, str]]:
        pairs = [(i.kind, i.id[:20]) for i in items[:500] if i.kind in ("movie", "series")]
        if not pairs:
            raise HTTPException(400, "Elige algún título")
        return pairs

    @r.post("/drop")
    def drop(body: DropRequest) -> dict:
        """«La dejé» (o regresar a «Viendo»); sin internet se queda hecha y espera en la cola de Trakt."""
        if body.kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        sent = _trakt_call(lambda: foryou.gestor.set_dropped(body.kind, body.id[:20], body.dropped, body.following),
                           "No pude guardarlo en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, "queued": sent == "queued"}

    @r.get("/board")
    def board() -> dict:
        """Biblioteca › Guardado por estado (G2-A): los cuatro montones, «¿Las dejaste?», tus listas y lo que cambió solo."""
        found = _trakt_call(foryou.gestor.board, "No pude traer lo tuyo de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        if found.get("trakt"):
            found["changes"] = foryou.gestor.automatic_changes(found)
        return found

    @r.get("/my-lists")
    def my_lists() -> dict:
        """Tus listas de Trakt con quién las ve y cuántos títulos tienen (☰ de Guardado y de cada lista)."""
        return {"lists": _trakt_call(foryou.gestor.lists, "No pude leer tus listas de Trakt. Revisa tu conexión e inténtalo de nuevo.")}

    @r.post("/many")
    def many_titles(body: ManyRequest) -> dict:
        """Elegir varios (G3-A): ponerlos o quitarlos de Mi lista o de una de tus listas, en un solo envío."""
        sent = _trakt_call(lambda: foryou.gestor.set_many(body.where[:40], _pairs(body.items), body.add),
                           "No pude cambiar tu lista de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, "queued": sent == "queued"}

    @r.post("/drop-many")
    def drop_many(body: ItemsRequest) -> dict:
        """«Las dejé» con varios."""
        sent = _trakt_call(lambda: foryou.gestor.drop_many(_pairs(body.items)),
                           "No pude guardarlo en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, "queued": sent == "queued"}

    @r.post("/watched-many")
    def watched_many(body: ItemsRequest) -> dict:
        """«Vistas» con varios (solo películas, hoy); `undo` las quita de lo visto."""
        movies = [i for k, i in _pairs(body.items) if k == "movie"]
        fn = foryou.gestor.unmark_movies_watched if body.undo else foryou.gestor.mark_movies_watched
        _trakt_call(lambda: fn(movies), "No pude marcarlas en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, "movies": movies}

    @r.post("/list-manage")
    def list_manage(body: ListManageRequest) -> dict:
        """El «···» de cada lista tuya (G4-A) y «Nueva lista»: necesita conexión."""
        g = foryou.gestor
        actions = {
            "create": lambda: g.create_list(body.name),
            "rename": lambda: g.rename_list(body.where, body.name),
            "privacy": lambda: g.set_privacy(body.where, body.privacy),
            "delete": lambda: g.delete_list(body.where),
            "duplicate": lambda: g.duplicate_list(body.where, body.name),
            "reorder": lambda: g.reorder(body.where, [i[:20] for i in body.ids[:5000]]),
        }
        if body.action not in actions:
            raise HTTPException(400, "¿Qué hago con la lista?")
        found = _trakt_call(actions[body.action], "Esto necesita internet: revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, **(found if isinstance(found, dict) else {})}

    # --- ola 3 (O3-B): tus vistas, tu historial, tu nota y tus temporadas ----------------------------------------------
    def _kind(kind: str) -> str:
        if kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        return kind

    @r.get("/viewings")
    def viewings(kind: str, id: str, video_id: str = "") -> dict:
        """«Tus vistas»: cada vez que viste esta película o este capítulo, con su fecha y hora."""
        found = _trakt_call(lambda: foryou.gestor.viewings(_kind(kind), id[:20], video_id[:40] or None),
                            "No pude leer tu historial de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"viewings": found}

    @r.post("/viewings")
    def change_viewing(body: ViewingRequest) -> dict:
        """«La vi otra vez» (add), cambiar la fecha (move), borrar una (remove) o deshacer la de hoy (undo)."""
        g, kind, imdb, video = foryou.gestor, _kind(body.kind), body.id[:20], (body.video_id or "")[:40] or None
        actions = {
            "add": lambda: g.add_viewing(kind, imdb, video, body.at or time.time()),
            "move": lambda: g.move_viewing(body.viewing_id or 0, kind, imdb, video, body.at or time.time()),
            "remove": lambda: g.remove_viewings([body.viewing_id or 0]),
            "undo": lambda: "sent" if g.undo_viewing(kind, imdb, video, body.at or time.time()) else "missing",
        }
        if body.action not in actions:
            raise HTTPException(400, "¿Qué hago con esa vista?")
        sent = _trakt_call(actions[body.action], "No pude cambiar tu historial de Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": sent != "missing", "queued": sent == "queued"}

    @r.get("/history")
    def history(page: int = 1) -> dict:
        """Tu historial de Trakt, de 100 en 100, con las vistas repetidas marcadas."""
        return _trakt_call(lambda: foryou.gestor.history(max(1, min(page, 500))),
                           "No pude leer tu historial de Trakt. Revisa tu conexión e inténtalo de nuevo.")

    @r.post("/history/remove")
    def history_remove(body: IdsRequest) -> dict:
        """«Borrar N vistas repetidas»: solo esas; siempre queda la otra vista de cada una."""
        sent = _trakt_call(lambda: foryou.gestor.remove_viewings(body.ids[:500]),
                           "No pude borrar esas vistas en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True, "queued": sent == "queued"}

    @r.get("/note")
    def note(kind: str, id: str) -> dict:
        """«Tu nota»: el texto y dónde se guarda (Trakt con VIP; sin VIP, en esta tele)."""
        return _trakt_call(lambda: foryou.gestor.note(_kind(kind), id[:20]),
                           "No pude leer tu nota. Revisa tu conexión e inténtalo de nuevo.")

    @r.post("/note")
    def save_note(body: NoteRequest) -> dict:
        return _trakt_call(lambda: foryou.gestor.set_note(_kind(body.kind), body.id[:20], body.text[:2000]),
                           "No pude guardar tu nota. Revisa tu conexión e inténtalo de nuevo.")

    @r.get("/season-rating")
    def season_rating(id: str, season: int) -> dict:
        """Tus estrellas (1–5) de una temporada, o null."""
        try:
            return {"stars": foryou.gestor.season_stars(id[:20], season)}
        except SERVICE_ERRORS:
            return {"stars": None}

    @r.post("/season-rating")
    def rate_season(body: SeasonRateRequest) -> dict:
        if body.stars is not None and not 1 <= body.stars <= 5:
            raise HTTPException(400, "Calificación inválida")
        _trakt_call(lambda: foryou.gestor.rate_season(body.id[:20], body.season, body.stars),
                    "No pude guardar tu calificación en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True}

    @r.post("/follow")
    def follow(body: FollowRequest) -> dict:
        """Seguir o dejar de seguir una serie, como el iPhone (Trakt la oculta de tu calendario y de tu progreso)."""
        _trakt_call(lambda: foryou.set_following(body.id[:20], body.following),
                    "No pude guardarlo en Trakt. Revisa tu conexión e inténtalo de nuevo.")
        return {"ok": True}

    @r.post("/watched")
    def mark_watched(body: WatchedRequest) -> dict:
        """«¿Cuándo la viste?»: marca vista una película, un episodio o la serie completa, con su fecha."""
        if body.kind not in ("movie", "series"):
            raise HTTPException(400, "Tipo inválido")
        try:
            when: str | float = body.when if body.when in ("now", "released", "unknown") else float(body.when)
        except ValueError:
            raise HTTPException(400, "Fecha inválida")
        _trakt_call(lambda: foryou.mark_watched(body.kind, body.id[:20], (body.video_id or "")[:40] or None, when),
                    "No pude marcarla como vista en Trakt. Revisa tu conexión e inténtalo de nuevo.")
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
            raise HTTPException(404, "No encontré este título.")
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
