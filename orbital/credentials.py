"""Credenciales locales (p. ej. la clave de sesión de Stremio), fuera de config.yaml.

Se guardan en secrets.json junto a config.yaml (en Windows, %APPDATA%\\orbital). En Windows el
contenido va cifrado con DPAPI (solo tu usuario, en este equipo, lo puede leer); un secrets.json
viejo en texto plano se lee igual y se cifra al primer arranque. Nunca se envían a la interfaz
web ni aparecen en los registros.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path

from . import dpapi

log = logging.getLogger(__name__)
FORMAT = "orbital-dpapi-1"


class Credentials:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict = {}
        if path and path.exists():
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as exc:
                log.warning("No se pudo leer %s: %s", path, exc)
                return
            if isinstance(raw, dict) and raw.get("format") == FORMAT:
                plain = dpapi.unprotect(str(raw.get("data") or ""))
                if plain is None:
                    log.warning("No pude descifrar %s (¿otro usuario de Windows u otro equipo?): "
                                "vuelve a conectar Stremio", path)
                    return
                try:
                    data = json.loads(plain)
                except ValueError:
                    data = None
                if not isinstance(data, dict):
                    log.warning("Credenciales ilegibles en %s: vuelve a conectar Stremio", path)
                    return
                self._data = data
            elif isinstance(raw, dict):
                self._data = raw
                if raw and dpapi.available():
                    with self._lock:
                        self._save()  # el archivo viejo en texto plano queda cifrado
                    log.info("Credenciales cifradas con tu usuario de Windows (DPAPI)")

    def get(self, key: str) -> str | None:
        with self._lock:
            return self._data.get(key)

    def set(self, key: str, value: str | list[str] | None) -> None:
        with self._lock:
            if value is None:
                self._data.pop(key, None)
            else:
                self._data[key] = value
            self._save()

    def _save(self) -> None:
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps(self._data, indent=1)
        sealed = dpapi.protect(text) if dpapi.available() else None
        if sealed is not None:
            text = json.dumps({"format": FORMAT, "data": sealed})
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(text, encoding="utf-8")
        if os.name != "nt":
            tmp.chmod(0o600)
        tmp.replace(self.path)
