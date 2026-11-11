"""Credenciales locales (p. ej. la clave de sesión de Stremio), fuera de config.yaml.

Se guardan en secrets.json junto a config.yaml (en Windows, %APPDATA%\\orbital). En Windows el
contenido va cifrado con DPAPI (solo tu usuario, en este equipo, lo puede leer); un secrets.json
viejo en texto plano se lee igual y se cifra al primer arranque. Nunca se envían a la interfaz
web ni aparecen en los registros.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path

from . import dpapi
from .atomic import atomic_write, backup_path

log = logging.getLogger(__name__)
FORMAT = "orbital-dpapi-1"


class Credentials:
    def __init__(self, path: Path | None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict = {}
        self._unreadable = False  # no se pudo leer: antes de escribir encima se respalda (AD-15)
        if path and path.exists():
            data, raw = self._read(path)
            if data is None:
                recovered, _ = self._read(backup_path(path)) if backup_path(path).exists() else (None, None)
                if recovered is None:
                    self._unreadable = True
                    return
                # El principal está dañado pero la copia de la vez anterior sirve: se usa y el dañado se respalda.
                log.warning("Recuperé las claves de %s", backup_path(path))
                self._data, self._unreadable = recovered, True
                with self._lock:
                    self._save()
                return
            self._data = data
            if raw is not None and data and dpapi.available():
                with self._lock:
                    self._save()  # el archivo viejo en texto plano queda cifrado
                log.info("Credenciales cifradas con tu usuario de Windows (DPAPI)")

    @staticmethod
    def _read(path: Path) -> tuple[dict | None, dict | None]:
        """(claves, None) si venía cifrado; (claves, crudo) si venía en texto plano; (None, None) si no se pudo."""
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            log.warning("No se pudo leer %s: %s", path, exc)
            return None, None
        if isinstance(raw, dict) and raw.get("format") == FORMAT:
            plain = dpapi.unprotect(str(raw.get("data") or ""))
            if plain is None:
                log.warning("No pude descifrar %s (¿otro usuario de Windows u otro equipo?): "
                            "vuelve a conectar Stremio", path)
                return None, None
            try:
                data = json.loads(plain)
            except ValueError:
                data = None
            if not isinstance(data, dict):
                log.warning("Credenciales ilegibles en %s: vuelve a conectar Stremio", path)
                return None, None
            return data, None
        if isinstance(raw, dict):
            return raw, raw
        log.warning("No se pudo leer %s: no es un objeto", path)
        return None, None

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
        if self._unreadable and self.path.exists():  # lo que no se pudo descifrar no se pierde: queda respaldado
            backup = self.path.with_name(f"{self.path.stem}.ilegible-{int(time.time())}{self.path.suffix}")
            try:
                self.path.replace(backup)
                log.warning("Respaldé las claves que no pude leer en %s", backup)
            except OSError as exc:
                log.warning("No pude respaldar %s: %s; no escribo encima", self.path, exc)
                return
            self._unreadable = False
        text = json.dumps(self._data, indent=1)
        sealed = dpapi.protect(text) if dpapi.available() else None
        if sealed is not None:
            text = json.dumps({"format": FORMAT, "data": sealed})
        atomic_write(self.path, text, backup=True, mode=0o600)  # la copia anterior queda en secrets.json.bak
