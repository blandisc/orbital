"""Complementos de Stremio (addons): el protocolo, sin depender de la app ni de la cuenta.

Un complemento es un servidor HTTP que responde JSON en rutas fijas; su manifiesto dice qué da:

  GET {base}/manifest.json                     -> {"name", "resources", "types", "idPrefixes", "catalogs"}
  GET {base}/catalog/{tipo}/{id}.json          -> {"metas": [...]}
  GET {base}/meta/{tipo}/{id}.json             -> {"meta": {...}}
  GET {base}/stream/{tipo}/{video}.json        -> {"streams": [...]}
  GET {base}/subtitles/{tipo}/{video}.json     -> {"subtitles": [...]}

Orbital junta los de tu cuenta de Stremio (en su orden, como Stremio) y los tuyos (`orbital stremio
addon add <url>`: se guardan cifrados, porque su URL suele llevar claves), y a cada pregunta le contesta el complemento que la sabe responder: por recurso,
tipo y prefijo de id (un id `kitsu:` no se le pregunta a quien solo sabe de IMDb). Con tu lista propia («La TV sin
Stremio», S1: addon_list.py) ya no se le pregunta nada a tu cuenta.

Cada complemento lleva su salud (`Health`): cuánto tardó la última vez y, si falla dos veces seguidas, se salta y se
vuelve a probar con espera creciente hasta una hora (C1 y C2 del iPhone). Un manifiesto que ya contestó se guarda en
disco: si el complemento no responde al arrancar, se usa el guardado.
"""

from __future__ import annotations

import hashlib
import json
import logging
import threading
import time
import urllib.request
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

from ..net import NET_ERRORS, read_json
from .stremio_api import StremioError

log = logging.getLogger(__name__)

CACHE_SECONDS = 600
RETRY_FAILED = 15  # s que se recuerda una lista incompleta por un error de red
REQUEST_TIMEOUT = 15
RESOURCES = ("catalog", "meta", "stream", "subtitles")
SKIP_AFTER = 2  # fallos seguidos para dejar de esperarlo (C2)
RETRY_BASE = 60.0  # s: la primera espera; se duplica hasta RETRY_MAX
RETRY_MAX = 3600.0
SLOW_SECONDS = 3.0  # «Contesta lento · 4,2 s» desde aquí


class Health:
    """Cómo le ha ido a cada complemento (por su dirección): lo que tardó la última vez que contestó y, si falla, desde
    cuándo. Tras SKIP_AFTER fallos seguidos se salta (`skip`) hasta su próximo intento, con espera creciente."""

    def __init__(self, clock: Callable[[], float] = time.time) -> None:
        self.clock = clock
        self._data: dict[str, dict] = {}
        self._lock = threading.Lock()

    def ok(self, url: str, seconds: float) -> None:
        with self._lock:
            self._data[url] = {"seconds": round(max(0.0, seconds), 2), "at": self.clock()}

    def fail(self, url: str) -> None:
        with self._lock:
            now = self.clock()
            last = self._data.get(url, {})
            fails = int(last.get("fails", 0)) + 1
            wait = min(RETRY_MAX, RETRY_BASE * 2 ** (fails - SKIP_AFTER)) if fails >= SKIP_AFTER else 0.0
            self._data[url] = {**last, "fails": fails, "since": last.get("since") or now, "retry": now + wait}

    def skip(self, url: str) -> bool:
        with self._lock:
            state = self._data.get(url, {})
            return int(state.get("fails", 0)) >= SKIP_AFTER and self.clock() < float(state.get("retry", 0))

    def status(self, url: str) -> dict:
        """{"state": "ok" | "slow" | "down" | "unknown", "seconds"?, "since"?}: lo que dice Ajustes › Complementos."""
        with self._lock:
            state = dict(self._data.get(url, {}))
        if state.get("fails"):
            return {"state": "down", "since": state.get("since"), "skipped": int(state["fails"]) >= SKIP_AFTER}
        if "seconds" in state:
            return {"state": "slow" if state["seconds"] >= SLOW_SECONDS else "ok", "seconds": state["seconds"]}
        return {"state": "unknown"}


def fetch_json(url: str, timeout: float = REQUEST_TIMEOUT) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "Orbital"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        data = read_json(res, timeout=timeout)
    return data if isinstance(data, dict) else {}


def redact(url: str) -> str:
    """Para los registros: solo el servidor. La ruta de un complemento configurado lleva tus claves
    (Real-Debrid en Torrentio, p. ej.)."""
    rest = url.split("://", 1)[-1]
    return rest.split("/", 1)[0] or "?"


