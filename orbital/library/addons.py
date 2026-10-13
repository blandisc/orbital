"""Complementos de Stremio (addons): el protocolo, sin depender de la app ni de la cuenta.

Un complemento es un servidor HTTP que responde JSON en rutas fijas; su manifiesto dice qué da:

  GET {base}/manifest.json                     -> {"name", "resources", "types", "idPrefixes", "catalogs"}
  GET {base}/catalog/{tipo}/{id}.json          -> {"metas": [...]}
  GET {base}/meta/{tipo}/{id}.json             -> {"meta": {...}}
  GET {base}/stream/{tipo}/{video}.json        -> {"streams": [...]}
  GET {base}/subtitles/{tipo}/{video}.json     -> {"subtitles": [...]}

Orbital junta los de tu cuenta de Stremio (en su orden, como Stremio) y los tuyos (`orbital stremio
addon add <url>`: se guardan cifrados, porque su URL suele llevar claves), y a cada pregunta le contesta el complemento que la sabe responder: por recurso,
tipo y prefijo de id (un id `kitsu:` no se le pregunta a quien solo sabe de IMDb).
"""

from __future__ import annotations

import logging
import threading
import time
import urllib.request
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field

from ..net import NET_ERRORS, read_json
from .stremio_api import StremioError

log = logging.getLogger(__name__)

CACHE_SECONDS = 600
RETRY_FAILED = 15  # s que se recuerda una lista incompleta por un error de red
REQUEST_TIMEOUT = 15
RESOURCES = ("catalog", "meta", "stream", "subtitles")


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
                 own: Callable[[], Iterable[str]] = lambda: (), timeout: float = REQUEST_TIMEOUT) -> None:
        self.account = account
        self.auth = auth
        self.own = own
        self.timeout = timeout
        self._cache: tuple[float, tuple, list[Addon]] = (0.0, (), [])
        self._lock = threading.Lock()
        self._loading = threading.Lock()

    @property
    def local(self) -> list[str]:
        return clean_urls(list(self.own()))

    def _key(self) -> tuple:
        return (self.auth(), tuple(self.local))

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
            for url in key[1]:
                if any(a.url == url for a in found):
                    continue
                try:
                    addon = parse_manifest(fetch_json(url, self.timeout), url)
                except NET_ERRORS as exc:
                    log.info("No pude leer el complemento de %s: %s", redact(url), exc)
                    failed = True
                    continue
                if addon:
                    found.append(addon)
                else:
                    log.warning("Complemento sin nada que Orbital use (%s)", redact(url))
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
