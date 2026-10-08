"""Estado que Orbital recuerda entre sesiones: historial de juego y preferencias del usuario."""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)


class State:
    """Guarda en un JSON (junto a config.yaml) recientes, tiempo jugado, favoritos, ocultos
    y el emulador preferido de cada juego. Con path=None vive solo en memoria (pruebas)."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._data: dict = {"history": {}, "prefs": {}}
        if path and path.exists():
            try:
                loaded = json.loads(path.read_text(encoding="utf-8"))
                self._data["history"] = dict(loaded.get("history", {}))
                self._data["prefs"] = dict(loaded.get("prefs", {}))
            except (OSError, ValueError) as exc:
                log.warning("No se pudo leer %s, empiezo de cero: %s", path, exc)

    def _save(self) -> None:
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(self.path)  # escritura atómica: no se corrompe si se apaga la consola

    # --- historial -----------------------------------------------------------
    def record_launch(self, item_id: str, now: float | None = None) -> None:
        with self._lock:
            entry = self._data["history"].setdefault(item_id, {"playtime": 0, "launches": 0})
            entry["last_played"] = now or time.time()
            entry["launches"] += 1
            self._save()

    def record_session(self, item_id: str, seconds: float) -> None:
        # Sesiones de menos de 10 s suelen ser un emulador que falló al abrir: no cuentan.
        if seconds < 10:
            return
        with self._lock:
            entry = self._data["history"].setdefault(item_id, {"playtime": 0, "launches": 0})
            entry["playtime"] = int(entry.get("playtime", 0) + seconds)
            self._save()

    def history(self, item_id: str) -> dict:
        with self._lock:
            return dict(self._data["history"].get(item_id, {}))

    def recent(self, limit: int = 15) -> list[str]:
        with self._lock:
            entries = [(v.get("last_played", 0), k) for k, v in self._data["history"].items()]
        return [k for _, k in sorted(entries, reverse=True)[:limit]]

    # --- preferencias --------------------------------------------------------
    def prefs(self, item_id: str) -> dict:
        with self._lock:
            return dict(self._data["prefs"].get(item_id, {}))

    def set_pref(self, item_id: str, key: str, value) -> None:
        with self._lock:
            prefs = self._data["prefs"].setdefault(item_id, {})
            if value is None:
                prefs.pop(key, None)
            else:
                prefs[key] = value
            if not prefs:
                self._data["prefs"].pop(item_id)
            self._save()

    def unhide_all(self) -> int:
        with self._lock:
            count = 0
            for item_id in list(self._data["prefs"]):
                if self._data["prefs"][item_id].pop("hidden", None):
                    count += 1
                if not self._data["prefs"][item_id]:
                    del self._data["prefs"][item_id]
            self._save()
            return count
