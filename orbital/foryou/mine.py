"""Lo tuyo en Trakt: guardar, calificar, seguir, marcar vistas y conectar tu cuenta.
"""

from __future__ import annotations

import logging
import re
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

from ..library import trakt as trakt_api
from .base import MINE_TTL, SERVICE_ERRORS, _Base

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


class _Mine(_Base):
    """Lo tuyo en Trakt: guardar, calificar, seguir, marcar vistas y conectar tu cuenta."""

    def saved_in(self, kind: str, imdb: str) -> dict:
        """«Guardar en…» (como el iPhone): si el título está en tu watchlist, en tus favoritos y en cuáles de tus listas de
        Trakt. Se pregunta a Trakt al momento (no a lo guardado en caché): lo que cambiaste en el iPhone ya cuenta (los
        favoritos, con su minuto y la marca de last_activities)."""
        t = self.trakt
        if not t.linked or not imdb.startswith("tt"):
            return {"trakt": False, "watchlist": False, "favorite": False, "lists": []}
        lists = t.lists()

        def members(list_id: str) -> list[dict] | None:
            try:
                return t.list_items(list_id)
            except SERVICE_ERRORS:  # una lista que no responde no tumba las demás
                return None

        with ThreadPoolExecutor(max_workers=6) as pool:
            watch = pool.submit(t.watchlist)
            favs = pool.submit(t.favorites)
            found = [pool.submit(members, row["id"]) for row in lists]
            in_watch = any(e["imdb"] == imdb for e in watch.result())
            in_favs = any(e["imdb"] == imdb for e in favs.result())
            out = [{"id": row["id"], "name": row["name"], "contains": any(e["imdb"] == imdb for e in f.result() or [])}
                   for row, f in zip(lists, found, strict=True) if f.result() is not None]
        return {"trakt": True, "watchlist": in_watch, "favorite": in_favs, "lists": out}

    def save_to(self, kind: str, imdb: str, where: str, add: bool) -> None:
        """Añadir o quitar de tu watchlist («watchlist»), de tus favoritos de Trakt («favorites») o de una de tus listas
        («list:123»). Las filas de esa lista se vuelven a pedir (en la TV y en Para ti)."""
        if where == "watchlist":
            self.trakt.set_watchlist(kind, imdb, add)
            self.cache.clear("trakt:watchlist")
            library = getattr(getattr(self.services, "watch", None), "trakt_library", None)
            if library is not None:
                library.note_watchlist(kind, imdb, add)
        elif where == "favorites":
            self.trakt.set_favorite(kind, imdb, add)  # Trakt ya olvida lo que tenía guardado de tus favoritos
        elif where.startswith("list:") and where[5:].isdigit():
            self.trakt.set_list_item(where[5:], kind, imdb, add)
            self.cache.clear(f"trakt:list:{where[5:]}")
        else:
            raise ValueError("¿Guardar dónde?")

    # --- lo tuyo con un título (olas 2 y 3 de «Una sola Orbital», como el iPhone) --------------------------------------
    MATCH_LIST = "Tu match perfecto"  # donde caen las que guardas en «¿Qué vemos hoy?» (MatchDeckModel.matchListName)

    def save_match(self, kind: str, imdb: str, add: bool) -> str:
        """«Guardar» en «¿Qué vemos hoy?»: con Trakt, en tu lista «Tu match perfecto» (se crea la primera vez); devuelve
        «match». Sin Trakt, «none»: la interfaz lo guarda en Mi lista (tu biblioteca de Stremio)."""
        if not self.trakt.linked:
            return "none"
        list_id = self.trakt.named_list(self.MATCH_LIST, create=True)
        if not list_id:
            raise trakt_api.TraktError("Trakt no creó «Tu match perfecto»")
        self.trakt.set_list_item(list_id, kind, imdb, add)
        self.cache.clear(f"trakt:list:{list_id}")
        self.cache.clear("trakt:lists")
        return "match"

    def my_rating(self, kind: str, imdb: str) -> int | None:
        """Tus estrellas (1–5) de un título en Trakt, o None."""
        if not self.trakt.linked:
            return None
        rating = self.trakt.my_rating(kind, imdb)
        return max(1, min(5, round(rating / 2))) if isinstance(rating, (int, float)) and rating else None

    def rate(self, kind: str, imdb: str, stars: int | None) -> None:
        """Califica con estrellas (1–5, como el iPhone; en Trakt cuentan doble). None quita la calificación."""
        if not self.trakt.linked:
            raise trakt_api.TraktAuthError("Conecta Trakt en Ajustes › Cuentas para calificar.")
        self.trakt.set_rating(kind, imdb, None if stars is None else max(1, min(5, int(stars))) * 2)

    def unfollowed(self) -> set[str]:
        """Las series que dejaste de seguir desde aquí (se recuerdan al momento; Trakt también las oculta) y las que
        escondiste en Trakt desde el iPhone (SS1-A): ninguna sale en el calendario ni en Lo nuevo de lo tuyo."""
        local = set(self.services.state.settings().get("unfollowed_shows") or [])
        library = getattr(getattr(self.services, "watch", None), "trakt_library", None)
        return local | set(getattr(library, "hidden", None) or ())

    def set_following(self, imdb: str, following: bool) -> None:
        """Seguir o dejar de seguir una serie (la campana de la ficha, como el iPhone): la que dejas ya no sale en tus estrenos
        («A continuación», Lo nuevo de lo tuyo, el calendario). Se guarda aquí al momento y en Trakt."""
        if not self.trakt.linked:
            raise trakt_api.TraktAuthError("Conecta Trakt en Ajustes › Cuentas para seguir o dejar de seguir una serie.")
        self.trakt.set_following(imdb, following)
        library = getattr(getattr(self.services, "watch", None), "trakt_library", None)
        if library is not None:  # lo escondido en Trakt se vuelve a leer (SS1-A); volver a seguirla la saca de ahí
            library.forget("hidden")
            if following:
                library.hidden.discard(imdb)
        local = set(self.services.state.settings().get("unfollowed_shows") or [])
        gone = local - {imdb} if following else local | {imdb}
        self.services.state.set_setting("unfollowed_shows", sorted(gone) or None)
        self.cache.clear("trakt:calendar")
        self.publish({"type": "foryou-changed"})

    def mark_watched(self, kind: str, imdb: str, video_id: str | None, when: str | float) -> None:
        """«¿Cuándo la viste?»: marca vista una película, un episodio o, sin episodio, la serie completa. `when`: «now»,
        «released» (el día que salió), «unknown» (no sabes cuándo) o un momento (segundos)."""
        if not self.trakt.linked:
            raise trakt_api.TraktAuthError("Conecta Trakt en Ajustes › Cuentas para marcar lo que viste.")
        target = trakt_api.scrobble_target(kind, imdb, video_id) or ({"show": {"ids": {"imdb": imdb}}} if kind == "series" else None)
        if target is None:
            raise ValueError("Título inválido")
        moment: str | float = time.time() if when == "now" else when if when in ("released", "unknown") else float(when)
        self.trakt.add_history(target, moment)  # sin episodio: la serie completa
        self.cache.clear("trakt:watched")
        self.cache.clear("trakt:watched-state")  # el avance de tus series (Guardado) también cambió

    def watched_ids(self) -> list[str]:
        """Lo que ya viste en Trakt (sin Trakt, nada): «Ocultar lo que ya vi»."""
        if not self.trakt.linked:
            return []
        try:
            return self.cache.get("trakt:watched", MINE_TTL, self.trakt.watched_ids)
        except SERVICE_ERRORS as exc:
            log.info("Para ti: no pude leer lo que ya viste: %s", exc)
            return []

    def skip_today(self, imdb: str) -> None:
        """«Hoy no»: esa no vuelve a proponerse en 24 horas."""
        if re.fullmatch(r"tt[0-9]{1,12}", imdb or ""):
            self.services.state.skip_today(imdb)

    # --- «No me interesa» ----------------------------------------------------------------------
    def dismiss(self, key: str) -> None:
        if not re.fullmatch(r"(video:tt[0-9]+|rawg:[0-9]+|game:.{1,300})", key or ""):
            raise ValueError("Sugerencia inválida")
        self.services.state.dismiss(key)

    # --- conectar Trakt ------------------------------------------------------------------------
    def start_link(self) -> dict:
        """Pide un código a Trakt y espera (en segundo plano) a que lo confirmes en trakt.tv/activate."""
        if not self.trakt.configured:
            raise ValueError("Falta la aplicación de Trakt: agrega su Client ID en Ajustes › Cuentas.")
        # Dos pedidos seguidos (Y dos veces) o cancelar mientras llega: solo cuenta el último. Antes se
        # quedaba el que terminara al final, y la pantalla podía mostrar un código que nadie esperaba.
        with self._link_lock:
            self._link_gen = gen = self._link_gen + 1
        code = self.trakt.device_code()
        with self._link_lock:
            if self._link_gen != gen:
                return code.public()
            self._link = code
        threading.Thread(target=self._wait_link, args=(code,), daemon=True, name="trakt-link").start()
        return code.public()

    def cancel_link(self) -> None:
        with self._link_lock:
            self._link_gen = self._link_gen + 1
            self._link = None

    def _wait_link(self, code: trakt_api.DeviceCode, sleep: Callable[[float], None] = time.sleep) -> str:
        interval = max(1.0, code.interval)
        while time.time() < code.expires_at:
            sleep(interval)
            with self._link_lock:
                if self._link is not code:  # cancelaste (B) o pediste otro código
                    return "cancelled"
            try:
                result = self.trakt.poll_device(code)
            except (trakt_api.TraktError, ValueError, TypeError, KeyError):
                continue  # la red parpadeó (o Trakt respondió algo raro): se sigue esperando
            if result == "slow":
                interval += 5
            elif result == "linked":
                with self._link_lock:
                    self._link = None
                self.cache.clear()
                name = self._safe(self.trakt.username) or ""
                self.publish({"type": "trakt-linked", "name": name})
                self.publish({"type": "foryou-changed"})
                return result
            elif result != "pending":
                break
        with self._link_lock:
            if self._link is code:
                self._link = None
        self.publish({"type": "trakt-link-failed", "message": "El código caducó. Pide otro para conectar Trakt."})
        return "expired"

    def unlink(self) -> None:
        self.trakt.unlink()
        self.cache.clear("trakt:")
        self.publish({"type": "foryou-changed"})
