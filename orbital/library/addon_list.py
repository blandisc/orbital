"""Tus complementos, de Orbital y no de tu cuenta de Stremio («La TV sin Stremio», S1; design/addons-contract.json).

La lista vive en la consola, cifrada como la sesión de Stremio (las direcciones de lo traído llevan claves): en su orden,
cada uno prendido o apagado por aparato («tv» aquí; el iPhone pone el suyo con S6). Se trae de tu Stremio una vez
(«Traer de tu Stremio», «Volver a traer»); desde ahí es tuya y tu cuenta no se toca. `source` dice de dónde salen las
fuentes: «stremio» (como antes: los de tu cuenta) o «own» (esta lista). «Volver a los de Stremio» solo cambia `source`:
tu lista se queda.

No se agregan complementos a mano (Fernando, 3 nov 2026): solo lo que viene con Orbital y lo traído de Stremio.
"""

from __future__ import annotations

import re
import threading
import time
import uuid
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime

from . import torrentio

LIST_KEY = "addon_list"
DEVICE = "tv"
OPENSUBTITLES = "https://opensubtitles-v3.strem.io/manifest.json"
# Lo que viene con Orbital (como AddonTemplates del iPhone). Torrentio se arma con tus opciones y tu clave de Real-Debrid
# (corte S3): su dirección no se guarda, se arma cada vez. Si traes uno de tu Stremio, sus opciones pasan a este.
TEMPLATES = {"torrentio": {"name": "Torrentio", "url": None, "default": True},
             "comet": {"name": "Comet", "url": None, "default": False},
             "opensubtitles": {"name": "OpenSubtitles", "url": OPENSUBTITLES, "default": True}}
COMET_BASE = "https://comet.elfhosted.com"


def comet_url(key: str | None) -> str | None:
    """Comet con tu Real-Debrid, armado igual que el iPhone (AddonTemplates.swift): su configuración como JSON en base64
    en la ruta; solo lo que ya está en Real-Debrid. Si el base64 trae «/» o «+», un espacio más al final lo limpia."""
    if not key:
        return None
    import base64
    import json
    text = json.dumps({"cachedOnly": True, "debridServices": [{"apiKey": key, "service": "realdebrid"}]},
                      separators=(",", ":"), sort_keys=True)
    for _ in range(4):
        encoded = base64.b64encode(text.encode()).decode()
        if "/" not in encoded and "+" not in encoded:
            return f"{COMET_BASE}/{encoded}/manifest.json"
        text += " "
    return None
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
    built: str | None = field(default=None, repr=False)  # la dirección de Torrentio con tu clave: nunca se guarda

    @property
    def address(self) -> str | None:
        if self.template in ("torrentio", "comet"):
            return self.built
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


MASK = "•••"


OPAQUE = re.compile(r"^[A-Za-z0-9+/=_-]{32,}$")  # una configuración en base64 o cifrada (Comet, MediaFusion…)


def masked(url: str) -> str:
    """La dirección con sus claves tapadas («realdebrid=•••», o un tramo opaco de la ruta entero): así viaja y así se
    enseña. Comet y MediaFusion llevan la clave dentro de un tramo en base64: ese tramo se tapa completo."""
    url = re.sub(r"(?i)((?:%s)=)[^|/&%%]+" % "|".join(torrentio.SECRET_KEYS + ("apikey", "token", "key")), rf"\1{MASK}", url)
    head, sep, rest = url.partition("://")
    if not sep:
        return url
    parts = rest.split("/")
    return head + sep + "/".join(MASK if i and OPAQUE.match(p) else p for i, p in enumerate(parts))


class Conflict(Exception):  # noqa: N818 — así se llama en el contrato (409)
    """El otro aparato partió de una revisión vieja: va la lista actual para que junte y reintente."""

    def __init__(self, current: dict) -> None:
        super().__init__("La lista cambió")
        self.current = current