def manifest_url(url: str) -> str | None:
    """La URL del manifiesto tal como la pegarías: con o sin /manifest.json, o el enlace stremio:// de
    «Instalar». Solo http(s): un complemento no puede apuntar a un archivo local."""
    url = url.strip()
    if url.lower().startswith("stremio://"):
        url = "https://" + url[len("stremio://"):]
    if not url.lower().startswith(("http://", "https://")):
        return None
    return url if url.endswith("/manifest.json") else url.rstrip("/") + "/manifest.json"


@dataclass
class Rule:
    types: list[str]  # vacío = cualquier tipo
    id_prefixes: list[str] | None  # None = cualquier id


@dataclass
class Addon:
    name: str
    url: str  # transportUrl: …/manifest.json
    rules: dict[str, Rule] = field(default_factory=dict)  # recurso -> qué tipos e ids atiende
    catalogs: list[dict] = field(default_factory=list)

    @property
    def base(self) -> str:
        return self.url.rsplit("/manifest.json", 1)[0]

    @property
    def resources(self) -> list[str]:
        return list(self.rules)

    def handles(self, resource: str, kind: str, item_id: str | None = None) -> bool:
        rule = self.rules.get(resource)
        if rule is None or (rule.types and kind not in rule.types):
            return False
        return item_id is None or rule.id_prefixes is None or item_id.startswith(tuple(rule.id_prefixes))


def _texts(value) -> list[str]:
    return [v for v in value if isinstance(v, str) and v] if isinstance(value, list) else []


def parse_manifest(manifest, url) -> Addon | None:
    """Un complemento a partir de su manifiesto; None si no sirve (manifiesto raro, sin recursos
    que Orbital use o una URL que no es http)."""
    if not isinstance(manifest, dict) or not isinstance(url, str) or not url.startswith(("http://", "https://")):
        return None
    types = _texts(manifest.get("types"))
    prefixes = _texts(manifest.get("idPrefixes")) or None  # sin prefijos (o lista vacía): cualquier id
    rules: dict[str, Rule] = {}
    listed = manifest.get("resources")
    for resource in listed if isinstance(listed, list) else []:
        # Un recurso es un nombre o {"name", "types", "idPrefixes"} con reglas propias.
        if isinstance(resource, str):
            name, own = resource, {}
        elif isinstance(resource, dict) and isinstance(resource.get("name"), str):
            name, own = resource["name"], resource
        else:
            continue
        if name in RESOURCES:
            rules[name] = Rule(types=_texts(own.get("types")) or types,
                               id_prefixes=_texts(own.get("idPrefixes")) or prefixes)
    if not rules:
        return None
    name = manifest.get("name")
    catalogs = [c for c in manifest.get("catalogs") or [] if isinstance(c, dict)] \
        if isinstance(manifest.get("catalogs"), list) else []
    return Addon(name=name if isinstance(name, str) and name.strip() else "Addon", url=url, rules=rules,
                 catalogs=catalogs)


def _slot(url: str) -> str:
    """Dónde se guarda el manifiesto de una dirección (su huella: la dirección lleva claves y no se escribe tal cual)."""
    return hashlib.sha256(url.encode()).hexdigest()[:24]


def clean_urls(value) -> list[str]:
    """Las URLs de tus complementos, normalizadas y sin repetir (lo que no es una URL se ignora)."""
    listed = [value] if isinstance(value, str) else value if isinstance(value, list) else []
    return list(dict.fromkeys(u for u in (manifest_url(x) for x in listed if isinstance(x, str)) if u))


