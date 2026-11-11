"""Mi lista, tus listas, favoritos, calificaciones, seguir y ocultar."""

from __future__ import annotations

import re
import time

from .account import _Account
from .base import (
    FAVORITES_FULL,
    FAVORITES_TTL,
    HIDDEN_SECTIONS,
    KINDS,
    PRIVACIES,
    PROGRESS_SHOWS,
    TraktAuthError,
    TraktError,
    TraktFavoritesFull,
    _dict,
    _typed,
    _when,
    entry,
    log,
)


class _Lists(_Account):
    """Mi lista, listas, favoritos, calificaciones y ocultas."""

    def set_watchlist(self, kind: str, imdb: str, add: bool) -> None:
        self._send("POST", "/sync/watchlist" + ("" if add else "/remove"), self._one(kind, imdb), idempotent=True)

    def set_list_item(self, list_id: str, kind: str, imdb: str, add: bool) -> None:
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        self._send("POST", f"/users/me/lists/{list_id}/items" + ("" if add else "/remove"), self._one(kind, imdb), idempotent=True)

    def add_list_items(self, list_id: str, items: list[tuple[str, str]]) -> None:
        """Agrega muchos títulos de una vez a tu lista ([(kind, imdb)]), de cien en cien (Trakt deja un cambio por segundo:
        uno por título tardaba minutos). Agregar dos veces no duplica."""
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        clean = [(k, i) for k, i in items if k in KINDS and re.fullmatch(r"tt[0-9]{1,12}", str(i))]
        for start in range(0, len(clean), 100):
            body: dict[str, list] = {}
            for kind, imdb in clean[start:start + 100]:
                body.setdefault(KINDS[kind], []).append({"ids": {"imdb": imdb}})
            self._send("POST", f"/users/me/lists/{list_id}/items", body, idempotent=True)

    def set_favorite(self, kind: str, imdb: str, add: bool) -> None:
        """Pone o quita un título de tus favoritos de Trakt (el corazón; aparte de la watchlist y de los favoritos de tus
        JUEGOS, que viven en la consola). Con 100 ya no cabe otro: Trakt responde 420 y se dice qué hacer."""
        body = self._one(kind, imdb)
        try:
            self._send("POST", "/sync/favorites" + ("" if add else "/remove"), body, errors={420: TraktFavoritesFull(FAVORITES_FULL)})
        finally:
            self._favorites = None  # la próxima lectura ya trae el cambio (o lo que de verdad quedó)

    def favorites(self, now: float | None = None) -> list[dict]:
        """Tus favoritos de Trakt (películas y series juntas, lo último que marcaste primero). Se guardan FAVORITES_TTL
        segundos; pasado ese rato se pregunta primero a /sync/last_activities si cambiaron y solo entonces se bajan."""
        now = time.time() if now is None else now
        cached = self._favorites
        if cached is not None:
            when, stamp, items = cached
            if now - when < FAVORITES_TTL:
                return items
            if stamp and self._favorites_stamp() == stamp:
                self._favorites = (now, stamp, items)  # no cambiaron: otro rato con los mismos
                return items
        stamp = self._favorites_stamp()
        rows = []
        for kind in ("movies", "shows"):
            got = self._all_pages(f"/sync/favorites/{kind}", extended="full")
            rows += [r for r in got if isinstance(r, dict)] if isinstance(got, list) else []
        items = _typed(sorted(rows, key=lambda r: str(r.get("listed_at") or ""), reverse=True))
        self._favorites = (now, stamp, items)
        return items

    def _favorites_stamp(self) -> str | None:
        """Cuándo cambiaron tus favoritos en Trakt (desde cualquier app): `favorites.updated_at`. None si no se sabe."""
        try:
            data = self._get("/sync/last_activities")
        except TraktAuthError:
            raise
        except TraktError:
            return None
        stamp = _dict(_dict(data).get("favorites")).get("updated_at")
        return stamp if isinstance(stamp, str) and stamp else None

    # --- listas ------------------------------------------------------------------------------
    def username(self) -> str:
        data = self._get("/users/settings")
        user = data.get("user") if isinstance(data, dict) else None
        name = user.get("name") or user.get("username") if isinstance(user, dict) else None
        return str(name or "")

    def recommendations(self, kind: str, limit: int = 30) -> list[dict]:
        rows = self._get(f"/recommendations/{KINDS[kind]}", limit=limit, ignore_collected="true",
                         ignore_watchlisted="true", extended="full")
        return [e for e in (entry(r, kind) for r in rows or []) if e] if isinstance(rows, list) else []

    def watchlist(self) -> list[dict]:
        rows = self._all_pages("/sync/watchlist", extended="full", sort_by="added", sort_how="desc")
        if isinstance(rows, list):
            rows = sorted((r for r in rows if isinstance(r, dict)), key=lambda r: str(r.get("listed_at") or ""), reverse=True)
        return _typed(rows)

    def lists(self) -> list[dict]:
        rows = self._get("/users/me/lists")
        found = []
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            ids = row.get("ids") if isinstance(row.get("ids"), dict) else {}
            name, trakt_id = row.get("name"), ids.get("trakt")
            if isinstance(name, str) and name.strip() and trakt_id:
                count = row.get("item_count")
                found.append({"id": str(trakt_id), "name": name.strip(),
                              "privacy": row.get("privacy") if row.get("privacy") in PRIVACIES else "private",
                              "count": count if isinstance(count, int) else None})
        return found

    # --- tus listas completas (G4-A, 10 nov 2026, como `Trakt+Lists.swift`): todo necesita conexión ---------------------
    def update_list(self, list_id: str, name: str | None = None, privacy: str | None = None) -> None:
        """Cambia el nombre o quién la ve de una de tus listas."""
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        body: dict[str, str] = {}
        if name is not None:
            clean = name.strip()
            if not clean:
                raise TraktError("Ponle nombre a la lista")
            body["name"] = clean[:100]
        if privacy is not None:
            if privacy not in PRIVACIES:
                raise TraktError("Privacidad inválida")
            body["privacy"] = privacy
        if body:
            self._send("PUT", f"/users/me/lists/{list_id}", body)

    def delete_list(self, list_id: str) -> None:
        """Borra una de tus listas (no se deshace; los títulos siguen en Mi lista y en tus otras listas)."""
        if not str(list_id).isdigit():
            raise TraktError("Lista inválida")
        self._send("DELETE", f"/users/me/lists/{list_id}")

    def list_rows(self, list_id: str) -> list[tuple[int, str]]:
        """Cada título de una lista (o de tu watchlist, con «watchlist») con el id de su renglón: lo que pide ordenar a mano."""
        if list_id == "watchlist":
            path = "/sync/watchlist"
        elif str(list_id).isdigit():
            path = f"/users/me/lists/{list_id}/items"
        else:
            raise TraktError("Lista inválida")
        found = []
        for row in self._all_pages(path):
            item = _dict(row).get("movie") or _dict(row).get("show")
            imdb = _dict(_dict(item).get("ids")).get("imdb")
            if isinstance(_dict(row).get("id"), int) and isinstance(imdb, str):
                found.append((row["id"], imdb))
        return found

    def reorder(self, list_id: str, imdbs: list[str]) -> None:
        """Ordena a mano una lista (o tu watchlist) en el orden de `imdbs`; lo que no venga se queda al final, como estaba."""
        rows = self.list_rows(list_id)
        by_imdb: dict[str, int] = {}
        for row_id, imdb in rows:
            by_imdb.setdefault(imdb, row_id)
        rank = [by_imdb[i] for i in imdbs if i in by_imdb]
        placed = set(rank)
        rank += [r for r, _ in rows if r not in placed]
        if not rank:
            return
        path = "/sync/watchlist/reorder" if list_id == "watchlist" else f"/users/me/lists/{list_id}/items/reorder"
        self._send("POST", path, {"rank": rank})

    def set_items(self, target: str, items: list[tuple[str, str]], add: bool) -> None:
        """Pone o quita varios títulos ([(kind, imdb)]) de tu watchlist («watchlist») o de una de tus listas, de cien en cien:
        un envío por lista (elegir varios, G3-A)."""
        if target != "watchlist" and not str(target).isdigit():
            raise TraktError("Lista inválida")
        clean = [(k, i) for k, i in items if k in KINDS and re.fullmatch(r"tt[0-9]{1,12}", str(i))]
        base = "/sync/watchlist" if target == "watchlist" else f"/users/me/lists/{target}/items"
        for start in range(0, len(clean), 100):
            body: dict[str, list] = {}
            for kind, imdb in clean[start:start + 100]:
                body.setdefault(KINDS[kind], []).append({"ids": {"imdb": imdb}})
            self._send("POST", base + ("" if add else "/remove"), body, idempotent=True)

    def duplicate_list(self, list_id: str, name: str) -> str:
        """«Duplicar»: una lista nueva, Solo tú, con los mismos títulos en el mismo orden. Su id."""
        items = self.list_items(list_id)
        made = self.create_list(name)
        if items:
            self.set_items(made, [(e["kind"], e["imdb"]) for e in items], True)
            try:
                self.reorder(made, [e["imdb"] for e in items])
            except TraktError as exc:  # el orden es lo de menos: los títulos ya están
                log.info("Trakt: no pude ordenar la copia: %s", exc)
        return made

    def watched_state(self) -> dict:
        """Lo que viste según Trakt para el tablero de Guardado (G2-A, como `watchedState` del iPhone): cada película y cada
        serie con su nombre, su año y la última vez que la viste; las series con cuánto llevas (0 a 1 de lo que ha salido) y si
        siguen saliendo."""
        def rows(data) -> list[dict]:
            return [_dict(r) for r in data] if isinstance(data, list) else []

        movies: dict[str, dict] = {}
        for row in rows(self._get("/sync/watched/movies")):
            item = entry(row.get("movie"), "movie")
            if item:
                movies[item["imdb"]] = {**item, "last": _when(row.get("last_watched_at"))}
        shows: dict[str, dict] = {}
        for row in rows(self._get("/sync/watched/shows", extended="full")):
            raw = _dict(row.get("show"))
            item = entry(raw, "series")
            if not item:
                continue
            aired = raw.get("aired_episodes")
            # Trakt ya no manda las temporadas aquí (10 nov 2026: llegan sin «seasons»): de entrada, las veces que viste
            # episodios entre los que han salido (una repetida cuenta de más); las más recientes se corrigen abajo.
            plays: int = row["plays"] if isinstance(row.get("plays"), int) else 0
            seen = sum(len(_dict(s).get("episodes") or []) for s in row.get("seasons") or [] if (_dict(s).get("number") or 0) > 0) or plays
            fraction = min(1.0, seen / aired) if isinstance(aired, int) and aired > 0 else 1.0
            shows[item["imdb"]] = {**item, "last": _when(row.get("last_watched_at")), "fraction": fraction,
                                   "airing": raw.get("status") in ("returning series", "in production")}
        # Las que viste más recientemente, con su avance exacto (vistos entre los que han salido, sin especiales).
        recent = sorted(shows, key=lambda i: -(shows[i]["last"] or 0))[:PROGRESS_SHOWS]

        def exact(imdb: str) -> tuple[str, float | None]:
            try:
                data = _dict(self._get(f"/shows/{imdb}/progress/watched", hidden="false", specials="false"))
            except TraktAuthError:
                raise
            except TraktError:  # una que falla se queda con la cuenta de arriba
                return imdb, None
            aired, completed = data.get("aired"), data.get("completed")
            if isinstance(aired, int) and aired > 0 and isinstance(completed, int):
                return imdb, min(1.0, completed / aired)
            return imdb, None

        from concurrent.futures import ThreadPoolExecutor

        with ThreadPoolExecutor(max_workers=4, thread_name_prefix="trakt-avance") as pool:
            for imdb, fraction in pool.map(exact, recent):
                if fraction is not None:
                    shows[imdb]["fraction"] = fraction
        return {"movies": movies, "shows": shows}

    def create_list(self, name: str) -> str:
        """Una lista privada nueva en tu cuenta; su id."""
        data = self._send("POST", "/users/me/lists", {"name": name, "privacy": "private"})
        trakt_id = (data or {}).get("ids", {}).get("trakt") if isinstance(data, dict) else None
        if not trakt_id:
            raise TraktError("Trakt no creó la lista")
        return str(trakt_id)

    def named_list(self, name: str, create: bool = False) -> str | None:
        """El id de tu lista con ese nombre (sin importar mayúsculas ni acentos), como el iPhone la busca: «Tu match
        perfecto», «Tus canales». `create`: si no existe, se crea."""
        import unicodedata

        def fold(text: str) -> str:
            return "".join(c for c in unicodedata.normalize("NFD", text.casefold()) if unicodedata.category(c) != "Mn")

        found = next((row["id"] for row in self.lists() if fold(row["name"]) == fold(name)), None)
        return found or (self.create_list(name) if create else None)

    def set_rating(self, kind: str, imdb: str, rating: int | None) -> None:
        """Tu calificación (1–10, como la guarda Trakt; las estrellas del iPhone van de 1 a 5 y cuentan doble). None la quita."""
        body = self._one(kind, imdb)
        if rating is None:
            self._send("POST", "/sync/ratings/remove", body)
            return
        if not 1 <= int(rating) <= 10:
            raise TraktError("Calificación inválida")
        body[KINDS[kind]][0]["rating"] = int(rating)
        self._send("POST", "/sync/ratings", body)

    def set_following(self, imdb: str, following: bool) -> None:
        """Dejar de seguir una serie (o volver a seguirla), como el iPhone: Trakt la oculta de tu calendario y de tu progreso,
        así que no sale en tus estrenos. Lo que viste no se toca."""
        self.set_hidden([imdb], not following)

    def set_hidden(self, imdbs: list[str], hidden: bool, sections: tuple[str, ...] = HIDDEN_SECTIONS) -> None:
        """Esconde varias series en esas secciones de Trakt (o las vuelve a mostrar), un envío por sección (como
        `Trakt.setHidden` del iPhone). «dejadas» es extra: si Trakt no la acepta (y no es que esté ocupado o caído), lo
        demás ya quedó."""
        valid = [i for i in imdbs if re.fullmatch(r"tt[0-9]{1,12}", i or "")]
        if not valid:
            raise TraktError("Título inválido")
        body = {"shows": [{"ids": {"imdb": i}} for i in valid]}
        for section in sections:
            try:
                self._send("POST", f"/users/hidden/{section}{'' if hidden else '/remove'}", body, idempotent=True)
            except TraktAuthError:
                raise
            except TraktError as exc:
                if section == "dropped" and exc.status is not None and exc.status != 429 and exc.status < 500:
                    continue
                raise
