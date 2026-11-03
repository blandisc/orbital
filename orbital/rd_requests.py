"""Pedidos a Real-Debrid: lo que todavía no tiene se le pide, se sigue cuánto lleva y, ya listo, es una versión más que
arranca al instante (Fernando, 2 nov 2026, propuesta RD: «Pedirlo y avisarme»).

La libreta es la misma en la TV y en el iPhone (design/addons-contract.json, «requests»; corte S2 de «La TV sin Stremio»):
una entrada por torrent, con su huella como clave, los videos que trae, quién lo pidió, de qué cuenta de Real-Debrid es y
uno de seis estados (más la lápida «gone»). La TV la guarda en el estado (sobrevive a un reinicio) y el iPhone la lee y le
manda la suya por GET/POST /api/realdebrid/requests. Mientras haya alguno en camino, un hilo le pregunta a Real-Debrid
cada POLL segundos por todos a la vez y avisa: «rd-request» (para la ficha) y, si lo pidió la TV, «Ya está …».
"""

from __future__ import annotations

import logging
import re
import threading
import time
import zlib
from collections.abc import Callable

from .library import addons, realdebrid, streams
from .net import NET_ERRORS

log = logging.getLogger(__name__)

STATE_ID = "rd:requests"
DEVICE = "TV"  # el nombre de la consola en `by` (el iPhone dice «Lo pidió la TV»)
POLL = 20.0
FORGET_AFTER = 7 * 86400  # lo terminado se olvida a la semana de su último cambio
STALL_AFTER = 24 * 3600  # «Sigue sin bajar · ¿probar otra versión?»
READY_LINK_TTL = 6 * 3600  # el enlace de Real-Debrid se vuelve a sacar pasado este rato
ACCOUNT_TTL = 3600
MAX_ENTRIES = 200

QUEUED, DOWNLOADING, NO_PEERS, REFUSED, TOO_MANY, READY, GONE = (
    "queued", "downloading", "no_peers", "refused", "too_many", "ready", "gone")
STATES = (QUEUED, DOWNLOADING, NO_PEERS, REFUSED, TOO_MANY, READY, GONE)
ACTIVE = {QUEUED, DOWNLOADING, NO_PEERS}
# Al juntar dos entradas gana el estado de más arriba (too_many se reintenta más tarde: cualquiera le gana).
PRECEDENCE = {GONE: 6, READY: 5, REFUSED: 4, NO_PEERS: 3, DOWNLOADING: 2, QUEUED: 1, TOO_MANY: 0}
# Lo que se ve, en las palabras de design/vocabulario.json.
WORDS = {QUEUED: "En cola", NO_PEERS: "Sin gente que lo comparta", REFUSED: "Real-Debrid no lo dejó bajar",
         TOO_MANY: "Muchas descargas activas", READY: "Listo"}
DETAILS = {QUEUED: "Real-Debrid lo recibió y espera turno", NO_PEERS: "Puede tardar días · Prueba otra versión",
           REFUSED: "Prueba otra versión", TOO_MANY: "Cancela otro pedido en Tus pedidos", READY: "Ya arranca al instante"}

HASH = re.compile(r"^[0-9a-f]{40}$")
LOCAL_ONLY = ("notified", "nudged")  # nunca viajan: avisa solo el aparato que lo pidió
TEXT_LIMITS = {"title": 120, "by": 60, "meta_id": 100, "language": 20, "release": 200, "rd_status": 40, "account": 40,
               "rd_id": 40}


def rd_state(rd_status: str, progress: int, seeders: int | None) -> str:
    """Lo que dice Real-Debrid de un torrent, como uno de los seis estados (contrato, rd_status_map)."""
    if rd_status == "downloaded":
        return READY
    if rd_status in ("magnet_error", "error", "virus", "dead"):
        return REFUSED
    if rd_status in ("downloading", "compressing", "uploading"):
        return NO_PEERS if rd_status == "downloading" and seeders == 0 and progress < 100 else DOWNLOADING
    return QUEUED


