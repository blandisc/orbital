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
        self._data: dict = {"history": {}, "prefs": {}, "settings": {}, "seen": {}}
        if path and path.exists():
            try:
                # utf-8-sig: si alguien lo abrió en el Bloc de notas, el BOM no lo invalida.
                loaded = json.loads(path.read_text(encoding="utf-8-sig"))
                if not isinstance(loaded, dict):
                    raise ValueError("no es un objeto")
                for key in self._data:
                    value = loaded.get(key, {})
                    self._data[key] = dict(value) if isinstance(value, dict) else {}
                # Cada entrada del historial y de preferencias, con la forma esperada.
                self._data["history"] = {k: v for k, v in self._data["history"].items() if isinstance(v, dict)}
                self._data["prefs"] = {k: v for k, v in self._data["prefs"].items() if isinstance(v, dict)}
            except (OSError, ValueError) as exc:
                # Antes se empezaba de cero y el primer guardado borraba favoritos y tiempo jugado:
                # ahora el archivo que no se pudo leer queda a salvo como .bak.
                backup = path.with_suffix(".bak")
                try:
                    path.replace(backup)
                except OSError:
                    backup = path
                log.warning("No se pudo leer %s (queda en %s); empiezo de cero: %s", path, backup, exc)

    def _save(self) -> None:
        """Escritura atómica (no se corrompe si se apaga la consola). Si Windows no deja escribir (un
        antivirus o el indexador tienen el archivo), se reintenta y, si no, se avisa en el registro: nunca
        tumba lo que se estaba haciendo (abrir un juego, cerrarlo)."""
        if not self.path:
            return
        for attempt in range(3):
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                tmp = self.path.with_suffix(".tmp")
                tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=1), encoding="utf-8")
                tmp.replace(self.path)
                return
            except OSError as exc:
                if attempt == 2:
                    log.warning("No pude guardar %s: %s", self.path, exc)
                    return
                time.sleep(.15)

    # --- historial -----------------------------------------------------------
    def record_launch(self, item_id: str, now: float | None = None) -> None:
        with self._lock:
            entry = self._data["history"].setdefault(item_id, {"playtime": 0, "launches": 0})
            entry["last_played"] = now or time.time()
            entry["launches"] = int(entry.get("launches") or 0) + 1
            self._save()

    def record_session(self, item_id: str, seconds: float) -> None:
        # Sesiones de menos de 10 s suelen ser un emulador que falló al abrir: no cuentan.
        if seconds < 10:
            return
        with self._lock:
            entry = self._data["history"].setdefault(item_id, {"playtime": 0, "launches": 0})
            entry["playtime"] = int((entry.get("playtime") if isinstance(entry.get("playtime"), (int, float)) else 0) + seconds)
            self._save()

    # --- juegos nuevos -------------------------------------------------------
    def mark_seen(self, item_ids: list[str], now: float | None = None) -> None:
        """Anota cuándo apareció cada juego por primera vez. La primera vez que corre no hay nada
        «nuevo»: todo lo que ya tenías cuenta como visto desde siempre."""
        with self._lock:
            seen = self._data["seen"]
            first_run = not seen
            fresh = [i for i in item_ids if i not in seen]
            if not fresh:
                return
            for item_id in fresh:
                seen[item_id] = 0 if first_run else (now or time.time())
            self._save()

    def first_seen(self, item_id: str) -> float | None:
        with self._lock:
            return self._data["seen"].get(item_id)

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

    # --- ajustes (pantalla de Ajustes de Orbital) ------------------------------
    def settings(self) -> dict:
        with self._lock:
            return dict(self._data["settings"])

    def set_setting(self, key: str, value) -> None:
        """`None` vuelve al valor por defecto (el de config.yaml o el de la interfaz)."""
        with self._lock:
            if value is None:
                self._data["settings"].pop(key, None)
            else:
                self._data["settings"][key] = value
            self._save()
