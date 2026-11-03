"""Tus complementos, de Orbital y no de tu cuenta de Stremio («La TV sin Stremio», S1; design/addons-contract.json).

La lista vive en la consola, cifrada como la sesión de Stremio (las direcciones de lo traído llevan claves): en su orden,
cada uno prendido o apagado por aparato («tv» aquí; el iPhone pone el suyo con S6). Se trae de tu Stremio una vez
(«Traer de tu Stremio», «Volver a traer»); desde ahí es tuya y tu cuenta no se toca. `source` dice de dónde salen las
fuentes: «stremio» (como antes: los de tu cuenta) o «own» (esta lista). «Volver a los de Stremio» solo cambia `source`:
tu lista se queda.

No se agregan complementos a mano (Fernando, 3 nov 2026): solo lo que viene con Orbital y lo traído de Stremio.
"""

from __future__ import annotations

import threading
import time
import uuid
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass, field

LIST_KEY = "addon_list"
DEVICE = "tv"
OPENSUBTITLES = "https://opensubtitles-v3.strem.io/manifest.json"
# Lo que viene con Orbital (como AddonTemplates del iPhone). Torrentio y Comet se arman con tu clave de Real-Debrid:
# llegan con S2; mientras, tu Torrentio es el traído de Stremio.
TEMPLATES = {"opensubtitles": {"name": "OpenSubtitles", "url": OPENSUBTITLES, "default": True}}
# Lo que Orbital ya usa por su cuenta: traerlo como complemento pediría todo dos veces (y apagarlo rompería las fichas).
SKIP_IDS = ("com.linvo.cinemeta", "org.stremio.local")
SKIP_HOSTS = ("v3-cinemeta.strem.io", "cinemeta.strem.io")
LOCAL_HOSTS = ("127.0.0.1", "localhost")


@dataclass
class Entry:
    id: str
    origin: str  # «orbital» | «stremio»
    name: str
    order: int
    enabled: dict[str, bool] = field(default_factory=dict)
    url: str | None = None  # solo lo traído de Stremio
    template: str | None = None  # solo lo de Orbital
    only_on: str | None = None  # «tv»: vive en esta computadora (Archivos de la TV)
    options: dict | None = None
    extra: dict = field(default_factory=dict)

    @property
    def address(self) -> str | None:
        return TEMPLATES[self.template]["url"] if self.template in TEMPLATES else self.url

    def on(self, device: str = DEVICE) -> bool:
        if self.only_on and self.only_on != device:
            return False
        default = TEMPLATES[self.template]["default"] if self.template in TEMPLATES else True
        return self.enabled.get(device, default)


def entry_from(item) -> Entry | None:
    """Una entrada guardada (o recibida), con cada campo de su tipo; None si no sirve."""
    if not isinstance(item, dict) or not isinstance(item.get("id"), str) or item.get("origin") not in ("orbital", "stremio"):
        return None
    text = lambda key: item[key] if isinstance(item.get(key), str) else None  # noqa: E731
    enabled = item.get("enabled") if isinstance(item.get("enabled"), dict) else {}
    order = item.get("order")
    return Entry(id=item["id"], origin=item["origin"], name=text("name") or "", order=order if isinstance(order, int) else 0,
                 enabled={k: v for k, v in enabled.items() if isinstance(k, str) and isinstance(v, bool)},
                 url=text("url"), template=text("template"), only_on=text("only_on"),
                 options=item["options"] if isinstance(item.get("options"), dict) else None,
                 extra=item["extra"] if isinstance(item.get("extra"), dict) else {})


def host(url: str) -> str:
    return url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0].lower()


