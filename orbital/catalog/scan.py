"""Escanear las fuentes (Steam, ES-DE, emuladores, Stremio…), guardar la última biblioteca y vigilar carpetas."""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from urllib.parse import quote

from ..atomic import atomic_write
from ..config import expand
from ..library import (
    detect,
    emulators,
    esde,
    geforcenow,
    steam,
    stremio,
)
from ..library.media import low_res, placeholder
from ..library.models import LibraryItem
from ..library_watch import NAMES_ONLY, LibraryWatcher
from .art import _Art
from .base import art_version, log


class _Scan(_Art):
    # --- escaneo -------------------------------------------------------------
    def _esde_emulators(self) -> list:
        """Los sistemas que tienes en ES-DE y Orbital no conoce por su cuenta (Nintendo 64, SNES…), con los emuladores
        que ES-DE sabe usar (ver library/esde_systems.py)."""
        if not self.esde or not self.esde.executable:
            return []
        from ..library import esde_systems

        covered = {e.system for e in self.emulators if e.system}
        try:
            preferred = {s: e for s in os.listdir(self.esde.home / "gamelists")
                         if (e := self.esde.gamelist(s).system_emulator)} if (self.esde.home / "gamelists").is_dir() else {}
            return esde_systems.configs(self.esde.executable.parent, self.esde.home / "custom_systems", self.esde.rom_root,
                                        covered, preferred)
        except Exception:  # noqa: BLE001 - las reglas de ES-DE nunca dejan a Orbital sin biblioteca
            log.exception("No pude leer los sistemas de ES-DE")
            return []

    def refresh(self) -> int:
        """Vuelve a buscar todo. Si ya hay un escaneo en curso, espera a que termine y usa ese."""
        if not self._refreshing.acquire(blocking=False):
            with self._refreshing:
                return len(self.store.all())
        try:
            return self._refresh()
        finally:
            self._refreshing.release()

    def wait_ready(self, timeout: float = 15) -> None:
        """Espera (un poco) a que termine el escaneo en curso: abrir un juego necesita saber qué
        emuladores hay, y al arrancar la biblioteca que se ve puede ser la guardada."""
        if self._refreshing.acquire(timeout=timeout):
            self._refreshing.release()

    def load_snapshot(self) -> bool:
        """La biblioteca del último arranque, para mostrarla ya. False si no hay (o está dañada)."""
        if not self._snapshot or not self._snapshot.exists():
            return False
        try:
            items = [LibraryItem.from_dict(d) for d in json.loads(self._snapshot.read_text(encoding="utf-8"))]
        except (OSError, ValueError, TypeError, AttributeError, KeyError) as exc:
            log.info("Biblioteca guardada ilegible (se escanea de cero): %s", exc)
            return False
        if not items:
            return False
        self.store.replace(items)
        self._migrate_runner_prefs(items)
        log.info("Biblioteca guardada: %d elementos (escaneando para ponerla al día)", len(items))
        return True

    def _save_snapshot(self, items: list[LibraryItem]) -> None:
        if not self._snapshot:
            return
        try:
            self._snapshot.parent.mkdir(parents=True, exist_ok=True)
            atomic_write(self._snapshot, json.dumps([i.to_dict() for i in items]), encoding="utf-8")
        except (OSError, TypeError, ValueError) as exc:
            log.info("No pude guardar la biblioteca: %s", exc)

    def _refresh(self) -> int:
        found: list[LibraryItem] = []
        if self.config.steam.enabled:
            self.steam_root = steam.find_steam(self.config.steam.path)
            if self.steam_root:
                try:
                    installed = steam.scan(self.steam_root)
                    found += installed
                    have = {i.id.removeprefix("steam:") for i in installed}
                    self._steam_owned = sorted(steam.owned_appids(self.steam_root) - have)
                except Exception:  # noqa: BLE001 - un archivo de Steam roto no tumba el escaneo
                    log.exception("No pude leer la biblioteca de Steam")
                # Steam ya no se abre al arrancar Orbital (eran ~0,6 GB todo el día que los juegos necesitan): se abre en
                # silencio al abrir un juego de Steam (sessions.launch › steam.ready_silent).
                found.append(
                    LibraryItem(
                        id="steam:bigpicture",
                        title="Steam Big Picture",
                        category="apps",
                        source="steam",
                        subtitle="Tienda y biblioteca completa",
                        uri=steam.big_picture_uri(),
                    )
                )
            else:
                log.info("Steam no encontrado")
        self.esde = esde.find(self.config.esde)
        if self.esde and self.esde.executable:
            found.append(
                LibraryItem(
                    id="app:esde",
                    title="ES-DE",
                    category="apps",
                    source="esde",
                    subtitle="Todos tus sistemas",
                    argv=[str(self.esde.executable)],
                    cwd=str(self.esde.executable.parent),
                    icon_path=str(self.esde.executable.parent / "resources" / "graphics" / "window_icon_256.png"),
                )
            )
        self.emulators = list(self.config.emulators)
        self.detected = {}
        if self.config.detect.enabled:
            dirs = detect.default_search_dirs(self.config.detect.dirs, self.esde.executable if self.esde else None)
            result = detect.detect(dirs, skip_ids={e.id for e in self.config.emulators})
            self.emulators = detect.merge(self.config.emulators, result.emulators)
            self.detected = result.found
        self.emulators += self._esde_emulators()
        if not self.esde and self.config.detect.roms:
            # Sin ES-DE: cada consola en su subcarpeta de tu carpeta de ROMs (la misma convención: switch, gc, xbox360…).
            roms = Path(expand(self.config.detect.roms))
            for emu in self.emulators:
                if not emu.rom_dirs and emu.system:
                    emu.rom_dirs = [str(roms / emu.system)]
        for emu, alternatives in emulators.split_alternatives(self.emulators):
            try:
                found += emulators.scan(emu, self.esde, alternatives, self.media)
            except Exception:  # noqa: BLE001 - un emulador con problemas no debe dejar a Orbital sin arrancar
                log.exception("No pude leer los juegos de %s", emu.name)
        if self.config.stremio.enabled:
            found += stremio.items(self.config.stremio)
        gfn_app = geforcenow.app_item()
        cloud: dict[str, dict] = {}
        if gfn_app:
            found.append(gfn_app)
            # Los de tu cuenta de Steam sin instalar que se pueden jugar en la nube: como juegos de GeForce NOW.
            if self._steam_owned and self.config.source:  # no en pruebas: la lista pública sale a internet
                try:
                    public = geforcenow.cloud_by_steam(self._cache / "gfn-public.json" if self._cache else None)
                    cloud = {a: public[a] for a in self._steam_owned if a in public}
                except Exception:  # noqa: BLE001 - la lista de NVIDIA nunca tumba el escaneo
                    log.exception("No pude leer la lista pública de GeForce NOW")
            gfn_games = geforcenow.items(self._steam_art, list(cloud.items()))
            found += gfn_games
            in_cloud = {str(i.steam_appid) for i in gfn_games if i.steam_appid}  # ya en GeForce NOW: no repetido en Steam
        else:
            in_cloud = set()
        # Todo lo de tu cuenta de Steam sin instalar (los que la tienda dice que son juegos) también está en Steam, con
        # «Instalar»: lo que se juega en la nube sigue además en GeForce NOW (antes solo ahí, y «Papers, Please» parecía
        # no estar en tu Steam).
        for appid in self._steam_owned:
            playable = appid in cloud or appid in in_cloud
            name = (cloud.get(appid) or {}).get("title") if appid in cloud else None
            if (name := name or self.steam_store.game_name(appid)) and steam._is_game(appid, name):
                found.append(steam.uninstalled_item(appid, name, cloud=playable))
        for app in self.config.apps:
            is_uri = "://" in app.target
            found.append(
                LibraryItem(
                    id=f"app:{app.id}",
                    title=app.name,
                    category=app.category,
                    source="app",
                    uri=app.target if is_uri else None,
                    argv=[] if is_uri else [app.target, *app.args],
                )
            )
        found += self.watch.stremio_items
        found += self.watch.cinemeta_items
        for item in found:
            url = f"/api/art/{quote(item.id, safe=':')}"
            if item.art_path:
                item.image = url + art_version(item.art_path, "?")
            if item.hero_path:
                item.hero = url + "?kind=hero" + art_version(item.hero_path)
                if low_res(item.hero_path):
                    item.extra["hero_lowres"] = True
            if item.logo_path:
                item.extra["logo"] = url + "?kind=logo" + art_version(item.logo_path)
            if item.icon_path and Path(item.icon_path).is_file():
                item.extra["icon"] = url + "?kind=icon"
            # Regla: todo lleva imagen. Sin portada o sin fondo, el respaldo de su sistema.
            if not item.image and item.category not in ("apps", "media"):
                item.image = placeholder("cover", item.system, item.id)
                item.extra["placeholder_cover"] = True
            if not item.hero:
                item.hero = placeholder("hero", item.system, item.id)
                item.extra["placeholder_hero"] = True
            self._store_facts(item)
            self._chosen_art(item)
        self.state.mark_seen([i.id for i in found if i.category in ("emulators", "steam")])
        self.store.replace(found)
        self._migrate_runner_prefs(found)
        self._save_snapshot(found)
        if self.library_watch is not None:
            self.library_watch.accept()  # lo que hay ahora ya está escaneado: el vigilante no lo vuelve a pedir
        log.info("Catálogo: %d elementos", len(found))
        self.warm_covers()
        self.warm_tones()
        self.scrape_art(background=True)
        self.watch.refresh_stremio(background=True)
        self.watch.refresh_trakt(background=True, force=True)
        if not self.watch.cinemeta_items:
            self.watch.refresh_cinemeta(background=True)
        return len(found)

    @staticmethod
    def thumbs_dir() -> Path:
        from ..library import media

        return media.default_root().parent / "thumbs"

    def warm_covers(self) -> None:
        """Las portadas reducidas de toda la biblioteca, en segundo plano (ver thumbs.py)."""
        from .. import thumbs

        paths = [Path(i.art_path) for i in self.store.all() if i.art_path]
        threading.Thread(target=thumbs.warm, args=(paths, thumbs.COVER_WIDTH, self.thumbs_dir()), daemon=True,
                         name="thumbs").start()

    # --- juegos nuevos con Orbital abierto (library_watch.py) ------------------
    library_watch: LibraryWatcher | None = None  # el vigilante de carpetas (solo en la Orbital de verdad: server.py lo arranca)

    def watched_folders(self) -> list[tuple[Path, bool | str]]:
        """Las carpetas donde aparecen juegos: las de cada emulador (con subcarpetas si el emulador las recorre) y las de
        Steam (sus appmanifest: un juego recién instalado)."""
        out: list[tuple[Path, bool | str]] = []
        for emu in self.emulators:
            out += [(d, bool(emu.recursive)) for d in emulators.rom_dirs(emu, self.esde)]
        if self.steam_root:
            out += [(f, NAMES_ONLY) for f in steam.library_folders(self.steam_root)]
        return out

    def rescan_for_new(self) -> list[LibraryItem]:
        """Algo cambió en las carpetas de juegos: vuelve a buscar (con su portada, logo y datos) y avisa a la tele con el
        nombre de lo que llegó. Devuelve los juegos nuevos."""
        before = {i.id for i in self.store.all()}
        self.refresh()
        new = [i for i in self.store.all() if i.id not in before and i.category in ("emulators", "steam")]
        self.notify({"type": "library-changed"})
        if new:
            names = ", ".join(i.title for i in new[:3]) + (f" y {len(new) - 3} más" if len(new) > 3 else "")
            log.info("Juegos nuevos: %s", names)
            self.notify({"type": "toast", "tone": "success", "message": "Nuevo en tu biblioteca", "detail": names})
        return new
