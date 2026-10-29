"""Estado que Orbital recuerda entre sesiones: historial de juego y preferencias del usuario."""

from __future__ import annotations

import json
import logging
import math
import re
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)


MAX_DISMISSED = 2000  # «No me interesa» guardados (los más viejos se olvidan)
# Lo que se comparte con el iPhone de cada título (lo demás —«Continuar», oculto— es de la TV).
SHARED_PREFS = ("audio", "spanish", "subtitles")
_CHOICE_OK = {"audio": re.compile(r"^[a-z]{2,3}$"), "spanish": re.compile(r"^(es-419|es-ES)?$"),
              "subtitles": re.compile(r"^([a-z]{2,3}|forced)?$")}
MAX_OPENED = 500  # consolas (filas) con su última entrada; las que hace más que no abres se olvidan
_NUMBER = "número"
# Qué tipo lleva cada ajuste: un «abc» en video_idle_minutes impedía arrancar (int("abc")).
SETTING_TYPES = {"audio": str, "dub": str, "subtitles": str, "quality": str, "text_size": str, "sub_scale": _NUMBER,
                 "safe_area": _NUMBER, "game_idle_minutes": _NUMBER, "video_idle_minutes": _NUMBER,
                 "reduce_motion": bool, "sounds": bool, "haptics": bool, "voice_tips": bool, "close_previous": bool,
                 "game_mode": str, "game_resolution": str,
                 "eden_build": str}


def _setting_ok(key, value) -> bool:
    kind = SETTING_TYPES.get(key)
    if kind == _NUMBER:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and 0 <= value <= 10_000
    if kind is not None:
        return type(value) is kind
    return isinstance(value, (str, bool, int, float)) and not (isinstance(value, float) and not math.isfinite(value))


