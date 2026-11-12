"""Las fichas: detalles, calificaciones, Letterboxd, logos, pósters, personas y sagas.
"""

from __future__ import annotations

import logging
import re
import threading
import time
from collections.abc import Callable

from ..atomic import atomic_write
from ..library import certification
from ..library import letterboxd as letterboxd_api
from ..library import rawg as rawg_api
from ..library import tmdb as tmdb_api
from ..net import NET_FAILURES
from . import pools
from .base import LOGO_RETRY, METAHUB, METAHUB_POSTER, POSTER_TTL, RECS_TTL, SERVICE_ERRORS, SLOW_TTL
from .items import runtime_text, video_item, whiten_if_dark
from .sources import _Sources

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Titles(_Sources):
    """Las fichas: detalles, calificaciones, Letterboxd, logos, pósters, personas y sagas."""

    def tmdb_poster(self, imdb: str) -> str | None:
        """El póster de TMDB de un título (P1, Fernando 8 nov: primero TMDB, el de metahub a veces es de otro título; como
        el iPhone). None sin clave de TMDB, si TMDB no lo tiene o si no contesta: va el de metahub."""
        if not self.tmdb.configured or not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            return None
        if time.monotonic() < self._posters_down_until:  # TMDB no contestó hace poco: no se espera por cada póster
            return None
        try:
            return self.cache.get(f"poster:{imdb}", POSTER_TTL, lambda: self.tmdb.poster(imdb))
        except Exception:  # noqa: BLE001 - el póster de TMDB es un extra: queda el de siempre
            log.info("No pude leer el póster de TMDB de %s", imdb)
            self._posters_down_until = time.monotonic() + 10 * 60
            return None

    def poster_source(self, url: str) -> str:
        """La dirección de donde bajar un póster: si es de metahub, el de TMDB de ese título cuando lo hay (`tmdb_poster`)."""
        found = METAHUB_POSTER.fullmatch(url or "")
        return (self.tmdb_poster(found[1]) if found else None) or url

    def imdb_ratings(self, wanted: list[tuple[str, str]]) -> dict[str, float]:
        """La calificación de IMDb de cada título (de Cinemeta, varios a la vez; se recuerda un día), para ordenar una lista
        «Mejor calificadas en IMDb», como el iPhone. Los que Cinemeta no tiene no salen."""
        def one(pair: tuple[str, str]) -> tuple[str, float | None]:
            kind, imdb = pair

            def load() -> float | None:
                try:
                    raw = self.services.cinemeta.meta(kind, imdb, localized=False).get("imdbRating")
                    return float(raw) if raw not in (None, "") else None
                except Exception:  # noqa: BLE001 - sin calificación no pasa nada
                    return None
            return imdb, self.cache.get(f"imdb:rating:{imdb}", SLOW_TTL, load)

        pairs = [(k if k in ("movie", "series") else "movie", i) for k, i in wanted if isinstance(i, str) and i.startswith("tt")][:120]
        return {imdb: rating for imdb, rating in pools.DETAILS.map(one, pairs, at_most=12) if rating}

    def title_extras(self, kind: str, imdb: str) -> dict:
        """La ficha como el iPhone: frase, clasificación, quién la hizo (TMDB) y «Más como esto» (lo que Trakt relaciona, ya
        con IMDb para abrirlo). Lo que no se pueda (sin clave, sin red) queda vacío; se recuerda (también sin internet)."""
        kind = kind if kind in ("movie", "series") else "movie"
        empty = {"tagline": None, "certification": None, "directors": [], "writers": [], "cast": [], "people": [], "more": [],
                 "release": None, "languages": [], "studios": [], "collection": None, "saga": None}
        if not isinstance(imdb, str) or not re.fullmatch(r"tt[0-9]{1,12}", imdb):
            return empty
        out = dict(empty)
        if self.tmdb.configured:
            def load_tmdb() -> dict:
                tmdb_id = self.tmdb.find_id(imdb, kind)
                return self.tmdb.extras(kind, tmdb_id, self.region) if tmdb_id else {}
            try:
                # extras3: desde el 12 nov se guarda la clasificación cruda (México y EE. UU.), no la ya elegida: al cambiar
                # el idioma de las fichas no se queda la escala de antes (las de extras2 ya no se leen).
                out.update(self.cache.get(f"extras3:{kind}:{imdb}", SLOW_TTL, load_tmdb) or {})
            except Exception:  # noqa: BLE001 - lo de TMDB es un extra: la ficha se ve sin él
                log.info("Ficha: no pude leer los extras de %s", imdb)
            ratings = out.pop("ratings", None) or {}
            if isinstance(ratings, dict):
                out["certification"] = certification.resolve(ratings.get("MX"), ratings.get("US"), kind, self._fichas_language())
            saga = out.get("collection")
            if isinstance(saga, dict) and saga.get("id"):
                # «La saga» (como el iPhone): sus películas en orden, ya con IMDb para abrirlas.
                try:
                    items = self.cache.get(f"saga-parts:{saga['id']}", SLOW_TTL,
                                           lambda: self._tmdb_items(self.tmdb.collection_parts(saga["id"]), "movie", saga["name"], limit=12))
                    if len(items) >= 2:
                        out["saga"] = {"name": saga["name"], "items": items}
                except Exception:  # noqa: BLE001 - la saga es un extra
                    log.info("Ficha: no pude leer la saga %s", saga.get("id"))
        if self.trakt.configured:
            related = self._related({"imdb": imdb, "kind": kind})
            out["more"] = [video_item(e, "Más como esto") for e in related[:15]]
        return out

    def _fichas_language(self) -> str:
        """El idioma de las fichas (Ajustes, o ui.language): decide la escala de la clasificación (design/clasificaciones.json)."""
        localizer = getattr(self.services.watch, "localizer", None)
        try:
            return str((localizer.language() if localizer else None) or "es")
        except Exception:  # noqa: BLE001 - sin ajuste legible, el de fábrica
            return "es"

    def title_letterboxd(self, kind: str, imdb: str) -> dict:
        """Letterboxd en la ficha, como el iPhone: su promedio (0.5–5) y sus reseñas populares (de cualquier película, sin
        cuenta) y, con tu usuario, tu reseña: tus estrellas, el ♥, cuándo la viste y lo que escribiste (de tu diario).
        Las series casi nunca están. Se recuerda tres días (el diario, una hora)."""
        out: dict = {"average": None, "reviews": [], "slug": None, "mine": None}
        if kind != "movie" or not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            return out
        try:
            info = self.cache.get(f"letterboxd:info:{imdb}", 3 * SLOW_TTL, lambda: self.letterboxd.info(imdb) or {})
        except (letterboxd_api.LetterboxdError, *SERVICE_ERRORS):
            info = {}
        out.update({k: info.get(k) for k in ("average", "slug")}, reviews=info.get("reviews") or [])
        if self.letterboxd.configured:
            try:
                diary = self.cache.get("letterboxd:diary", RECS_TTL, self.letterboxd.diary)
                tmdb = self.tmdb.find_id(imdb, "movie") if self.tmdb.configured else None
                mine = next((e for e in diary if (tmdb and e.get("tmdb") == tmdb) or (info.get("slug") and e.get("slug") == info["slug"])), None)
                if mine and (mine.get("rating") or mine.get("review") or mine.get("liked")):
                    out["mine"] = {k: mine.get(k) for k in ("rating", "liked", "rewatch", "watched", "review")}
            except (letterboxd_api.LetterboxdError, *SERVICE_ERRORS):
                log.info("Ficha: no pude leer tu diario de Letterboxd")
        return out

    def title_ratings(self, kind: str, imdb: str) -> dict:
        """Las calificaciones de la ficha, como el iPhone (RatingsRow): IMDb (de Cinemeta), TMDB y Trakt, en 0–10. Las que no
        se pueden saber (sin clave, sin red, sin votos) quedan en None; se recuerdan un día."""
        kind = kind if kind in ("movie", "series") else "movie"
        if not isinstance(imdb, str) or not re.fullmatch(r"tt[0-9]{1,12}", imdb):
            return {"imdb": None, "tmdb": None, "trakt": None}

        def imdb_rating() -> float | None:
            return self.imdb_ratings([(kind, imdb)]).get(imdb)

        def tmdb_rating() -> float | None:
            if not self.tmdb.configured:
                return None
            tmdb_id = self.tmdb.find_id(imdb, kind)
            return self.tmdb.details(kind, tmdb_id).get("rating") if tmdb_id else None

        def trakt_rating() -> float | None:
            return self.trakt.rating(kind, imdb) if self.trakt.configured else None

        def safe(name: str, load: Callable[[], float | None]) -> float | None:
            try:
                return self.cache.get(f"rating:{name}:{imdb}", SLOW_TTL, load)
            except Exception:  # noqa: BLE001 - una calificación que falla no tumba la ficha
                return None

        loads = (("imdb", imdb_rating), ("tmdb", tmdb_rating), ("trakt", trakt_rating))
        found = pools.DETAILS.map(lambda pair: safe(*pair), loads, at_most=3)
        return {name: value for (name, _), value in zip(loads, found, strict=True)}

    def _studio_logos(self) -> dict[str, str]:
        """Los logos de los estudios (TMDB), sin hacer esperar al riel: si aún no están, se piden en segundo plano y mientras
        tanto la tarjeta dice el nombre. Se recuerdan un día."""
        found = self.cache.peek("tmdb:studio-logos")
        if found is None and not self._studio_logos_busy:
            self._studio_logos_busy = True

            def load() -> None:
                try:
                    pairs = pools.DETAILS.map(lambda s: (str(s[0]), self._safe(lambda: self.tmdb.company_logo(s[0]))), tmdb_api.STUDIOS,
                                              at_most=4)
                    self.cache.get("tmdb:studio-logos", SLOW_TTL, lambda: {k: v for k, v in pairs if v})
                finally:
                    self._studio_logos_busy = False
                    self.publish({"type": "studio-logos"})  # Películas y series se pone al día con los logos

            threading.Thread(target=load, daemon=True, name="studio-logos").start()
        return found or {}

    def _warm_logos(self, items: list[dict]) -> None:
        """Baja en segundo plano (uno a la vez) los logos recortados de los primeros títulos de una lista: cuando el héroe
        de la tele los pide ya están en disco (antes una serie nueva tardaba en enseñar su título estilizado)."""
        wanted = [i["meta_id"] for i in items if isinstance(i.get("meta_id"), str) and i["meta_id"].startswith("tt")]
        if wanted:
            self._logo_pool.submit(lambda: [self.trimmed_logo(imdb) for imdb in wanted])

    def _with_art(self, item: dict) -> dict:
        """El póster o fondo que elegiste para ese título («Cambiar el arte»), en lugar del de siempre."""
        name = self.services.names.name(item.get("kind"), item.get("meta_id")) if getattr(self.services, "names", None) else None
        if name and name != item.get("title"):  # el mismo nombre que en la ficha y en Buscar (tu idioma)
            item = {**item, "title": name}
        art = self.services.watch.art_for(item.get("meta_id")) if item.get("meta_id") else {}
        if not art:
            return item
        return {**item, **({"image": art["poster"]} if art.get("poster") else {}),
                **({"hero": art["background"]} if art.get("background") else {})}

    # --- la ficha de una sugerencia ------------------------------------------------------------
    def details(self, key: str, kind: str | None = None) -> dict:
        """Sinopsis en español (si se puede) y si su logo es oscuro (se pinta blanco)."""
        if key.startswith("video:"):
            imdb = key.removeprefix("video:")
            kind = kind if kind in ("movie", "series") else "movie"
            return self.cache.get(f"details:{key}", SLOW_TTL, lambda: self._video_details(imdb, kind))
        if key.startswith("rawg:"):
            rawg_id = int(key.removeprefix("rawg:")) if key.removeprefix("rawg:").isdigit() else 0
            return self.cache.get(f"details:{key}", SLOW_TTL, lambda: self._rawg_details(rawg_id))
        if key.startswith("game:"):
            item = self.services.get(key.removeprefix("game:"))
            appid = item.steam_appid if item else None
            text = self.cache.get(f"steam:{appid}", SLOW_TTL, lambda: rawg_api.steam_description(appid)) if appid else ""
            # Su logo de Steam, si es oscuro, se pinta blanco (Cult of the Lamb: rojo oscuro sobre su arte rojo no se leía).
            dark = self.logo_dark(f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/logo.png") if appid else None
            return {"overview": text, "logo_dark": dark}
        raise KeyError(key)

    def _video_details(self, imdb: str, kind: str) -> dict:
        overview, facts = "", None
        if self.tmdb.configured:
            found = self._safe(lambda: self.tmdb.find(imdb, kind))
            if found:
                overview = found["overview"]
                if kind == "movie" and found.get("runtime"):
                    facts = [["Duración", runtime_text(found["runtime"])], ["Año", str(found["year"] or "")]]
                elif kind == "series" and found.get("seasons"):
                    facts = [["Temporadas", str(found["seasons"])], ["Episodios", str(found.get("episodes") or "")]]
        if not overview:
            try:  # Cinemeta (en inglés): mejor eso que nada
                overview = str(self.services.cinemeta.meta(kind, imdb).get("description") or "").strip()
            except Exception:  # noqa: BLE001 - sin sinopsis no pasa nada
                overview = ""
        return {"overview": overview, "facts": [f for f in facts or [] if f[1]] or None,
                "logo_dark": self.logo_dark(METAHUB.format(kind="logo", imdb=imdb))}

    def _rawg_details(self, rawg_id: int) -> dict:
        appid = self._safe(lambda: self.rawg.steam_appid(rawg_id)) if rawg_id else None
        text = rawg_api.steam_description(appid) if appid else ""
        if not text and rawg_id:
            text = self._safe(lambda: self.rawg.description(rawg_id)) or ""
            text = text[:600].rsplit(" ", 1)[0] + "…" if len(text) > 600 else text
        return {"overview": text}

    def logo_dark(self, url: str) -> bool | None:
        """¿El logo es oscuro (negro sobre transparente)? Sobre el fondo oscuro no se vería: se pinta blanco."""
        if url in self._dark:
            return self._dark[url]
        verdict = None
        try:
            import io
            import urllib.request

            from PIL import Image

            from ..net import read_body

            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Orbital"}), timeout=6) as res:
                raw = read_body(res, timeout=6, limit=4 * 1024 * 1024)
            image = Image.open(io.BytesIO(raw)).convert("RGBA")
            image.thumbnail((96, 96))
            visible = [px[:3] for px in image.getdata() if isinstance(px, tuple) and len(px) == 4 and px[3] > 128]
            if visible:
                lum = sum(.2126 * r + .7152 * g + .0722 * b for r, g, b in visible) / len(visible)
                verdict = lum < 64
        except Exception:  # noqa: BLE001 - sin Pillow, sin logo o sin internet: se deja como venga
            verdict = None
        if len(self._dark) > 2000:
            self._dark.clear()
        self._dark[url] = verdict
        return verdict

    def trimmed_logo(self, imdb: str) -> bytes | None:
        """El logo del título (metahub) ya sin su aire transparente, guardado en disco: la tele lo pide aquí, así el hueco
        entre la etiqueta y el logo es el mismo en todos. None si no hay (o no se pudo bajar: se reintenta en un rato)."""
        from ..library import iptv_logos

        if not re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            return None
        path = self.logo_dir / f"{imdb}.v2.png" if self.logo_dir else None  # v2: los oscuros ya vienen en blanco
        try:
            if path is not None and path.is_file():
                return path.read_bytes()
        except OSError:
            pass
        if imdb in self._logos:
            return self._logos[imdb]
        if time.monotonic() - self._logo_misses.get(imdb, -1e9) < LOGO_RETRY:
            return None
        try:
            png = whiten_if_dark(iptv_logos.trim(iptv_logos.download_logo(METAHUB.format(kind="logo", imdb=imdb))))
        except (iptv_logos.LogoError, *NET_FAILURES) as exc:
            log.debug("Sin logo de %s: %s", imdb, exc)
            if len(self._logo_misses) > 2000:
                self._logo_misses.clear()
            self._logo_misses[imdb] = time.monotonic()
            return None
        if path is not None:
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(path, png, durable=False)
                return png
            except OSError as exc:
                log.info("No pude guardar un logo: %s", exc)
        if len(self._logos) > 300:
            self._logos.clear()
        self._logos[imdb] = png
        return png

    # --- una persona (como el iPhone) -------------------------------------------------------------
    def person(self, person_id: int) -> dict:
        """Foto, biografía y filmografía de alguien del reparto (TMDB). Se recuerda un día."""
        if not self.tmdb.configured:
            raise ValueError("Para ver a esta persona falta la clave de TMDB (Ajustes › Cuentas).")
        return self.cache.get(f"person:{int(person_id)}", SLOW_TTL, lambda: self.tmdb.person(int(person_id)))

    def tmdb_imdb(self, kind: str, tmdb_id: int) -> str | None:
        """El IMDb de un título de TMDB (abrir su ficha desde la filmografía)."""
        kind = kind if kind in ("movie", "series") else "movie"
        return self.cache.get(f"tmdb-imdb:{kind}:{int(tmdb_id)}", SLOW_TTL, lambda: self.tmdb.imdb_of(kind, int(tmdb_id)))

    def sagas(self, imdbs: list[str]) -> list[dict]:
        """Las sagas de tus películas (TMDB), solo las que tienen dos o más tuyas: [{id, name, imdbs}]. Cada película se
        pregunta una vez y se recuerda mucho tiempo (no cambia de saga)."""
        if not self.tmdb.configured:
            return []

        def one(imdb: str):
            try:
                return imdb, self.cache.get(f"saga:{imdb}", 30 * SLOW_TTL, lambda: self.tmdb.collection_of(imdb) or {})
            except SERVICE_ERRORS:
                return imdb, None
        groups: dict[int, dict] = {}
        for imdb, saga in pools.DETAILS.map(one, imdbs[:200], at_most=6):
            if saga and saga.get("id"):
                groups.setdefault(saga["id"], {"id": saga["id"], "name": saga["name"], "imdbs": []})["imdbs"].append(imdb)
        return sorted((g for g in groups.values() if len(g["imdbs"]) >= 2), key=lambda g: g["name"])
