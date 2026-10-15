"""Scraper propio: consigue portada, fondo horizontal y logotipo de cada juego sin pasar por ES-DE.

Fuentes, en orden, y ninguna pide clave:
- libretro-thumbnails: portadas de cajas para sistemas retro, por el nombre exacto de la ROM (No-Intro).
- TheGamesDB: portada, fanart horizontal y logotipo de casi cualquier consola (se lee su web pública).
- Steam: para juegos que también salieron en PC (portada, héroe y logotipo oficiales).

Cada imagen se valida antes de guardarla (media.good): una captura no pasa como portada ni un fondo
chico como héroe. Lo que rechazaste no vuelve. Uso: python -m orbital.library.scraper [--force]
"""

from __future__ import annotations

import difflib
import html
import json
import logging
import re
import threading
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

from ..net import NET_ERRORS, read_body
from .media import IMAGE_EXTS, MediaStore, good, image_look, image_size

log = logging.getLogger(__name__)

USER_AGENT = "Orbital/1.0 (consola personal; scraper de portadas)"
TIMEOUT = 15

# Sistemas de ES-DE -> plataforma de TheGamesDB.
TGDB_PLATFORMS = {
    "switch": 4971, "gc": 2, "wii": 9, "wiiu": 38, "n64": 3, "nes": 7, "snes": 6, "gb": 4, "gbc": 41,
    "gba": 5, "nds": 8, "n3ds": 4912, "3ds": 4912, "psx": 10, "ps2": 11, "ps3": 12, "psp": 13,
    "psvita": 39, "xbox": 14, "xbox360": 15, "dreamcast": 16, "saturn": 17, "genesis": 18,
    "megadrive": 36, "mastersystem": 35, "gamegear": 20,
}
# Sistemas de ES-DE -> carpeta de libretro-thumbnails.
LIBRETRO_SYSTEMS = {
    "gba": "Nintendo - Game Boy Advance", "gb": "Nintendo - Game Boy", "gbc": "Nintendo - Game Boy Color",
    "nes": "Nintendo - Nintendo Entertainment System", "snes": "Nintendo - Super Nintendo Entertainment System",
    "n64": "Nintendo - Nintendo 64", "nds": "Nintendo - Nintendo DS", "gc": "Nintendo - GameCube",
    "wii": "Nintendo - Wii", "psx": "Sony - PlayStation", "ps2": "Sony - PlayStation 2",
    "psp": "Sony - PlayStation Portable", "xbox": "Microsoft - Xbox", "xbox360": "Microsoft - Xbox 360",
    "genesis": "Sega - Mega Drive - Genesis", "megadrive": "Sega - Mega Drive - Genesis",
    "dreamcast": "Sega - Dreamcast", "saturn": "Sega - Saturn",
}
LIBRETRO = "https://thumbnails.libretro.com/{system}/{folder}/{name}.png"
TGDB_SEARCH = "https://thegamesdb.net/search.php?name={name}&platform_id%5B%5D={platform}"
TGDB_GAME = "https://thegamesdb.net/game.php?id={id}"
TGDB_IMAGE = "https://cdn.thegamesdb.net/images/original/{path}"
STEAM_SEARCH = "https://store.steampowered.com/api/storesearch/?term={term}&cc=us&l=english"
STEAM_ASSET = "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{name}"


@dataclass
class Target:
    """Un juego al que le hace falta arte."""

    system: str
    key: str  # nombre de la ROM sin extensión (también el del archivo de imagen)
    title: str
    kinds: list[str] = field(default_factory=lambda: ["cover", "hero", "logo"])


@dataclass
class Candidate:
    kind: str
    url: str
    source: str
    # 0 = arte oficial (fanart, héroe de Steam, caja); 1 = captura del juego (cuando no hay otra cosa).
    rank: int = 0