class State:
    """Guarda en un JSON (junto a config.yaml) recientes, tiempo jugado, favoritos, ocultos
    y el emulador preferido de cada juego. Con path=None vive solo en memoria (pruebas)."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path
        self._lock = threading.Lock()
        # "dismissed": sugerencias de «Para ti» que dijiste «No me interesa» (clave → cuándo).
        # "inbox": lo que la TV le manda al iPhone y él aún no recoge (id → pendiente; ver companion.py).
        # "opened": cuándo entraste por última vez a cada consola (fila → cuándo): lo nuevo deja de anunciarse.
        self._data: dict = {"history": {}, "prefs": {}, "settings": {}, "seen": {}, "dismissed": {}, "inbox": {},
                            "opened": {}, "sync": {}, "skipped": {}}
        self._frozen = False  # no se pudo leer el archivo: se vive en memoria y NO se pisa
        if path and path.exists():
            self._load(path)

    def _read(self, path: Path) -> str:
        for attempt in range(3):  # un antivirus o el indexador pueden tenerlo abierto un momento
            try:
                return path.read_text(encoding="utf-8-sig")  # utf-8-sig: el BOM del Bloc de notas no lo invalida
            except OSError:
                if attempt == 2:
                    raise
                time.sleep(.2)
        return ""

    def _load(self, path: Path) -> None:
        try:
            text = self._read(path)
        except UnicodeDecodeError:
            text = ""  # no es UTF-8 (PowerShell lo guardó en UTF-16, el Bloc de notas en ANSI): cuenta como dañado
        except OSError as exc:
            # Sigue ahí pero no se deja leer: guardar encima borraría favoritos y tiempo jugado.
            self._frozen = True
            log.warning("No pude leer %s; esta sesión no lo modifica: %s", path, exc)
            return
        try:
            loaded = json.loads(text)
            if not isinstance(loaded, dict):
                raise ValueError("no es un objeto")
        except (ValueError, RecursionError) as exc:
            # Dañado: queda a salvo con fecha (otro daño después no pisa este respaldo) y se empieza de cero.
            backup = path.with_name(f"{path.stem}-{time.strftime('%Y%m%d-%H%M%S')}.bak")
            try:
                path.replace(backup)
            except OSError:
                self._frozen, backup = True, path
            log.warning("No se pudo leer %s (queda en %s); empiezo de cero: %s", path, backup, exc)
            return
        for key in self._data:
            value = loaded.get(key, {})
            self._data[key] = dict(value) if isinstance(value, dict) else {}
        # Cada entrada con la forma esperada: números donde van números (un "abc" no tumba el orden).
        number = lambda v: v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0 else 0  # noqa: E731
        history = {}
        for k, v in self._data["history"].items():
            if isinstance(v, dict):
                history[k] = {**v, **{f: number(v.get(f)) for f in ("playtime", "launches", "last_played") if f in v}}
        self._data["history"] = history
        self._data["prefs"] = {k: v for k, v in self._data["prefs"].items() if isinstance(v, dict)}
        self._data["seen"] = {k: number(v) for k, v in self._data["seen"].items()}
        self._data["dismissed"] = {k: number(v) for k, v in self._data["dismissed"].items()}
        self._data["skipped"] = {k: number(v) for k, v in self._data["skipped"].items()}
        self._data["settings"] = {k: v for k, v in self._data["settings"].items() if _setting_ok(k, v)}
        self._data["inbox"] = {k: v for k, v in self._data["inbox"].items() if isinstance(v, dict) and v.get("action") in ("open", "download")}
        rev = self._data["sync"].get("rev")
        self._data["sync"] = {"rev": rev if isinstance(rev, int) and not isinstance(rev, bool) and rev >= 0 else 0}

    def _save(self) -> None:
        """Escritura atómica (no se corrompe si se apaga la consola). Si Windows no deja escribir (un
        antivirus o el indexador tienen el archivo), se reintenta y, si no, se avisa en el registro: nunca
        tumba lo que se estaba haciendo (abrir un juego, cerrarlo)."""
        if not self.path or self._frozen:
            return
        for attempt in range(3):
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                tmp = self.path.with_suffix(".tmp")
                tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=1), encoding="utf-8", errors="replace")
                tmp.replace(self.path)
                return
            except OSError as exc:
                if attempt == 2:
                    log.warning("No pude guardar %s: %s", self.path, exc)
                    return
                time.sleep(.15)

    # --- historial -----------------------------------------------------------
    def record_launch(self, item_id: str, now: float | None = None) -> dict | None:
        """Anota que se abrió; devuelve cómo estaba antes (None = nunca), para deshacerlo si se cancela."""
        with self._lock:
            before = self._data["history"].get(item_id)
            before = dict(before) if isinstance(before, dict) else None
            entry = self._data["history"].setdefault(item_id, {"playtime": 0, "launches": 0})
            entry["last_played"] = now or time.time()
            entry["launches"] = int(entry.get("launches") or 0) + 1
            self._save()
            return before

    def undo_launch(self, item_id: str, before: dict | None) -> None:
        """Cancelaste en la pantalla de carga: el historial vuelve a como estaba (no cuenta como jugado)."""
        with self._lock:
            if before is None:
                self._data["history"].pop(item_id, None)
            else:
                self._data["history"][item_id] = dict(before)
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

    def mark_opened(self, row_id: str, now: float | None = None) -> None:
        """Entraste a esa consola: lo que llegó antes ya no cuenta como «nuevo» en su tarjeta."""
        with self._lock:
            opened = self._data["opened"]
            key = row_id[:80]
            opened.pop(key, None)
            opened[key] = now or time.time()  # al final: las más viejas se van primero
            while len(opened) > MAX_OPENED:  # cada fila nueva (búsquedas, colecciones) sumaba para siempre
                del opened[next(iter(opened))]
            self._save()

    def opened(self, row_id: str) -> float:
        with self._lock:
            return self._data["opened"].get(row_id, 0)

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

    def _set_pref_unlocked(self, item_id: str, key: str, value) -> None:
        prefs = self._data["prefs"].setdefault(item_id, {})
        changed = prefs.get(key) != value
        if value is None:
            prefs.pop(key, None)
        else:
            prefs[key] = value
        if changed and key in SHARED_PREFS and item_id.startswith("stremio:"):
            prefs["rev"] = self._bump()  # el iPhone lo recibe en su siguiente sincronización
        if not prefs:
            self._data["prefs"].pop(item_id)

    def set_pref(self, item_id: str, key: str, value) -> None:
        with self._lock:
            self._set_pref_unlocked(item_id, key, value)
            self._save()

    def set_pref_on(self, item_ids: list[str], key: str, value) -> None:
        """La misma preferencia en varias claves (el emulador: title ID, título, huella y ruta)."""
        with self._lock:
            for item_id in item_ids:
                self._set_pref_unlocked(item_id, key, value)
            self._save()

    def migrate_runner_prefs(self, item_keys: list[tuple[str, list[str]]]) -> int:
        """Copia prefs[ruta].runner a cada clave estable que aún no tenga emulador.

        No borra las entradas viejas. Idempotente. Devuelve cuántas copias hizo.
        """
        copied = 0
        with self._lock:
            prefs = self._data["prefs"]
            for item_id, keys in item_keys:
                old = prefs.get(item_id, {}).get("runner")
                if not old:
                    continue
                for key in keys:
                    if key == item_id:
                        continue
                    slot = prefs.setdefault(key, {})
                    if not slot.get("runner"):
                        slot["runner"] = old
                        copied += 1
            if copied:
                self._save()
        return copied

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

    # --- «Para ti»: lo que no te interesa ----------------------------------------
    def dismiss(self, key: str, now: float | None = None) -> None:
        with self._lock:
            dismissed = self._data["dismissed"]
            dismissed[key] = now or time.time()
            if len(dismissed) > MAX_DISMISSED:  # cada «No me interesa» reescribe state.json entero
                for old in sorted(dismissed, key=dismissed.get)[:len(dismissed) - MAX_DISMISSED]:
                    del dismissed[old]
            self._save()

    # --- «Hoy no» de ¿Qué vemos?: no vuelve a proponerse en unas horas (ni tras reiniciar Orbital) -------------
    def skip_today(self, imdb: str, now: float | None = None) -> None:
        with self._lock:
            self._data["skipped"][imdb] = now or time.time()
            self._save()

    def skipped(self, max_age: float, now: float | None = None) -> set[str]:
        """Lo que dijiste «Hoy no» hace menos de `max_age` segundos (lo viejo se olvida aquí mismo)."""
        stamp = now or time.time()
        with self._lock:
            skipped = self._data["skipped"]
            old = [k for k, v in skipped.items() if stamp - v >= max_age]
            for k in old:
                del skipped[k]
            if old:
                self._save()
            return set(skipped)

    # --- elecciones compartidas con el iPhone (audio, variante, subtítulos de cada título) ---------------
    def _bump(self) -> int:
        sync = self._data["sync"]
        sync["rev"] = int(sync.get("rev") or 0) + 1
        return sync["rev"]

    def choices_since(self, since: int, limit: int = 500) -> tuple[int, dict]:
        """Lo que cambió en la TV después de `since` (0: todo lo que hay). {meta_id: {audio, spanish, subtitles, rev}}."""
        with self._lock:
            out = {}
            for item_id, prefs in self._data["prefs"].items():
                rev = prefs.get("rev") if isinstance(prefs.get("rev"), int) else 0
                if not item_id.startswith("stremio:"):
                    continue
                has = any(isinstance(prefs.get(k), str) for k in SHARED_PREFS)
                # Uno olvidado («Olvidar») viaja sin campos: el iPhone también lo olvida.
                if (since == 0 and has) or (since > 0 and rev > since):
                    out[item_id.split(":", 1)[1]] = {**{k: prefs[k] for k in SHARED_PREFS if isinstance(prefs.get(k), str)}, "rev": rev}
            items = sorted(out.items(), key=lambda kv: kv[1]["rev"])[-limit:]
            return int(self._data["sync"].get("rev") or 0), dict(items)

    def apply_choice(self, meta_id: str, fields: dict, base_rev: int) -> bool:
        """Lo que eligió el iPhone para un título. False si la TV lo cambió después de lo último que el iPhone vio (gana
        la TV: el iPhone recibe su valor). Solo los campos compartidos y con valores válidos; un campo en None se olvida."""
        valid = {k: v for k, v in fields.items() if k in SHARED_PREFS and (v is None or (isinstance(v, str) and _CHOICE_OK[k].match(v)))}
        if not valid:
            return True
        with self._lock:
            item_id = f"stremio:{meta_id}"
            prefs = self._data["prefs"].get(item_id, {})
            if (prefs.get("rev") or 0) > base_rev:
                return False
            prefs = self._data["prefs"].setdefault(item_id, {})
            for key, value in valid.items():
                if value is None:
                    prefs.pop(key, None)
                else:
                    prefs[key] = value
            prefs["rev"] = self._bump()
            self._save()
            return True

    def forget_choices(self, meta_id: str) -> None:
        """«Lo que recuerda cada título» › Olvidar: vuelve a lo de Ajustes (y el iPhone se entera)."""
        with self._lock:
            prefs = self._data["prefs"].get(f"stremio:{meta_id}")
            if not prefs:
                return
            for key in SHARED_PREFS:
                prefs.pop(key, None)
            prefs["rev"] = self._bump()
            self._save()

    def remembered_titles(self) -> list[tuple[str, dict]]:
        """Los títulos con audio o subtítulos propios (para Ajustes), del más reciente al más viejo."""
        with self._lock:
            rows = [(k.split(":", 1)[1], {key: v[key] for key in SHARED_PREFS if isinstance(v.get(key), str)}, v.get("rev") or 0)
                    for k, v in self._data["prefs"].items() if k.startswith("stremio:") and any(isinstance(v.get(x), str) for x in SHARED_PREFS)]
            return [(m, f) for m, f, _ in sorted(rows, key=lambda r: r[2], reverse=True)]

    def dismissed(self) -> set[str]:
        with self._lock:
            return set(self._data["dismissed"])

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

    # --- bandeja para el iPhone (lo que la TV le manda: «Enviar» y «Descargar en el iPhone») ----------
    def inbox(self) -> list[dict]:
        """Los pendientes, del más viejo al más nuevo."""
        with self._lock:
            return [dict(v) for v in self._data["inbox"].values()]

    def inbox_add(self, item: dict, limit: int) -> dict:
        """Anota un pendiente. El mismo título con la misma acción, aún pendiente, no se repite (se devuelve el que ya estaba).
        Pasado el tope se van los más viejos."""
        with self._lock:
            for old in self._data["inbox"].values():
                if (old.get("meta_id"), old.get("video_id"), old.get("action")) == (item.get("meta_id"), item.get("video_id"), item.get("action")):
                    return dict(old)
            self._data["inbox"][item["id"]] = dict(item)
            while len(self._data["inbox"]) > limit:
                del self._data["inbox"][next(iter(self._data["inbox"]))]
            self._save()
            return dict(item)

    def inbox_ack(self, ids: list[str]) -> int:
        with self._lock:
            gone = [i for i in ids if self._data["inbox"].pop(i, None) is not None]
            if gone:
                self._save()
            return len(gone)