def label(req: dict) -> str:
    """Cómo se dice un pedido en una línea: «Bajando en Real-Debrid · 42 %», «En cola»…"""
    state = req.get("state")
    if state == DOWNLOADING:
        return f"Bajando en Real-Debrid · {int(req.get('percent') or 0)} %"
    return WORDS.get(str(state), "En cola")


def clean(raw: object) -> dict | None:
    """Una entrada como la manda el iPhone (o la de un estado viejo), con su forma o None. Lo que no conoce lo ignora."""
    if not isinstance(raw, dict):
        return None
    h = str(raw.get("hash") or "").lower()
    if not HASH.match(h):
        return None
    out: dict = {"hash": h}
    if isinstance(raw.get("account"), int) and not isinstance(raw.get("account"), bool):  # el id de Real-Debrid es un número
        raw = {**raw, "account": str(raw["account"])}
    for key, limit in TEXT_LIMITS.items():
        value = raw.get(key)
        if value is None:
            continue
        if not isinstance(value, str) or len(value) > limit:
            return None
        out[key] = value
    kind = raw.get("kind") or "movie"
    if kind not in ("movie", "series"):
        return None
    out["kind"] = kind
    vids = raw.get("video_ids") or []
    if not isinstance(vids, list) or len(vids) > 50 or not all(isinstance(v, str) and 0 < len(v) <= 100 for v in vids):
        return None
    out["video_ids"] = list(dict.fromkeys(vids))
    files = raw.get("files") or {}
    if isinstance(raw.get("file_idx"), int) and len(out["video_ids"]) == 1:  # el iPhone de antes mandaba un solo archivo
        files = {out["video_ids"][0]: raw["file_idx"], **(files if isinstance(files, dict) else {})}
    if not isinstance(files, dict) or len(files) > 50 or not all(
            isinstance(k, str) and isinstance(v, int) and v >= 0 for k, v in files.items()):
        return None
    out["files"] = dict(files)
    for key in ("season", "episode", "seeders"):
        value = raw.get(key)
        if value is not None and (not isinstance(value, int) or isinstance(value, bool)):
            return None
        out[key] = value
    percent = raw.get("percent") or 0
    if not isinstance(percent, (int, float)) or not 0 <= percent <= 100:
        return None
    out["percent"] = int(percent)
    for key in ("since", "progress_at", "updated"):
        value = raw.get(key)
        if value is not None and not isinstance(value, (int, float)):
            return None
        out[key] = float(value) if value is not None else None
    out["all_files"] = raw.get("all_files") is True
    state = raw.get("state")
    out["state"] = REFUSED if state == "failed" else state if state in STATES else QUEUED  # lo desconocido: se vuelve a preguntar
    return out


def merge(old: dict, new: dict) -> dict:
    """Dos entradas de la misma huella, juntas campo por campo (contrato, «merge»): los relojes nunca deciden."""
    fresh = bool(new.get("rd_id") and old.get("rd_id") and new["rd_id"] != old["rd_id"])  # volver a pedir da otro rd_id
    if fresh:
        out = {**new}
    else:
        out = {**old}
        for key in ("rd_id", "title", "by", "since", "meta_id", "kind", "season", "episode", "language", "release",
                    "account"):
            if not out.get(key) and new.get(key):
                out[key] = new[key]
        out["all_files"] = bool(old.get("all_files") or new.get("all_files"))
        if PRECEDENCE.get(str(new.get("state")), 1) > PRECEDENCE.get(str(old.get("state")), 1):
            out["state"] = new["state"]
        if (new.get("percent") or 0) > (old.get("percent") or 0):
            out.update(percent=new["percent"], rd_status=new.get("rd_status") or old.get("rd_status"),
                       seeders=new.get("seeders"))
        out["progress_at"] = max(old.get("progress_at") or 0, new.get("progress_at") or 0) or None
    out["video_ids"] = list(dict.fromkeys([*(old.get("video_ids") or []), *(new.get("video_ids") or [])]))
    out["files"] = {**(old.get("files") or {}), **(new.get("files") or {})}
    for key in LOCAL_ONLY:
        out[key] = (new if fresh else old).get(key, False)
    return out