def clean(title: str) -> str:
    """Título para buscar: sin etiquetas de región/versión ni ids entre corchetes."""
    title = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", title)
    title = title.replace("_", " ")
    # "Simpsons, The - Hit & Run" -> "The Simpsons - Hit & Run"
    title = re.sub(r"^(.*?), (The|A|An)\b", r"\2 \1", title.strip())
    return re.sub(r"\s+", " ", title).strip()


def _norm(title: str) -> str:
    title = html.unescape(title).lower().replace("&", " and ")
    title = re.sub(r"[™®©:\-–—'’!.,]", " ", title)
    title = re.sub(r"\bthe\b|\band\b", " ", title)
    return re.sub(r"\s+", " ", title).strip()


def similar(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, _norm(a), _norm(b)).ratio()


class Http:
    """Peticiones educadas: un agente propio y una pausa entre consultas al mismo sitio."""

    def __init__(self, pause: float = 0.6) -> None:
        self.pause = pause
        self._last: dict[str, float] = {}
        self._lock = threading.Lock()

    def get(self, url: str) -> bytes | None:
        host = urllib.parse.urlsplit(url).netloc
        with self._lock:
            wait = self._last.get(host, 0) + self.pause - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self._last[host] = time.monotonic()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
                return read_body(res, timeout=TIMEOUT)
        except NET_ERRORS as exc:
            log.debug("Sin respuesta de %s: %s", url, exc)
            return None


class TheGamesDB:
    name = "thegamesdb"

    def __init__(self, http: Http) -> None:
        self.http = http
        self._pages: dict[int, str] = {}

    def page(self, game: int) -> str:
        if game not in self._pages:
            raw = self.http.get(TGDB_GAME.format(id=game))
            self._pages[game] = raw.decode("utf-8", "replace") if raw else ""
        return self._pages[game]

    def meta(self, target: Target) -> dict | None:
        platform = TGDB_PLATFORMS.get(target.system)
        games = self.search(clean(target.title), platform, 0.75) if platform else []
        text = self.page(games[0]) if games else ""
        if not text:
            return None

        def field(pattern: str) -> str | None:
            m = re.search(pattern, text, re.S)
            value = html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() if m else ""
            return re.sub(r"\s+", " ", value) or None

        data = {
            "title": field(r"<h1[^>]*>(.*?)</h1>"),
            "description": field(r'<p class="game-overview"[^>]*>(.*?)</p>'),
            "released": field(r"ReleaseDate:\s*([^<]*)"),
            "players": field(r"Players:\s*([^<]*)"),
            "developer": field(r"Developer\(s\):.*?<a[^>]*>([^<]*)"),
            "publisher": field(r"Publishers?\(s\):.*?<a[^>]*>([^<]*)"),
            "genres": [g.strip() for g in (field(r"Genre\(s\):\s*([^<]*)") or "").split("|") if g.strip()],
            "source": TGDB_GAME.format(id=games[0]),
        }
        return {k: v for k, v in data.items() if v}

    def search(self, title: str, platform: int | None, threshold: float) -> list[int]:
        """Ids de los resultados que se llaman como el juego, del más parecido al menos."""
        url = TGDB_SEARCH.format(name=urllib.parse.quote_plus(title), platform=platform)
        if platform is None:
            url = url.split("&platform_id")[0]
        page = self.http.get(url)
        if not page:
            return []
        text = page.decode("utf-8", "replace")
        results = re.findall(r'game\.php\?id=(\d+)">.*?<div class="card-footer[^>]*>\s*<p>([^<]*)</p>', text, re.S)
        scored = sorted(((similar(title, name), int(gid)) for gid, name in results), reverse=True)
        return [gid for score, gid in scored if score >= threshold]

    def images(self, game: int, kinds: set[str]) -> list[Candidate]:
        found = re.findall(r"images/original/((boxart/front|fanart|clearlogo|screenshot)/(\d+)-?(\d*)\.\w+)", self.page(game))
        names = {"boxart/front": "cover", "fanart": "hero", "clearlogo": "logo", "screenshot": "hero"}
        # Orden natural: fanart/12-2 antes que fanart/12-10.
        found = sorted(set(found), key=lambda f: (f[1], int(f[3] or 0)))
        return [Candidate(names[folder], TGDB_IMAGE.format(path=path), self.name, rank=1 if folder == "screenshot" else 0)
                for path, folder, _, _ in found if names[folder] in kinds]

    def candidates(self, target: Target) -> list[Candidate]:
        platform = TGDB_PLATFORMS.get(target.system)
        if platform is None:
            return []
        title = clean(target.title)
        games = self.search(title, platform, 0.75)
        found = self.images(games[0], set(target.kinds)) if games else []
        # Fondo y logotipo son del juego, no de la caja: si esta versión no los tiene, sirven los de la
        # misma obra en otra consola (Hit & Run de Xbox con el fanart de la de GameCube).
        lacking = {"hero", "logo"} & set(target.kinds) - {c.kind for c in found}
        if lacking:
            for other in [g for g in self.search(title, None, 0.92) if g not in games[:1]][:3]:
                found += self.images(other, lacking)
        return found