class AddonRegistry:
    """Tus complementos, en orden: primero los de tu cuenta de Stremio, luego los tuyos.

    `account` es el cliente de api.strem.io y `auth` da la clave de sesión (None = sin cuenta: solo
    los tuyos); `own` da las URLs de los tuyos. La lista se recuerda unos minutos y se vuelve a armar
    si cambia la cuenta o agregas o quitas uno."""

    def __init__(self, account=None, auth: Callable[[], str | None] = lambda: None,
                 own: Callable[[], Iterable[str]] = lambda: (), timeout: float = REQUEST_TIMEOUT,
                 listing=None, manifests: Path | None = None) -> None:
        self.account = account
        self.auth = auth
        self.own = own
        self.timeout = timeout
        self.listing = listing  # addon_list.AddonList: con `source` «own», la lista sale de ahí y no de la cuenta
        self.health = Health()
        self.manifests = manifests  # archivo donde se guardan los manifiestos que ya contestaron
        self._cache: tuple[float, tuple, list[Addon]] = (0.0, (), [])
        self._lock = threading.Lock()
        self._loading = threading.Lock()

    @property
    def own_list(self) -> bool:
        """Las fuentes salen de tu lista de Orbital (no de tu cuenta de Stremio)."""
        return self.listing is not None and self.listing.source == "own"

    @property
    def local(self) -> list[str]:
        if self.own_list:
            return clean_urls(self.listing.urls())
        return clean_urls(list(self.own()))

    def _key(self) -> tuple:
        return (None if self.own_list else self.auth(), tuple(self.local))

    def forget(self) -> None:
        """La lista cambió (prendiste, quitaste, trajiste): la próxima pregunta la vuelve a armar."""
        with self._lock:
            self._cache = (0.0, (), [])

    def _saved(self) -> dict:
        if not self.manifests:
            return {}
        try:
            data = json.loads(self.manifests.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}

    def _save_manifests(self, fresh: dict[str, dict]) -> None:
        if not self.manifests or not fresh:
            return
        try:
            self.manifests.parent.mkdir(parents=True, exist_ok=True)
            self.manifests.write_text(json.dumps({**self._saved(), **fresh}, ensure_ascii=False), encoding="utf-8")
        except OSError as exc:
            log.info("No pude guardar los manifiestos: %s", exc)

    def _manifest(self, url: str) -> tuple[dict | None, bool]:
        """El manifiesto de un complemento y si contestó; sin respuesta, el guardado (si lo hay)."""
        started = time.monotonic()
        try:
            data = fetch_json(url, self.timeout)
        except NET_ERRORS as exc:
            log.info("No pude leer el complemento de %s: %s", redact(url), exc)
            self.health.fail(url)
            return self._saved().get(_slot(url)), False
        self.health.ok(url, time.monotonic() - started)
        return data, True

    def _fresh(self) -> list[Addon] | None:
        stamp, key, found = self._cache
        return found if key == self._key() and time.time() - stamp < CACHE_SECONDS else None

    def addons(self) -> list[Addon]:
        """Pide la lista si hace falta (bloquea). Sin cuenta que responda y sin complementos propios,
        lanza el error de la cuenta (la interfaz lo muestra como hasta ahora)."""
        with self._lock:
            if (hit := self._fresh()) is not None:
                return hit
            key = self._key()
            found, failed, error = self._from_account(key[0])
            wanted = [u for u in key[1] if not any(a.url == u for a in found)]
            # En paralelo: un complemento colgado no hace esperar a los demás uno tras otro.
            with ThreadPoolExecutor(max_workers=max(1, min(8, len(wanted)))) as pool:
                answers = list(pool.map(self._manifest, wanted))
            fresh = {}
            for url, (manifest, answered) in zip(wanted, answers, strict=True):
                failed = failed or not answered
                addon = parse_manifest(manifest, url)
                if addon:
                    found.append(addon)
                    if answered:
                        fresh[_slot(url)] = manifest
                elif answered:
                    log.warning("Complemento sin nada que Orbital use (%s)", redact(url))
            self._save_manifests(fresh)
            if error and not found:
                raise error
            # Si algo no respondió (Wi-Fi al despertar), la lista se recuerda solo unos segundos.
            self._cache = (time.time() - (CACHE_SECONDS - RETRY_FAILED if failed else 0), key, found)
            return found

    def _from_account(self, key: str | None) -> tuple[list[Addon], bool, Exception | None]:
        if not key or self.account is None:
            return [], False, None
        try:
            result = self.account.request("addonCollectionGet", {"authKey": key, "update": True})
        except StremioError as exc:
            log.info("Sin los complementos de tu cuenta: %s", exc)
            return [], True, exc
        raw = result.get("addons") if isinstance(result, dict) else None
        found = []
        for item in raw if isinstance(raw, list) else []:
            # Un complemento con el manifiesto raro se salta; no deja sin fuentes a los demás.
            if isinstance(item, dict) and (addon := parse_manifest(item.get("manifest"), item.get("transportUrl"))):
                found.append(addon)
        return found, False, None

    def known(self) -> list[Addon]:
        """Los que ya se conocen, sin esperar a la red: si la lista caducó, se pide en segundo plano.
        Para lo que no puede quedarse esperando a la cuenta (las fichas)."""
        stamp, key, found = self._cache
        if self._fresh() is None and self._loading.acquire(blocking=False):
            def load() -> None:
                try:
                    self.addons()
                except Exception as exc:  # noqa: BLE001 - en segundo plano solo se registra
                    log.info("Complementos: %s", exc)
                finally:
                    self._loading.release()

            threading.Thread(target=load, daemon=True, name="addons").start()
        return found if key == self._key() else []

    def serving(self, resource: str, kind: str, item_id: str | None = None) -> list[Addon]:
        return [a for a in self.addons() if a.handles(resource, kind, item_id)]