class AddonList:
    """La lista y sus cambios. `store` es el llavero de la consola (credentials.Credentials o un dict en pruebas)."""

    def __init__(self, store, legacy: Callable[[], Iterable[str]] = lambda: ()) -> None:
        self.store = store
        self.legacy = legacy  # los que agregaste con `orbital stremio addon add` (antes de S1): se traen como de Stremio
        self._lock = threading.Lock()

    # --- leer ----------------------------------------------------------------------------------------------------
    def _raw(self) -> dict:
        data = self.store.get(LIST_KEY)
        return data if isinstance(data, dict) else {}

    @property
    def source(self) -> str:
        return "own" if self._raw().get("source") == "own" else "stremio"

    @property
    def revision(self) -> int:
        value = self._raw().get("revision")
        return value if isinstance(value, int) and value >= 0 else 0

    @property
    def imported_at(self) -> float | None:
        value = self._raw().get("imported_at")
        return float(value) if isinstance(value, (int, float)) else None

    def entries(self) -> list[Entry]:
        out = []
        for item in self._raw().get("entries") or []:
            entry = entry_from(item)
            if entry and entry.address:
                out.append(entry)
        if not any(e.template == "opensubtitles" for e in out):  # lo de Orbital siempre está (apagado o prendido)
            out.append(Entry(id="opensubtitles", origin="orbital", name="OpenSubtitles", template="opensubtitles",
                             order=len(out)))
        return sorted(out, key=lambda e: e.order)

    def urls(self, device: str = DEVICE) -> list[str]:
        """Las direcciones prendidas en este aparato, en su orden (lo que AddonRegistry pide)."""
        return [e.address for e in self.entries() if e.on(device) and e.address]

    # --- escribir ------------------------------------------------------------------------------------------------
    def _save(self, entries: list[Entry], **extra) -> None:
        data = self._raw()
        removed = [*data.get("removed", []), *extra.pop("removed", [])]
        for i, entry in enumerate(sorted(entries, key=lambda e: e.order)):
            entry.order = i
        self.store.set(LIST_KEY, {**data, **extra, "revision": self.revision + 1, "changed_at": time.time(),
                                  "changed_by": DEVICE, "entries": [asdict(e) for e in entries],
                                  "removed": list(dict.fromkeys(r for r in removed if isinstance(r, str)))})

    def import_from_stremio(self, addons: list[tuple[str, str, dict | None]]) -> dict:
        """Trae (o vuelve a traer) tus complementos de Stremio: [(nombre, dirección del manifiesto, manifiesto)]. Lo que
        ya estaba se queda con su id, su prendido o apagado y su lugar; lo nuevo entra al final, prendido. Desde ahí las
        fuentes salen de esta lista (`source` «own»). Devuelve {"added", "kept", "skipped"}."""
        with self._lock:
            entries = self.entries()
            by_url = {e.url: e for e in entries if e.url}
            removed = set(self._raw().get("removed") or [])
            added = kept = skipped = 0
            seen = set()
            for name, url, manifest in [*addons, *(("", u, None) for u in self.legacy())]:
                if not url or url in seen:
                    continue
                seen.add(url)
                ident = manifest.get("id") if isinstance(manifest, dict) else None
                if ident in SKIP_IDS or host(url) in SKIP_HOSTS:
                    skipped += 1
                    continue
                if url == OPENSUBTITLES or (isinstance(ident, str) and ident.startswith("org.stremio.opensubtitles")):
                    skipped += 1  # ya viene con Orbital
                    continue
                if url in by_url:
                    entry = by_url[url]
                    if name:
                        entry.name = name
                    kept += 1
                    continue
                entry = Entry(id=str(uuid.uuid4()), origin="stremio", name=name or host(url), url=url,
                              order=len(entries), enabled={DEVICE: True},
                              only_on=DEVICE if host(url) in LOCAL_HOSTS else None)
                if entry.id in removed:
                    continue
                entries.append(entry)
                added += 1
            self._save(entries, source="own", imported_at=time.time())
            return {"added": added, "kept": kept, "skipped": skipped}

    def set_enabled(self, ident: str, on: bool, device: str = DEVICE) -> Entry:
        with self._lock:
            entries = self.entries()
            entry = self._find(entries, ident)
            if entry.only_on and entry.only_on != device:
                raise ValueError(f"{entry.name} solo funciona en la TV")
            entry.enabled = {**entry.enabled, device: on}
            self._save(entries)
            return entry

    def move(self, ident: str, step: int) -> Entry:
        with self._lock:
            entries = self.entries()
            entry = self._find(entries, ident)
            i = entries.index(entry)
            j = max(0, min(len(entries) - 1, i + step))
            entries.insert(j, entries.pop(i))
            for k, e in enumerate(entries):
                e.order = k
            self._save(entries)
            return entry

    def remove(self, ident: str) -> Entry:
        """Quita uno traído de Stremio (lo de Orbital no se borra: se apaga)."""
        with self._lock:
            entries = self.entries()
            entry = self._find(entries, ident)
            if entry.origin != "stremio":
                raise ValueError(f"{entry.name} viene con Orbital: se apaga, no se quita")
            entries.remove(entry)
            self._save(entries, removed=[entry.id])
            return entry

    def restore(self, entry: dict) -> Entry:
        """«Deshacer» tras quitar: regresa a su lugar."""
        with self._lock:
            back = entry_from(entry)
            if back is None:
                raise KeyError("entrada")
            entries = [e for e in self.entries() if e.id != back.id]
            entries.insert(min(back.order, len(entries)), back)
            for k, e in enumerate(entries):
                e.order = k
            data = self._raw()
            self.store.set(LIST_KEY, {**data, "removed": [r for r in data.get("removed") or [] if r != back.id]})
            self._save(entries)
            return back

    def set_source(self, source: str) -> None:
        """«own»: las fuentes salen de esta lista; «stremio»: de tu cuenta, como antes (la lista se queda)."""
        if source not in ("own", "stremio"):
            raise ValueError(source)
        with self._lock:
            self._save(self.entries(), source=source)

    @staticmethod
    def _find(entries: list[Entry], ident: str) -> Entry:
        found = next((e for e in entries if e.id == ident), None)
        if found is None:
            raise KeyError(ident)
        return found