class Libretro:
    name = "libretro"

    def candidates(self, target: Target) -> list[Candidate]:
        system = LIBRETRO_SYSTEMS.get(target.system)
        if system is None:
            return []
        # libretro cambia estos caracteres por "_" en los nombres de archivo.
        name = urllib.parse.quote(re.sub(r'[&*/:`<>?\\|"]', "_", target.key))
        url = lambda folder: LIBRETRO.format(system=urllib.parse.quote(system), folder=folder, name=name)  # noqa: E731
        return [
            Candidate("cover", url("Named_Boxarts"), self.name),
            # Sin fanart: una captura del juego o su pantalla de título (mejor que un respaldo genérico).
            Candidate("hero", url("Named_Snaps"), self.name, rank=1),
            Candidate("hero", url("Named_Titles"), self.name, rank=1),
        ]


class Steam:
    name = "steam"

    def __init__(self, http: Http) -> None:
        self.http = http

    def candidates(self, target: Target) -> list[Candidate]:
        title = clean(target.title)
        data = self.http.get(STEAM_SEARCH.format(term=urllib.parse.quote(title)))
        try:
            items = (json.loads(data) if data else {}).get("items") or []
        except ValueError:
            return []
        # Solo si el nombre coincide de verdad: "Pikmin" no debe traer otro juego que sí está en Steam.
        match = next((i for i in items if similar(title, i.get("name", "")) >= 0.9), None)
        if not match:
            return []
        appid = match["id"]
        return [
            Candidate("cover", STEAM_ASSET.format(appid=appid, name="library_600x900_2x.jpg"), self.name),
            Candidate("hero", STEAM_ASSET.format(appid=appid, name="library_hero.jpg"), self.name),
            Candidate("logo", STEAM_ASSET.format(appid=appid, name="logo.png"), self.name),
        ]


