"""Consultar la biblioteca: elementos, filas de la interfaz, preferencias, búsqueda por nombre y «Tu consola»."""

from __future__ import annotations

import time

from .. import player
from ..library import (
    emulators,
)
from ..library.identity import runner_keys
from ..library.models import LibraryItem
from ..text import normalize
from .base import CATEGORIES, CONTINUE_LIMIT, JUMP_LIMIT, NEW_FOR, _Base, log, tone_path
from .match import title_match


class _Query(_Base):
    def stremio_library(self) -> list[LibraryItem]:
        return [i for i in self.items() if i.source == "stremio"]

    # --- consulta ------------------------------------------------------------
    def items(self, include_hidden: bool = False) -> list[LibraryItem]:
        items = self.store.all()
        if include_hidden:
            return items
        return [i for i in items if not self.state.prefs(i.id).get("hidden")]

    def get(self, item_id: str) -> LibraryItem | None:
        return self.store.get(item_id)

    def is_favorite(self, item: LibraryItem) -> bool:
        # La preferencia de Orbital manda sobre el favorito de ES-DE.
        return self.state.prefs(item.id).get("favorite", item.favorite)

    def runner_for(self, item: LibraryItem, runner_id: str | None = None):
        if runner_id:
            return item.runner(runner_id)
        for key in runner_keys(item):
            chosen = self.state.prefs(key).get("runner")
            if chosen:
                return item.runner(chosen)
        return item.runner()

    def _migrate_runner_prefs(self, items: list[LibraryItem]) -> None:
        """Las elecciones de emulador guardadas por ruta pasan a la clave estable (sin borrar las viejas)."""
        n = self.state.migrate_runner_prefs([(i.id, runner_keys(i)) for i in items])
        if n:
            log.info("Emulador elegido: %d preferencias copiadas a una clave que sobrevive a renombrar", n)

    def describe(self, item: LibraryItem) -> dict:
        data = item.public()
        data["favorite"] = self.is_favorite(item)
        if item.runners:
            data["runner"] = self.runner_for(item).id
        history = self.state.history(item.id)
        # En Stremio manda su propia fecha (abrir la ficha no significa haberlo visto).
        data["last_played"] = item.last_watched if item.source == "stremio" else self.last_played(item)
        # Steam lleva sus propias horas (también lo jugado fuera de Orbital): la mayor de las dos.
        data["playtime"] = max(history.get("playtime", 0), item.extra.get("steam_playtime", 0))
        # Recién llegado (en los últimos 7 días): la consola lo anuncia en Inicio.
        seen = self.state.first_seen(item.id)
        if seen and time.time() - seen < NEW_FOR:
            data["new"] = True
        # Cuándo llegó (filtro «Añadidos»): lo que vio Orbital o, para lo que ya tenías, la fecha del archivo.
        data["added"] = seen or item.extra.get("added") or None
        # Una película o serie: su nombre en tu idioma (Stremio guarda el original en inglés).
        if item.source == "stremio" and item.extra.get("meta_id"):
            data["title"] = self.names.name(item.extra.get("kind"), item.extra["meta_id"]) or data["title"]
        # V3: el tono de su fondo, si ya se midió (si no, el cliente lo saca él mismo, como antes).
        if self.tones is not None and (tone := self.tones.peek(tone_path(item))):
            data["art_tone"] = tone
        return data

    def last_played(self, item: LibraryItem) -> float | None:
        """La última vez que se jugó: lo que registró Orbital o, en Steam, lo que registró Steam."""
        last = max(self.state.history(item.id).get("last_played") or 0, item.extra.get("steam_last_played") or 0)
        return last or None

    def grouped(self) -> list[dict]:
        items = self.items()
        by_id = {i.id: i for i in items}
        alpha = sorted(items, key=lambda i: i.title.lower())
        rows = []
        running = self.launcher.status()
        running_id = running["id"] if running else None
        for cat in CATEGORIES:
            if cat["id"] == "jump":
                games = [(self.last_played(i) or 0, i) for i in items if i.source not in ("stremio", "cinemeta")]
                videos = [(i.last_watched or 0, i) for i in items if i.category == "continue"]
                recent = sorted((p for p in games + videos if p[0]), key=lambda p: p[0], reverse=True)
                members = [i for _, i in recent][:JUMP_LIMIT]
                if running_id and running_id in by_id:  # lo abierto va primero (Home o A para volver)
                    members = [by_id[running_id], *[i for i in members if i.id != running_id]][:JUMP_LIMIT]
                if members:
                    rows.append({**cat, "items": [{**self.describe(i), **({"live": True} if i.id == running_id else {})}
                                                  for i in members]})
                continue
            if cat["id"] == "recent":
                # Juegos y apps (también lo jugado en Steam fuera de Orbital); lo que se ve va en
                # "Seguir viendo".
                played = sorted(((self.last_played(i) or 0, i.id, i) for i in items
                                 if i.source not in ("stremio", "cinemeta")), reverse=True)
                members = [i for last, _, i in played if last][:15]
            elif cat["id"] == "continue":
                # Stremio guarda todo lo que alguna vez empezaste (años): lo reciente, no 134 títulos.
                members = sorted((i for i in items if i.category == "continue"),
                                 key=lambda i: i.last_watched or 0, reverse=True)[:CONTINUE_LIMIT]
            elif cat["id"] == "mylist":  # tu watchlist de Trakt (o, sin Trakt, tu biblioteca de Stremio), lo último primero
                members = sorted((i for i in items if i.source == "stremio" and i.extra.get("in_library")),
                                 key=lambda i: i.extra.get("listed_at") or i.last_watched or 0, reverse=True)
            elif cat["id"] == "favorites":
                members = [i for i in alpha if self.is_favorite(i)]
            elif cat["id"] == "emulators":
                # Una fila por sistema, en el orden de config.yaml. Un emulador instalado sin juegos también sale (vacía,
                # con dónde ponerlos): si no, parecía que Orbital no lo había reconocido (RPCS3 recién instalado).
                with_games: set[str] = set()
                empty: list[dict] = []
                for emu in self.emulators:
                    games = [i for i in items if i.category == "emulators" and i.source == emu.id]
                    if games:
                        with_games.add(emu.system or emu.id)
                        row_id = f"emulators:{emu.id}"
                        rows.append({"id": row_id, "title": emu.name, "items": [self.describe(i) for i in games],
                                     "opened": self.state.opened(row_id)})
                    elif emu.system and emulators.executable_found(emu):
                        folder = emulators.rom_dirs(emu, self.esde)
                        empty.append({"id": f"emulators:{emu.id}", "title": emu.name, "items": [], "empty": True,
                                      "system": emu.system, "folder": str(folder[0]) if folder else None})
                seen_empty: set[str] = set()
                for row in empty:  # uno por sistema y solo si ese sistema no tiene juegos con otro emulador
                    if row["system"] not in with_games and row["system"] not in seen_empty:
                        seen_empty.add(row["system"])
                        rows.append(row)
                continue
            else:
                members = [i for i in items if i.category == cat["id"]]
            if members:
                rows.append({**cat, "items": [self.describe(i) for i in members], "opened": self.state.opened(cat["id"])})
        return rows

    def grouped_items(self, row_id: str) -> list[LibraryItem]:
        """Elementos de una fila, en el mismo orden que la interfaz."""
        row = next((r for r in self.grouped() if r["id"] == row_id), None)
        found = (self.get(i["id"]) for i in row["items"]) if row else ()
        return [i for i in found if i is not None]

    def hidden_count(self) -> int:
        return sum(1 for i in self.items(include_hidden=True) if self.state.prefs(i.id).get("hidden"))

    def find(self, query: str, category: str | None = None, *, source: str | None = None,
             exclude_source: str | tuple[str, ...] | None = None) -> LibraryItem | None:
        """Búsqueda difusa por título, pensada para lo que transcribe Alexa."""
        target = normalize(query)
        if not target:
            return None
        candidates = [i for i in self.items()
                      if (category is None or i.category == category)
                      and (source is None or i.source == source)
                      and (exclude_source is None or i.source not in
                           ((exclude_source,) if isinstance(exclude_source, str) else exclude_source))]
        by_name = {normalize(i.title): i for i in candidates}
        if target in by_name:
            return by_name[target]
        return title_match(target, by_name)

    # --- preferencias --------------------------------------------------------
    def set_prefs(self, item_id: str, *, favorite: bool | None = None, hidden: bool | None = None,
                  runner: str | None = None, clear_runner: bool = False) -> dict:
        item = self.get(item_id)
        if item is None:
            raise KeyError(item_id)
        if favorite is not None:
            self.state.set_pref(item_id, "favorite", favorite)
        if hidden is not None:
            self.state.set_pref(item_id, "hidden", True if hidden else None)
        keys = runner_keys(item)
        if runner is not None:
            if runner not in {r.id for r in item.runners}:
                raise ValueError(f"{item.title} no tiene el emulador {runner}")
            self.state.set_pref_on(keys, "runner", None if runner == item.default_runner else runner)
        if clear_runner:
            self.state.set_pref_on(keys, "runner", None)
        return self.describe(item)

    def setup_status(self) -> dict:
        """Qué encontró Orbital (para "Tu consola", la pantalla de primer uso)."""
        items = self.items()
        games = [i for i in items if i.source not in ("stremio", "cinemeta", "search") and i.category not in ("apps", "media")]
        systems: dict[str, int] = {}
        for i in items:
            if i.category == "emulators":
                emu = next((e for e in self.emulators if e.id == i.source), None)
                systems[emu.name if emu else i.source] = systems.get(emu.name if emu else i.source, 0) + 1
        return {
            "games": len(games),
            "steam": sum(1 for i in items if i.source == "steam") if self.steam_root else None,
            "emulators": systems,
            "esde": self.esde is not None,
            "stremio": self.stremio_linked,
            # Películas y series sin Stremio (corte S4): Real-Debrid y tus complementos.
            "realdebrid": bool(self.watch.rd_token()),
            "addons": sum(1 for e in self.watch.addon_list.entries() if e.on() and e.address),
            "trakt": self.foryou.status()["trakt"],
            "player": player.find_mpv() is not None,
            "alexa": bool(self.config.server.token) and not self.config.server.token_is_ephemeral,
        }
