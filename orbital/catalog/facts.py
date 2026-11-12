"""Los datos de la tienda de Steam y de Wikipedia que se ponen en cada juego, y las horas de Steam."""

from __future__ import annotations

import threading

from ..library import (
    steam,
)
from ..library.models import LibraryItem
from .query import _Query


class _Facts(_Query):
    STORE_SOURCES = ("steam", "geforcenow")

    def _store_facts(self, item: LibraryItem) -> None:
        """Descripción, año, géneros y desarrollador de la tienda de Steam (sin pisar lo que el juego ya trae)."""
        if item.source in self.STORE_SOURCES and item.steam_appid:
            for key, value in self.steam_store.cached(item.steam_appid).items():
                item.extra.setdefault(key, value)
        elif item.source == "geforcenow" and item.category == "geforcenow":  # no está en Steam: Wikidata/Wikipedia
            for key, value in self.wiki_games.cached(item.title).items():
                item.extra.setdefault(key, value)

    def warm_store(self, stop: threading.Event | None = None) -> None:
        """Pide a la tienda de Steam las fichas que faltan (los jugados hace poco primero), en segundo plano, y las
        pone en la biblioteca sin reescanearla."""
        games = [i for i in self.store.all() if i.source in self.STORE_SOURCES and i.steam_appid]
        games.sort(key=lambda i: self.last_played(i) or 0, reverse=True)
        unknown = [int(a) for a in self._steam_owned if not self.steam_store.known(a)]  # para saber nombre y si es juego
        no_steam = [i.title for i in self.store.all() if i.category == "geforcenow" and not i.steam_appid]
        wiki = self.wiki_games.warm(no_steam, stop=stop)
        if not self.steam_store.warm([i.steam_appid for i in games if i.steam_appid] + unknown, limit=400, stop=stop):
            if wiki:
                self.store.update(self._store_facts, where=lambda i: i.source in self.STORE_SOURCES)
                self.notify({"type": "library-changed"})
            return
        if any(self.steam_store.known(a) for a in unknown):
            self.refresh()  # llegaron nombres de juegos sin instalar: entran a la biblioteca
        else:
            self.store.update(self._store_facts, where=lambda i: i.source in self.STORE_SOURCES)
        self.notify({"type": "library-changed"})

    def refresh_steam_stats(self) -> None:
        """Relee las horas y la última vez de Steam (barato: no reescanea la biblioteca)."""
        if self.steam_root is None:
            return
        stats = steam.user_stats(self.steam_root)

        def apply(item: LibraryItem) -> None:
            got = stats.get(str(item.steam_appid), {})
            item.extra["steam_last_played"] = got.get("last_played", 0)
            item.extra["steam_playtime"] = got.get("playtime", 0)
        self.store.update(apply, where=lambda i: i.source == "steam" and i.steam_appid is not None)
        self.notify({"type": "library-changed"})