class RdRequests:
    def __init__(self, finder: streams.StreamFinder, state, publish, rd_factory=realdebrid.RealDebrid,
                 token: Callable[[], str | None] | None = None) -> None:
        self.finder = finder
        self.state = state
        self.publish = publish
        self.rd_factory = rd_factory
        self.token = token or self._torrentio_token  # el corte S2 le da la clave propia de la consola
        self._lock = threading.RLock()
        self._polling = False
        self._account: tuple[float, str | None, str | None] = (0.0, None, None)  # (cuándo, token, id de usuario)
        self._links: dict[tuple[str, str], tuple[float, str, str]] = {}  # el enlace listo vive solo en memoria

    # --- de dónde sale la clave y qué torrents hay ---------------------------------------------------------------
    def _debrid_addon(self) -> addons.Addon | None:
        try:
            return next((a for a in self.finder.addons() if realdebrid.token_in(a.base)), None)
        except Exception as exc:  # noqa: BLE001 — sin lista de complementos (Stremio sin conectar, sin red): no hay Torrentio
            log.info("Sin tu Torrentio para Real-Debrid: %s", exc)
            return None

    def _torrentio_token(self) -> str | None:
        addon = self._debrid_addon()
        return realdebrid.token_in(addon.base) if addon else None

    def client(self) -> realdebrid.RealDebrid | None:
        token = self.token()
        return self.rd_factory(token) if token else None

    def account(self) -> str | None:
        """El id de usuario de tu Real-Debrid (nunca la clave): de qué cuenta es cada pedido. None si no se sabe."""
        token = self.token()
        when, cached_token, user = self._account
        if token and token == cached_token and time.time() - when < ACCOUNT_TTL:
            return user
        rd = self.rd_factory(token) if token else None
        user = None
        if rd is not None:
            try:
                got = rd.user().get("id")
                user = str(got) if got is not None else None
            except (realdebrid.RealDebridError, AttributeError) as exc:
                log.info("No pude saber de qué cuenta de Real-Debrid es la clave: %s", exc)
                return cached_token == token and self._account[2] or None
        self._account = (time.time(), token, user)
        return user

    def _mine(self, req: dict, account: str | None) -> bool:
        """Es de tu cuenta de Real-Debrid: la TV lo puede seguir, cancelar y ver. Sin `account` cuenta como de la misma."""
        return not req.get("account") or not account or req["account"] == account

    def candidates(self, kind: str, video_id: str, prefs: streams.Preferences) -> list[streams.Source]:
        """Los torrents que existen para ese video (tu Torrentio, con tus opciones pero sin Real-Debrid), del mejor al peor
        según tu idioma. Vacío si no hay o si no contestó."""
        addon = self._debrid_addon()
        if addon is None:
            return []
        base = realdebrid.without_debrid(addon.base)
        try:
            data = addons.fetch_json(f"{base}/stream/{kind}/{video_id}.json", self.finder.timeout)
        except NET_ERRORS as exc:
            log.info("Sin torrents para pedir de %s: %s", video_id, exc)
            return []
        found = []
        for i, stream in enumerate(data.get("streams") or []):
            if not isinstance(stream, dict) or not isinstance(stream.get("infoHash"), str):
                continue
            try:
                found.append(streams.parse(stream, addon.name, base, i))
            except streams.PARSE_ERRORS:
                continue
        return [s for s in streams.rank(found, prefs, kind) if not {"CAM", "Tráiler"} & set(s.tags)]

    # --- la libreta ----------------------------------------------------------------------------------------------
    def _all(self) -> dict[str, dict]:
        """Las entradas por huella. Las de antes del corte S2 (por video, sin huella) se quedan como estaban hasta que el
        siguiente vistazo a Real-Debrid les encuentre su huella (`_migrate`)."""
        return {k: v for k, v in self.state.prefs(STATE_ID).items() if isinstance(v, dict)}

    def _put(self, key: str, value: dict | None) -> None:
        self.state.set_pref(STATE_ID, key, value)

    def _entries(self) -> list[dict]:
        return [v for k, v in self._all().items() if HASH.match(k)]

    def find(self, video_id: str) -> dict | None:
        """El pedido de ese video: el más reciente que no está rechazado ni cancelado; si no hay, el último."""
        mine = [r for r in self._entries() if video_id in (r.get("video_ids") or []) and r.get("state") != GONE]
        mine.sort(key=lambda r: r.get("since") or 0, reverse=True)
        legacy = self._all().get(video_id)
        if not mine and isinstance(legacy, dict):  # todavía sin migrar
            return {**legacy, "state": REFUSED if legacy.get("state") == "failed" else legacy.get("state") or QUEUED,
                    "video_ids": [video_id], "by": DEVICE}
        return next((r for r in mine if r.get("state") != REFUSED), mine[0] if mine else None)

    def status(self, video_id: str) -> dict | None:
        """{"state", "percent", "message", "detail", "language", "by", "mine"} del pedido de ese video, o None."""
        req = self.find(video_id)
        if req is None:
            return None
        out = {k: req.get(k) for k in ("state", "percent", "language", "by")}
        out["message"] = label(req)
        out["detail"] = DETAILS.get(str(req.get("state")), "")
        out["mine"] = self._mine(req, self._account[2])
        out["hash"] = req.get("hash")
        if req.get("state") in ACTIVE and req.get("progress_at") and time.time() - req["progress_at"] >= STALL_AFTER:
            out["detail"] = "Sigue sin bajar · ¿probar otra versión?"
        return out

    def listing(self) -> dict:
        """Para «Tus pedidos» y GET /api/realdebrid/requests: {version, account, requests}, sin lo que solo vive aquí."""
        self.prune()
        account = self.account()
        entries = sorted(self._entries(), key=lambda r: r.get("since") or 0, reverse=True)
        return {"version": 1, "account": account,
                "requests": [{k: v for k, v in r.items() if k not in LOCAL_ONLY} for r in entries]}

    def receive(self, raw: object) -> dict:
        """POST /api/realdebrid/requests: un pedido (o lo que cambió de él) que manda otro aparato. Se junta por huella y
        nunca se le pide nada a Real-Debrid. ValueError si no tiene la forma."""
        entry = clean(raw)
        if entry is None:
            raise ValueError("Ese pedido no tiene la forma acordada")
        with self._lock:
            old = self._all().get(entry["hash"])
            if old is None and entry["state"] not in ACTIVE and (entry.get("updated") or time.time()) < time.time() - FORGET_AFTER:
                raise ValueError("Ese pedido ya se olvidó")
            fresh = merge(old, entry) if old else {**entry, "notified": True, "nudged": True}  # no es de aquí: no avisa
            fresh["updated"] = time.time()
            self._put(entry["hash"], fresh)
            self.prune()
        if fresh["state"] in ACTIVE and self._mine(fresh, self.account()):
            self.watch()
        for video_id in fresh.get("video_ids") or []:
            self._publish(video_id)
        return {k: v for k, v in fresh.items() if k not in LOCAL_ONLY}

    def prune(self) -> None:
        """Olvida lo terminado de hace una semana (y lo de otra cuenta sin noticias en una semana) y deja 200 como mucho."""
        now = time.time()
        account = self._account[2]
        with self._lock:
            entries = self._all()
            keep = []
            for key, req in entries.items():
                if not HASH.match(key):
                    continue
                old = now - (req.get("updated") or req.get("since") or 0) > FORGET_AFTER
                if old and (req.get("state") not in ACTIVE or not self._mine(req, account)):
                    self._put(key, None)
                else:
                    keep.append((req.get("state") in ACTIVE, req.get("updated") or 0, key))
            keep.sort()
            for _, _, key in keep[:max(0, len(keep) - MAX_ENTRIES)]:
                self._put(key, None)

    # --- pedir ---------------------------------------------------------------------------------------------------
    def request(self, kind: str, video_id: str, title: str, prefs: streams.Preferences, meta_id: str = "",
                season: int | None = None, episode: int | None = None) -> dict:
        """Pide a Real-Debrid la mejor versión que existe de ese video. Lanza RealDebridError (en palabras) si no se pudo."""
        current = self.status(video_id)
        if current and current["state"] in (*ACTIVE, READY) and current.get("mine"):
            return current
        rd = self.client()
        if rd is None:
            raise realdebrid.RealDebridError("Conecta Real-Debrid en tu Torrentio para pedirle lo que no tiene")
        picks = self.candidates(kind, video_id, prefs)
        if not picks:
            raise realdebrid.RealDebridError("Nadie lo tiene todavía en internet · vuelve a buscar más tarde")
        refused = {k for k, v in self._all().items() if v.get("state") == REFUSED}
        pick = next((p for p in picks if p.stream["infoHash"].lower() not in refused), None)  # «Prueba otra versión»
        if pick is None:
            raise realdebrid.RealDebridError("Real-Debrid no lo dejó bajar · no queda otra versión que pedir")
        info_hash = pick.stream["infoHash"].lower()
        file_idx = pick.stream.get("fileIdx") if isinstance(pick.stream.get("fileIdx"), int) else None
        account = self.account()
        now = time.time()
        known = self._all().get(info_hash)
        if known and known.get("state") in (*ACTIVE, READY) and self._mine(known, account) and (
                file_idx is None or file_idx in (known.get("files") or {}).values()
                or known.get("all_files") or len(known.get("files") or {}) > 1):
            # Otro episodio del mismo paquete, ya pedido con todos sus videos (`all_files`): se une, sin volver a pedir
            # nada. Uno pedido con un solo archivo (los de antes del corte S2): ese episodio se pide como torrent nuevo.
            files = {**(known.get("files") or {}), **({video_id: file_idx} if file_idx is not None else {})}
            self._put(info_hash, {**known, "video_ids": list(dict.fromkeys([*known["video_ids"], video_id])),
                                  "files": files, "updated": now})
            self._publish(video_id)
            return self.status(video_id) or {}
        entry = {"hash": info_hash, "account": account, "rd_id": None, "title": title[:120], "kind": kind,
                 "meta_id": meta_id or video_id.split(":")[0], "video_ids": [video_id],
                 "files": {video_id: file_idx} if file_idx is not None else {}, "season": season, "episode": episode,
                 "language": " + ".join(streams.LANG_NAMES.get(lang, lang) for lang in pick.languages[:2])[:20],
                 "release": (pick.release or "")[:200], "by": DEVICE, "since": now, "updated": now, "rd_status": None,
                 "percent": 0, "seeders": None, "progress_at": now, "state": QUEUED, "all_files": kind == "series",
                 "notified": False, "nudged": False}
        try:
            entry["rd_id"] = rd.add(info_hash, file_idx, pack=kind == "series")
        except realdebrid.RealDebridError as exc:
            if not (exc.too_many or exc.refused):  # de tu cuenta o de la red: no queda anotado
                raise
            entry["state"] = TOO_MANY if exc.too_many else REFUSED
        self._put(info_hash, merge(known, entry) if known else entry)
        log.info("Pedido a Real-Debrid: %s (%s)", title, pick.release or info_hash)
        self._publish(video_id)
        self.watch()
        return self.status(video_id) or {}

    def cancel(self, info_hash: str) -> None:
        """«Cancelar pedido»: se quita de tu Real-Debrid y queda la lápida para que el otro aparato no lo reanote."""
        req = self._all().get(info_hash)
        if not req or not self._mine(req, self.account()):
            raise realdebrid.RealDebridError("Ese pedido es de otra cuenta de Real-Debrid")
        rd = self.client()
        if rd is None:
            raise realdebrid.RealDebridError("Vuelve a conectar Real-Debrid")
        if req.get("rd_id"):
            rd.delete(req["rd_id"])
        self._put(info_hash, {**req, "state": GONE, "updated": time.time()})
        for video_id in req.get("video_ids") or []:
            self._links.pop((info_hash, video_id), None)
            self._publish(video_id)

    def ready_source(self, kind: str, video_id: str) -> streams.Source | None:
        """El pedido ya bajado, como una versión que arranca al instante (o None). Solo lo de tu cuenta."""
        req = self.find(video_id)
        if not req or req.get("state") != READY or not req.get("hash") or not self._mine(req, self.account()):
            return None
        key = (req["hash"], video_id)
        cached = self._links.get(key)
        if cached and time.time() - cached[0] < READY_LINK_TTL:
            url, name = cached[1], cached[2]
        else:
            rd = self.client()
            try:
                got = rd.link(rd.info(req["rd_id"]), (req.get("files") or {}).get(video_id)) if rd and req.get("rd_id") else None
            except realdebrid.RealDebridError as exc:
                log.info("No pude sacar el enlace del pedido %s: %s", video_id, exc)
                got = None
            if not got:
                return None
            url, name = got
            self._links[key] = (time.time(), url, name)
        stream = {"name": "[RD+] Real-Debrid\nTu pedido", "title": name or req.get("title") or "", "url": url,
                  "behaviorHints": {"filename": name}}
        return streams.parse(stream, "Real-Debrid", "realdebrid://pedido", zlib.crc32(video_id.encode()) % 2**31)

    # --- el seguimiento ------------------------------------------------------------------------------------------
    def start(self) -> None:
        """Al arrancar Orbital: si quedó algo en camino (o sin migrar), se le vuelve a seguir."""
        if any(not HASH.match(k) or v.get("state") in ACTIVE for k, v in self._all().items()):
            self.watch()

    def watch(self) -> None:
        """Arranca el hilo que pregunta cuánto llevan (si no estaba ya)."""
        with self._lock:
            if self._polling:
                return
            self._polling = True
        threading.Thread(target=self._loop, daemon=True, name="rd-requests").start()

    def _loop(self) -> None:
        try:
            while self.tick():
                time.sleep(POLL)
        except Exception:  # noqa: BLE001 — que un pedido raro nunca deje los demás sin seguir en silencio
            log.exception("El seguimiento de pedidos a Real-Debrid se detuvo")
        finally:
            with self._lock:
                self._polling = False

    def _migrate(self, rd: realdebrid.RealDebrid, torrents: list[dict]) -> None:
        """Las entradas de antes del corte S2 (por video): su huella sale de Real-Debrid. Si ya no está allá, se olvidan."""
        for video_id, old in self._all().items():
            if HASH.match(video_id):
                continue
            info = next((t for t in torrents if t.get("id") == old.get("rd_id")), None)
            if info is None and old.get("rd_id"):
                try:
                    info = rd.info(old["rd_id"])
                except realdebrid.RealDebridError as exc:
                    if not exc.gone:
                        continue
            h = str((info or {}).get("hash") or "").lower()
            self._put(video_id, None)
            if not HASH.match(h):
                continue
            state = {"ready": READY, "failed": REFUSED}.get(str(old.get("state")), QUEUED)
            entry = {"hash": h, "account": self._account[2], "rd_id": old.get("rd_id"), "title": old.get("title") or "",
                     "kind": old.get("kind") or "series", "meta_id": video_id.split(":")[0], "video_ids": [video_id],
                     "files": {}, "season": None, "episode": None, "language": (old.get("language") or "")[:20],
                     "release": "", "by": DEVICE, "since": old.get("since") or time.time(), "updated": time.time(),
                     "rd_status": None, "percent": int(old.get("percent") or 0), "seeders": None,
                     "progress_at": old.get("since") or time.time(), "state": state, "all_files": False,
                     "notified": state == READY, "nudged": False}
            known = self._all().get(h)
            self._put(h, merge(known, entry) if known else entry)

    def tick(self) -> bool:
        """Un vistazo a todos los pedidos de tu cuenta que siguen en camino, con una sola consulta. True si queda alguno."""
        rd = self.client()
        if rd is None:
            return False  # sin clave: la ficha dice «Vuelve a conectar Real-Debrid»; se retoma al conectar
        account = self.account()
        try:
            torrents = rd.torrents(100)
        except realdebrid.RealDebridError as exc:
            log.info("No pude ver tus pedidos en Real-Debrid: %s", exc)
            return not exc.bad_key
        self._migrate(rd, torrents)
        pending = False
        for req in self._entries():
            if req.get("state") not in ACTIVE or not self._mine(req, account):
                continue
            match = next((t for t in torrents if req.get("rd_id") and t.get("id") == req["rd_id"]), None) \
                or next((t for t in torrents if str(t.get("hash") or "").lower() == req["hash"]), None)
            if match is None and req.get("rd_id"):  # más viejo que los 100 de la lista
                try:
                    match = rd.info(req["rd_id"])
                except realdebrid.RealDebridError as exc:
                    if exc.gone:  # lo borraste en real-debrid.com o lo canceló el otro aparato
                        self._update(req["hash"], {"state": GONE})
                    else:
                        pending = True
                    continue
            if match is None:  # Torrentio lo pidió al abrirlo y todavía no sale en tu cuenta
                pending = True
                continue
            self._apply(rd, req, match)
            pending = pending or self._all()[req["hash"]].get("state") in ACTIVE
        self.prune()
        return pending

    def _update(self, info_hash: str, change: dict) -> dict:
        """Cambia una entrada releyéndola bajo el candado (un POST del iPhone puede llegar a la vez)."""
        with self._lock:
            req = {**self._all().get(info_hash, {}), **change, "updated": time.time()}
            self._put(info_hash, req)
        for video_id in req.get("video_ids") or []:
            self._publish(video_id)
        return req

    def _apply(self, rd: realdebrid.RealDebrid, req: dict, torrent: dict) -> None:
        status = str(torrent.get("status") or "")
        percent = int(torrent.get("progress") or 0)
        seeders = torrent.get("seeders") if isinstance(torrent.get("seeders"), int) else None
        if status == "waiting_files_selection" and torrent.get("id"):
            try:
                files = req.get("files") or {}
                rd.select(torrent["id"], next(iter(files.values())) if len(files) == 1 else None, pack=req.get("kind") == "series")
            except realdebrid.RealDebridError as exc:
                log.info("No pude elegir los archivos del pedido %s: %s", req.get("title"), exc)
        state = rd_state(status, percent, seeders)
        now = time.time()
        change = {"rd_id": req.get("rd_id") or torrent.get("id"), "rd_status": status or None,
                  "percent": 100 if state == READY else max(percent, req.get("percent") or 0), "seeders": seeders,
                  "state": state}
        if change["percent"] > (req.get("percent") or 0) or state == READY:
            change["progress_at"] = now
        if all(req.get(k) == v for k, v in change.items()):
            if state in ACTIVE and not req.get("nudged") and req.get("by") == DEVICE and \
                    now - (req.get("progress_at") or now) >= STALL_AFTER:
                self._update(req["hash"], {"nudged": True})
                self.publish({"type": "toast", "ok": False, "message": f"{req.get('title') or 'Tu pedido'}: sigue sin bajar",
                              "detail": "¿Probar otra versión? · Tus pedidos, en Ajustes › Cuentas › Real-Debrid"})
            return
        fresh = self._update(req["hash"], change)
        if state == READY:
            for video_id in fresh.get("video_ids") or []:
                self.finder.forget(fresh.get("kind") or "series", video_id)
            if not fresh.get("notified") and fresh.get("by") == DEVICE:  # avisa solo quien lo pidió
                self._update(req["hash"], {"notified": True})
                self.publish({"type": "toast", "ok": True, "message": f"Ya está {fresh.get('title') or 'tu pedido'}",
                              "detail": "Real-Debrid lo terminó de bajar · ábrelo para verlo"})
        elif state == REFUSED and fresh.get("by") == DEVICE and not fresh.get("notified"):
            self._update(req["hash"], {"notified": True})
            self.publish({"type": "toast", "ok": False, "message": f"Real-Debrid no lo dejó bajar: {fresh.get('title') or 'tu pedido'}",
                          "detail": "Prueba otra versión"})

    def _publish(self, video_id: str) -> None:
        self.publish({"type": "rd-request", "video_id": video_id, "request": self.status(video_id)})
