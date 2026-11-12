"""El arte: portadas, fondos y logos de los juegos (scraper propio), el arte elegido de películas y series, y los tonos."""

from __future__ import annotations

import threading
from dataclasses import replace
from pathlib import Path

from ..library.media import KINDS, low_res
from ..library.models import LibraryItem
from ..library.scraper import Scraper, Target
from .base import log, tone_path
from .facts import _Facts


class _Art(_Facts):
    # --- arte de los juegos (scraper propio) -----------------------------------------------------
    def art_targets(self, force: bool = False) -> list[Target]:
        """Juegos a los que les falta portada, fondo o logotipo (o el de ES-DE no sirve)."""
        paths = {"cover": "art_path", "hero": "hero_path", "logo": "logo_path"}
        targets = []
        for item in self.store.all():
            if not item.system or not item.media_key:
                continue
            # Un fondo que es solo una captura chica también se intenta mejorar (fanart).
            kinds = [k for k in KINDS
                     if not self.media.path(item.system, item.media_key, k)
                     and (force or not getattr(item, paths[k]) or (k == "hero" and low_res(item.hero_path)))]
            if self.media.meta(item.system, item.media_key) is None:
                kinds.append("meta")
            if kinds:
                targets.append(Target(item.system, item.media_key, item.title, kinds))
        return targets

    def scrape_art(self, background: bool = False) -> int:
        """Busca el arte que falte; si consiguió algo, vuelve a escanear para mostrarlo."""
        if not self.config.art.scrape:
            return 0
        if background:
            threading.Thread(target=self.scrape_art, name="scraper", daemon=True).start()
            return 0
        if not self._scraping.acquire(blocking=False):
            return 0
        try:
            targets = []
            for t in self.art_targets():
                kinds = [k for k in t.kinds if (t.system, t.key, k) not in self._scraped]
                self._scraped.update((t.system, t.key, k) for k in kinds)
                if kinds:
                    targets.append(Target(t.system, t.key, t.title, kinds))
            if not targets:
                return 0
            self._scraper = self._scraper or self._new_scraper()
            added = self._scraper.run(targets)
        except Exception:  # noqa: BLE001 - sin internet o una fuente caída: se queda el arte que hay
            log.exception("No pude buscar arte")
            return 0
        finally:
            self._scraping.release()
        if added:
            log.info("Scraper: %d imágenes nuevas", added)
            self.refresh()
            self.notify({"type": "library-changed"})  # la tele enseña la portada nueva (antes, hasta recargar)
        return added

    def replace_art(self, item_id: str, kind: str) -> bool:
        """«No me gusta esta imagen»: la descarta y busca otra."""
        item = self.store.get(item_id)
        if item is None or not item.system or not item.media_key or kind not in KINDS:
            return False
        self._scraper = self._scraper or self._new_scraper()
        current = {"cover": item.art_path, "hero": item.hero_path, "logo": item.logo_path}.get(kind)
        found = self._scraper.replace(Target(item.system, item.media_key, item.title, [kind]), kind, current)
        self.refresh()
        return found is not None

    def _art_target(self, item_id: str):
        item = self.store.get(item_id)
        if item is None or not item.system or not item.media_key:
            return None
        self._scraper = self._scraper or self._new_scraper()
        return Target(item.system, item.media_key, item.title, ["cover", "hero"])

    def _new_scraper(self) -> Scraper:
        """Con la clave de SteamGridDB si la escribiste (Ajustes › Cuentas): se lee cada vez, así sirve en cuanto la pones."""
        return Scraper(self.media, sgdb_key=lambda: self.foryou.key("steamgriddb_key") if self.foryou else "")

    def art_choices(self, item_id: str) -> dict | None:
        """«Elegir imagen» de un juego: las portadas y fondos que hay, y cuáles tiene ahora (como el de películas)."""
        target = self._art_target(item_id)
        if target is None:
            return None
        found = self._scraper.choices(target)
        sources = self._scraper.sources()
        slot = f"{target.system}/{target.key}"
        return {"posters": found["cover"], "backgrounds": found["hero"],
                "current": {"poster": sources.get(f"{slot}/cover"), "background": sources.get(f"{slot}/hero")}}

    def choose_art(self, item_id: str, which: str, url: str | None) -> bool:
        """Elegiste una portada o un fondo; sin `url`, «La automática»: Orbital vuelve a escoger."""
        target = self._art_target(item_id)
        kind = {"poster": "cover", "background": "hero"}.get(which)
        if target is None or kind is None:
            return False
        if url:
            ok = self._scraper.choose(target, kind, url) is not None
        else:
            self.media.remove(target.system, target.key, kind)
            ok = bool(self._scraper.fetch(replace(target, kinds=[kind])))
        self.refresh()
        return ok

    def _chosen_art(self, item: LibraryItem) -> None:
        """«Cambiar el arte»: el póster o el fondo que elegiste para esa película o serie, en lugar del de siempre."""
        meta_id = (item.extra or {}).get("meta_id")
        if item.source not in ("stremio", "cinemeta") or not meta_id:
            return
        art = self.watch.art_for(meta_id)
        if art.get("poster"):
            item.image = art["poster"]
        if art.get("background"):
            item.hero = art["background"]

    def apply_art(self, meta_id: str) -> None:
        """Se acaba de elegir arte: la biblioteca lo toma ya, sin reescanear."""
        self.store.update(self._chosen_art, where=lambda i: (i.extra or {}).get("meta_id") == meta_id)
        self.notify({"type": "library-changed"})


    def warm_tones(self) -> None:
        """Mide en segundo plano el tono del fondo de toda la biblioteca (V3); lo ya medido no se repite."""
        if self.tones is None:
            return
        paths = [Path(p) for i in self.store.all() if (p := tone_path(i))]
        threading.Thread(target=self.tones.warm, args=(paths,), daemon=True, name="art-tones").start()
