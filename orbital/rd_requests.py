"""Pedidos a Real-Debrid: lo que todavía no tiene se le pide, se sigue cuánto lleva y, ya listo, es una versión más que
arranca al instante (Fernando, 2 nov 2026, propuesta RD: «Pedirlo y avisarme»).

Los pedidos se recuerdan en el estado (sobreviven a un reinicio). Mientras haya alguno bajando, un hilo pregunta cada
POLL segundos y avisa: «rd-request» (para la ficha) y, al terminar, el aviso «Ya está …».
"""

from __future__ import annotations

import logging
import threading
import time
import zlib

from .library import addons, realdebrid, streams
from .net import NET_ERRORS

log = logging.getLogger(__name__)

STATE_ID = "rd:requests"
POLL = 20.0
FORGET_AFTER = 7 * 86400  # un pedido viejo (listo o fallido) se olvida a la semana
READY_LINK_TTL = 6 * 3600  # el enlace de Real-Debrid se vuelve a sacar pasado este rato


class RdRequests:
    def __init__(self, finder: streams.StreamFinder, state, publish, rd_factory=realdebrid.RealDebrid) -> None:
        self.finder = finder
        self.state = state
        self.publish = publish
        self.rd_factory = rd_factory
        self._lock = threading.Lock()
        self._polling = False

    # --- de dónde sale el token y qué torrents hay --------------------------------------------------------------
    def _debrid_addon(self) -> addons.Addon | None:
        return next((a for a in self.finder.addons() if realdebrid.token_in(a.base)), None)

    def client(self) -> realdebrid.RealDebrid | None:
        addon = self._debrid_addon()
        token = realdebrid.token_in(addon.base) if addon else None
        return self.rd_factory(token) if token else None

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

    # --- los pedidos ---------------------------------------------------------------------------------------------
    def _all(self) -> dict:
        return dict(self.state.prefs(STATE_ID))

    def _put(self, video_id: str, value: dict | None) -> None:
        self.state.set_pref(STATE_ID, video_id, value)

    def status(self, video_id: str) -> dict | None:
        """{"state": "downloading" | "ready" | "failed", "percent", "message"} del pedido de ese video, o None."""
        req = self._all().get(video_id)
        if not isinstance(req, dict):
            return None
        return {k: req.get(k) for k in ("state", "percent", "message", "language")}

    def request(self, kind: str, video_id: str, title: str, prefs: streams.Preferences) -> dict:
        """Pide a Real-Debrid la mejor versión que existe de ese video. Lanza RealDebridError (en palabras) si no se pudo."""
        current = self.status(video_id)
        if current and current["state"] in ("downloading", "ready"):
            return current
        rd = self.client()
        if rd is None:
            raise realdebrid.RealDebridError("Conecta Real-Debrid en tu Torrentio para pedirle lo que no tiene")
        picks = self.candidates(kind, video_id, prefs)
        if not picks:
            raise realdebrid.RealDebridError("Nadie tiene esto todavía en internet. Vuelve a buscar más tarde")
        pick = picks[0]
        file_idx = pick.stream.get("fileIdx")
        rd_id = rd.add(pick.stream["infoHash"], file_idx if isinstance(file_idx, int) else None)
        language = " + ".join(streams.LANG_NAMES.get(lang, lang) for lang in pick.languages[:2])
        self._put(video_id, {"kind": kind, "title": title, "rd_id": rd_id, "state": "downloading", "percent": 0,
                             "language": language, "since": time.time(), "message": ""})
        log.info("Pedido a Real-Debrid: %s (%s)", title, pick.release or pick.stream["infoHash"])
        self._publish(video_id)
        self.watch()
        return self.status(video_id) or {}

    def ready_source(self, kind: str, video_id: str) -> streams.Source | None:
        """El pedido ya bajado, como una versión que arranca al instante (o None)."""
        req = self._all().get(video_id)
        if not isinstance(req, dict) or req.get("state") != "ready":
            return None
        url, name = req.get("url"), req.get("filename") or req.get("title") or ""
        if not url or time.time() - float(req.get("linked") or 0) > READY_LINK_TTL:
            rd = self.client()
            try:
                got = rd.link(rd.info(req["rd_id"])) if rd else None
            except realdebrid.RealDebridError as exc:
                log.info("No pude sacar el enlace del pedido %s: %s", video_id, exc)
                got = None
            if not got:
                return None
            url, name = got
            self._put(video_id, {**req, "url": url, "filename": name, "linked": time.time()})
        stream = {"name": "[RD+] Real-Debrid\nTu pedido", "title": name, "url": url, "behaviorHints": {"filename": name}}
        return streams.parse(stream, "Real-Debrid", "realdebrid://pedido", zlib.crc32(video_id.encode()) % 2**31)

    # --- el seguimiento ------------------------------------------------------------------------------------------
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
        finally:
            with self._lock:
                self._polling = False

    def tick(self) -> bool:
        """Un vistazo a cada pedido que baja. True si queda alguno bajando."""
        pending = False
        rd = None
        for video_id, req in self._all().items():
            if not isinstance(req, dict):
                continue
            if req.get("state") != "downloading":
                if time.time() - float(req.get("since") or 0) > FORGET_AFTER:
                    self._put(video_id, None)
                continue
            rd = rd or self.client()
            if rd is None:
                return False
            try:
                info = rd.info(req["rd_id"])
            except realdebrid.RealDebridError as exc:
                log.info("No pude ver el pedido %s: %s", video_id, exc)
                pending = True
                continue
            status = str(info.get("status") or "")
            percent = int(info.get("progress") or 0)
            if status in realdebrid.DONE:
                self._put(video_id, {**req, "state": "ready", "percent": 100})
                self.finder.forget(req.get("kind") or "series", video_id)
                self.publish({"type": "toast", "ok": True, "message": f"Ya está {req.get('title') or 'tu pedido'}",
                              "detail": "Real-Debrid lo terminó de bajar · ábrelo para verlo"})
            elif status in realdebrid.FAILED:
                self._put(video_id, {**req, "state": "failed", "message": "Real-Debrid no pudo bajarlo"})
                self.publish({"type": "toast", "ok": False, "message": f"Real-Debrid no pudo bajar {req.get('title') or 'tu pedido'}",
                              "detail": "Prueba otra versión o vuelve a pedirlo más tarde"})
            else:
                pending = True
                if percent != req.get("percent"):
                    self._put(video_id, {**req, "percent": percent})
            self._publish(video_id)
        return pending

    def _publish(self, video_id: str) -> None:
        self.publish({"type": "rd-request", "video_id": video_id, "request": self.status(video_id)})