class AddonList:
    """La lista y sus cambios. `store` es el llavero de la consola (credentials.Credentials o un dict en pruebas)."""

    def __init__(self, store, legacy: Callable[[], Iterable[str]] = lambda: (),
                 key: Callable[[], str | None] = lambda: None, on_key: Callable[[str], None] = lambda key: None,
                 stremio: Callable[[], bool] = lambda: True) -> None:
        self.store = store
        self.stremio = stremio  # hay cuenta de Stremio conectada: sin ella (y sin haber elegido), la lista es la tuya
        self.legacy = legacy  # los que agregaste con `orbital stremio addon add` (antes de S1): se traen como de Stremio
        self.key = key  # tu clave de Real-Debrid (la de la consola): con ella se arma Torrentio
        self.on_key = on_key  # la clave que venía en un Torrentio traído, para la consola si todavía no tiene
        self._lock = threading.RLock()

    # --- leer ----------------------------------------------------------------------------------------------------
    def _raw(self) -> dict:
        data = self.store.get(LIST_KEY)
        return data if isinstance(data, dict) else {}

    @property
    def source(self) -> str:
        """«own» o «stremio». Si nunca elegiste: tu cuenta de Stremio si está conectada (como antes) y, sin ella, tu lista
        (corte S4: una TV nueva funciona sin cuenta de Stremio)."""
        saved = self._raw().get("source")
        if saved in ("own", "stremio"):
            return saved
        return "stremio" if self.stremio() else "own"

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
            if entry and (entry.address or entry.template in TEMPLATES):
                out.append(entry)
        for ident, template in TEMPLATES.items():  # lo de Orbital siempre está (apagado o prendido)
            if not any(e.template == ident for e in out):
                out.append(Entry(id=ident, origin="orbital", name=template["name"], template=ident, order=len(out)))
        key = self.key()
        for entry in out:
            if entry.template == "torrentio":
                entry.options = entry.options if entry.options is not None else dict(torrentio.RECOMMENDED)
                entry.built = torrentio.manifest_url(entry.options, key)
            elif entry.template == "comet":
                entry.built = comet_url(key)
        return sorted(out, key=lambda e: e.order)

    def torrentio(self) -> Entry:
        return next(e for e in self.entries() if e.template == "torrentio")

    def urls(self, device: str = DEVICE) -> list[str]:
        """Las direcciones prendidas en este aparato, en su orden (lo que AddonRegistry pide)."""
        return [e.address for e in self.entries() if e.on(device) and e.address]

    # --- escribir ------------------------------------------------------------------------------------------------
    def _save(self, entries: list[Entry], **extra) -> None:
        data = self._raw()
        removed = [*data.get("removed", []), *extra.pop("removed", [])]
        for i, entry in enumerate(sorted(entries, key=lambda e: e.order)):
            entry.order = i
        saved = []
        for e in entries:
            item = asdict(e)
            item.pop("built", None)
            if e.origin == "orbital":
                item["url"] = None  # la dirección de lo de Orbital (con tu clave) se arma, no se guarda
            saved.append(item)
        changed_by = extra.pop("changed_by", DEVICE)
        self.store.set(LIST_KEY, {**data, **extra, "revision": self.revision + 1, "changed_at": time.time(),
                                  "changed_by": changed_by, "entries": saved,
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
                if torrentio.is_torrentio(url):  # tu Torrentio: sus opciones pasan al de Orbital (corte S3)
                    self._adopt(entries, url)
                    kept += 1
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

    def _adopt(self, entries: list[Entry], url: str, place: Entry | None = None) -> None:
        """Un Torrentio de tu Stremio: el de Orbital toma sus opciones (si no las cambiaste aquí) y su lugar, y la clave
        que traía queda como la de la consola si todavía no tiene. Arma la misma dirección: nada cambia en tus versiones."""
        parsed = torrentio.parse(url)
        if parsed is None:
            return
        options, key = parsed
        mine = next(e for e in entries if e.template == "torrentio")
        if not mine.extra.get("set_here"):
            mine.options = options
        if place is not None:
            mine.order = place.order
            mine.enabled = dict(place.enabled)
        if key and not self.key():
            self.on_key(key)

    def adopt_torrentio(self) -> bool:
        """Al arrancar: los Torrentio que ya habías traído de Stremio pasan al de Orbital (corte S3). True si cambió algo."""
        with self._lock:
            entries = self.entries()
            brought = [e for e in entries if e.origin == "stremio" and e.url and torrentio.is_torrentio(e.url)]
            if not brought:
                return False
            for old in brought:
                self._adopt(entries, old.url or "", place=old if old is brought[0] else None)
                entries.remove(old)
            self._save(entries)
            return True

    def set_options(self, options: dict) -> Entry:
        """Las opciones de Torrentio de Orbital (Ajustes › Complementos › Torrentio): se guardan al cambiarlas."""
        with self._lock:
            entries = self.entries()
            mine = next(e for e in entries if e.template == "torrentio")
            mine.options = {k: v for k, v in options.items() if k in (*torrentio.ORDER, "verbatim")}
            mine.extra = {**mine.extra, "set_here": True}
            self._save(entries)
            return self.torrentio()

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

    # --- lo que viaja con el iPhone (corte S6; design/addons-contract.json, `store`, GET/PUT /api/addons) ----------
    def shared(self) -> dict:
        """La lista como la lee el iPhone: con su revisión y las direcciones con clave tapadas («•••»)."""
        data = self._raw()
        out = []
        for e in self.entries():
            item = {"id": e.id, "origin": e.origin, "name": e.name, "enabled": dict(e.enabled), "order": e.order}
            if e.template:
                item["template"] = e.template
            if e.origin == "stremio" and e.url:
                item["url"] = masked(e.url)
            if e.only_on:
                item["only_on"] = e.only_on
            if e.options is not None:
                item["options"] = e.options
            if e.extra:
                item["extra"] = {k: v for k, v in e.extra.items() if k != "set_here"}
            out.append(item)
        at = data.get("changed_at")
        iso = datetime.fromtimestamp(at, UTC).isoformat() if isinstance(at, (int, float)) else at
        return {"revision": self.revision, "changed_at": iso, "changed_by": data.get("changed_by") or DEVICE,
                "addons": out, "removed": list(data.get("removed") or [])}

    def receive(self, body: dict, device: str) -> dict:
        """PUT /api/addons: la lista que cambió otro aparato. Lanza Conflict (409, con la actual) si partió de otra
        revisión y ValueError (422) si algo no cuadra. Cada aparato cambia solo su propio prendido o apagado."""
        if not isinstance(body, dict) or not isinstance(body.get("base_revision"), int):
            raise ValueError("Falta la revisión de la que partiste")
        items = body.get("addons")
        if not isinstance(items, list) or len(items) > 100:
            raise ValueError("La lista no tiene la forma acordada")
        with self._lock:
            if body["base_revision"] != self.revision:
                raise Conflict(self.shared())
            entries = self.entries()
            by_id = {e.id: e for e in entries}
            by_url = {e.url: e for e in entries if e.url}
            removed = [r for r in body.get("removed") or [] if isinstance(r, str)]
            seen: list[Entry] = []
            for i, raw in enumerate(items):
                got = entry_from(raw)
                if got is None:
                    raise ValueError("Un complemento no tiene la forma acordada")
                url = raw.get("url") if isinstance(raw, dict) else None
                if isinstance(url, str) and MASK in url:
                    raise ValueError("Una dirección tapada no se puede guardar")
                mine = by_id.get(got.id) or (by_url.get(url) if isinstance(url, str) else None)
                if mine is None:
                    if got.origin != "stremio" or not isinstance(url, str) or not url.startswith("https://"):
                        raise ValueError("No se agregan complementos a mano")
                    if masked(url) != url:
                        raise ValueError("Espera las llaves por aparato: esa dirección lleva una clave")
                    mine = Entry(id=got.id, origin="stremio", name=got.name or host(url), url=url, order=i,
                                 only_on=DEVICE if host(url) in LOCAL_HOSTS else None)
                if mine in seen:
                    continue
                theirs = {k: v for k, v in got.enabled.items() if k != DEVICE}  # el prendido de la TV es de la TV
                mine.enabled = {**mine.enabled, **theirs}
                mine.order = i
                if got.name:
                    mine.name = got.name
                if mine.template == "torrentio" and isinstance(got.options, dict):
                    mine.options = {k: v for k, v in got.options.items() if k in (*torrentio.ORDER, "verbatim")}
                    mine.extra = {**mine.extra, "set_here": True}
                if got.extra:
                    mine.extra = {**mine.extra, **got.extra}
                seen.append(mine)
            # Lo que el otro no mandó (lo que solo vive en la TV) conserva su lugar: va justo después del que lo precedía.
            for k, e in enumerate(entries):
                if e in seen or (e.origin == "stremio" and e.id in removed):
                    continue
                before = next((p for p in reversed(entries[:k]) if p in seen), None)
                seen.insert(seen.index(before) + 1 if before else 0, e)
            for k, e in enumerate(seen):
                e.order = k
            raw_by = body.get("changed_by")
            changed_by = raw_by if isinstance(raw_by, str) else device
            self._save(seen, removed=removed, changed_by=changed_by[:60], source="own")
            return self.shared()

    @staticmethod
    def _find(entries: list[Entry], ident: str) -> Entry:
        found = next((e for e in entries if e.id == ident), None)
        if found is None:
            raise KeyError(ident)
        return found