class Scraper:
    def __init__(self, store: MediaStore | None = None, http: Http | None = None) -> None:
        self.store = store or MediaStore()
        self.http = http or Http()
        self.providers = [Libretro(), TheGamesDB(self.http), Steam(self.http)]
        self._sources_file = self.store.root / "fuentes.json"

    def sources(self) -> dict[str, str]:
        try:
            data = json.loads(self._sources_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return {k: v for k, v in data.items() if isinstance(v, str)} if isinstance(data, dict) else {}

    def _remember(self, slot: str, url: str) -> None:
        data = self.sources()
        data[slot] = url
        self._sources_file.parent.mkdir(parents=True, exist_ok=True)
        self._sources_file.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    def fetch(self, target: Target) -> dict[str, Path]:
        """Busca en las fuentes y guarda la primera imagen válida de cada tipo que falte (y la ficha)."""
        if "meta" in target.kinds and self.store.meta(target.system, target.key) is None:
            data = self.providers[1].meta(target)
            if data:
                self.store.save_meta(target.system, target.key, data)
        missing = [k for k in target.kinds if k != "meta" and not self.store.path(target.system, target.key, k)]
        saved: dict[str, Path] = {}
        candidates: list[Candidate] = []
        for provider in self.providers:
            if not missing:
                break
            try:
                candidates += provider.candidates(target)
            except Exception:  # noqa: BLE001 - una fuente rota no debe parar a las demás
                log.exception("Falló %s con %s", provider.name, target.title)
        # Primero el arte oficial de todas las fuentes; las capturas, solo si no hubo nada mejor.
        for cand in sorted(candidates, key=lambda c: c.rank):
            if cand.kind not in missing or self.store.is_rejected(target.system, target.key, cand.kind, cand.url):
                continue
            path = self._download(target, cand)
            if path:
                saved[cand.kind] = path
                missing.remove(cand.kind)
        if missing:
            log.info("Sin %s para %s (%s)", ", ".join(missing), target.title, target.system)
        return saved

    def _download(self, target: Target, cand: Candidate) -> Path | None:
        data = self.http.get(cand.url)
        if not data or len(data) < 2048:
            return None
        ext = Path(urllib.parse.urlsplit(cand.url).path).suffix.lower()
        ext = ext if ext in IMAGE_EXTS else ".jpg"
        path = self.store.target(target.system, target.key, cand.kind, ext)
        tmp = path.with_name(path.name + ".part")
        tmp.write_bytes(data)
        if not good(cand.kind, image_size(tmp), target.system):
            tmp.unlink()
            return None
        if self.store.looks_rejected(target.system, target.key, cand.kind, tmp):  # la misma, con otra dirección
            tmp.unlink()
            return None
        for other in IMAGE_EXTS:  # una sola imagen por tipo
            old = path.with_suffix(other)
            if old.exists() and old != path:
                old.unlink()
        tmp.replace(path)
        self._remember(f"{target.system}/{target.key}/{cand.kind}", cand.url)
        log.info("%s: %s de %s", target.title, cand.kind, cand.source)
        return path

    def replace(self, target: Target, kind: str, current: Path | str | None = None) -> Path | None:
        """«No me gusta»: rechaza la imagen actual (o la de ES-DE) y busca otra que no se vea igual."""
        slot = f"{target.system}/{target.key}/{kind}"
        current = current or self.store.path(target.system, target.key, kind)
        look = image_look(current) if current else None
        if look:
            self.store.reject(target.system, target.key, kind, f"look:{look}")
        self.store.reject(target.system, target.key, kind, self.sources().get(slot, "esde"))
        self.store.remove(target.system, target.key, kind)
        return self.fetch(Target(target.system, target.key, target.title, [kind])).get(kind)

    def run(self, targets: list[Target]) -> int:
        """Rellena lo que falte; devuelve cuántas imágenes nuevas guardó."""
        return sum(len(self.fetch(t)) for t in targets)


def main(argv: list[str] | None = None) -> int:
    import argparse

    from ..catalog import Catalog
    from ..config import load_config

    parser = argparse.ArgumentParser(description="Consigue el arte de los juegos de Orbital.")
    parser.add_argument("--force", action="store_true", help="vuelve a buscar aunque ya haya arte de ES-DE")
    parser.add_argument("--system", help="solo este sistema (p. ej. psp)")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    config = load_config()
    config.art.scrape = False  # aquí se busca en primer plano, no en el hilo del catálogo
    catalog = Catalog(config)
    catalog.refresh()
    targets = [t for t in catalog.art_targets(force=args.force) if not args.system or t.system == args.system]
    print(f"{len(targets)} juegos por revisar")
    added = Scraper().run(targets)
    print(f"Listo: {added} imágenes nuevas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
