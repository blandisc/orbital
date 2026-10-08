"""Credenciales locales (p. ej. la clave de sesión de Stremio), fuera de config.yaml.

Se guardan en secrets.json junto a config.yaml (en Windows, %APPDATA%\\orbital, que solo tu
usuario puede leer). Nunca se envían a la interfaz web ni aparecen en los registros.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path

log = logging.getLogger(__name__)


class Credentials:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict = {}
        if path and path.exists():
            try:
                self._data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as exc:
                log.warning("No se pudo leer %s: %s", path, exc)

    def get(self, key: str) -> str | None:
        with self._lock:
            return self._data.get(key)

    def set(self, key: str, value: str | None) -> None:
        with self._lock:
            if value is None:
                self._data.pop(key, None)
            else:
                self._data[key] = value
            if not self.path:
                return
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._data, indent=1), encoding="utf-8")
            if os.name != "nt":
                tmp.chmod(0o600)
            tmp.replace(self.path)
