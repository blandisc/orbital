"""«Probar otros» subtítulos en la TV: cambiar de uno a otro hasta dar con el bueno (ver player_screen.py).

Se entra desde X › Subtítulos › «Probar otros» (o con `try_subtitles()`, que la voz puede llamar). Arriba sale una
franja (player_ui.sub_trial_ass): «Español · Subtítulo 2 de 5», de dónde viene (del video o de tu complemento) y la
sincronía. Mientras tanto el video sigue:

  ◀ ▶ el subtítulo anterior / siguiente del mismo idioma (las pistas del video y las de tu complemento) y regresa
      8 s para oír la misma frase con el nuevo · ↑ ↓ adelantar o atrasar medio segundo ·
  A «Este va bien»: se queda y el título lo recuerda (idioma, ese subtítulo y su sincronía) ·
  B «Dejar el de antes»: vuelve al que tenías al entrar, con su sincronía.

Los de sordos y los forzados se saltan (salvo que el que tenías sea de ese tipo). De internet se baja solo el que
eliges y, tras un segundo sin moverte, el siguiente (uno, no dos): así ▶ es casi inmediato.
"""

from __future__ import annotations

import logging
import threading

from . import player_ui
from .playback import base_language

log = logging.getLogger(__name__)


class SubtitleTrial:
    """Se mezcla en PlayerScreen/OrbitalPlayer: usa su mpv, toast, _overlay, _sub_urls, fetch_subtitle…"""

    TRY = 10  # su capa (encima de la barra y los avisos)
    TRY_BACK = 8  # s que regresa al cambiar de subtítulo: la misma frase con el nuevo
    TRY_PRELOAD_WAIT = 1.0  # s sin moverte antes de bajar el siguiente de internet
    SUBS_OVER_PANEL = 50  # sub-pos (% del alto) con el panel X abierto: los subtítulos se ven encima del panel

    _try: dict | None = None
    _subs_lifted: float | None = None  # el sub-pos de antes de abrir el panel X (None: no se movieron)
    _keep_delay = False  # «Este va bien»: la sincronía se recuerda junto con los subtítulos (current_subtitle)

    # --- los subtítulos suben mientras el panel X está abierto ------------------------------------------------------
    def _lift_subs(self, on: bool) -> None:
        if on and self._subs_lifted is None:
            before = self.mpv.get("sub-pos")
            ok = isinstance(before, (int, float)) and not isinstance(before, bool)
            self._subs_lifted = float(before) if ok else 100.0
            self.mpv.command("set_property", "sub-pos", self.SUBS_OVER_PANEL)
        elif not on and self._subs_lifted is not None:
            before, self._subs_lifted = self._subs_lifted, None
            self.mpv.command("set_property", "sub-pos", int(before) if before == int(before) else before)

    def _set_sub_delay(self, value: float) -> None:
        self.sub_delay = round(value, 1)
        self.mpv.command("set_property", "sub-delay", self.sub_delay)

    # --- entrar ---------------------------------------------------------------------------------------------------
    def try_subtitles(self) -> str | None:
        """Entra a «Probar otros» con el idioma de los subtítulos que tienes (o el de este título). None si entró; si
        no, el motivo en palabras (también lo dice en pantalla)."""
        if self.current is None or self._is_live():
            return "No hay un video abierto"
        if self._try is not None:
            return None
        if self.menu is not None:
            self.close_menu()
        tracks = [t for t in self.mpv.get("track-list") or [] if isinstance(t, dict) and t.get("type") == "sub" and "id" in t]
        chosen = next((t for t in tracks if t.get("selected")), None)
        wanted = self._subs_lang if self._subs_lang not in ("", "forced") else ""
        lang = base_language(chosen.get("lang")) if chosen else base_language(wanted)
        if not lang and tracks:
            lang = base_language(tracks[0].get("lang"))
        addon = self._fallback_subs if self._fallback_subs and base_language(self._subs_lang) == lang else None
        if not lang or (not tracks and addon is None):
            self.toast("Este video no trae subtítulos para probar", 3)
            return "Este video no trae subtítulos para probar"
        allowed = {"normal", player_ui.sub_kind(chosen) if chosen else "normal"}
        candidates = []
        for t in tracks:
            if base_language(t.get("lang")) != lang or (player_ui.sub_kind(t) not in allowed and t is not chosen):
                continue
            external = bool(t.get("external"))
            candidates.append({"track": t["id"], "origin": "addon" if external else "video",
                               "url": self._sub_url(t) if external else "", "lang": t.get("lang") or lang})
        index = next((i for i, c in enumerate(candidates) if chosen is not None and c["track"] == chosen["id"]), -1)
        token = object()
        self._try = {"token": token, "lang": lang, "candidates": candidates, "index": index, "status": "",
                     "before": {"sid": chosen["id"] if chosen else "no", "delay": self.sub_delay},
                     "searching": addon is not None, "timer": None}
        if self._hud_visible:
            self.hide_hud()
        if addon is not None:
            self.background(lambda: self._try_fetch(token, addon))
        self._try_draw()
        return None

    def _try_fetch(self, token, addon) -> None:
        """Las de tu complemento para ese idioma (en su hilo: es internet)."""
        try:
            urls = [u for u in addon() or [] if isinstance(u, str)]
            offline = False
        except Exception:  # noqa: BLE001 - sin internet o el complemento no contestó
            log.info("No pude buscar subtítulos para probar", exc_info=True)
            urls, offline = [], True
        trial = self._try
        if trial is None or trial["token"] is not token:
            return
        known = {c["url"] for c in trial["candidates"] if c["url"]}
        trial["candidates"] += [{"track": None, "origin": "addon", "url": u, "lang": trial["lang"]}
                                for u in dict.fromkeys(urls) if u not in known]
        trial["searching"] = False
        if offline:
            trial["status"] = "Sin internet: solo los subtítulos del video"
        self._try_draw()
        self._try_schedule_preload()

    # --- la franja --------------------------------------------------------------------------------------------------
    def _try_draw(self) -> None:
        trial = self._try
        if trial is None:
            return
        candidates, index = trial["candidates"], trial["index"]
        status = trial["status"] or ("Buscando más en tu complemento…" if trial["searching"] else "")
        here = candidates[index] if 0 <= index < len(candidates) else None
        self._overlay(self.TRY, player_ui.sub_trial_ass(player_ui.SubTrial(
            language=player_ui.language(trial["lang"]) or trial["lang"].upper(), number=index + 1 if here else 0,
            total=len(candidates), origin=here["origin"] if here else "video", delay=self.sub_delay, status=status)))

    def _try_press(self, button: str) -> bool:
        """Los botones mientras pruebas subtítulos. True si el botón era de la franja (todos menos Home y los soltados)."""
        if button.endswith("-up"):
            return False
        button = button.removeprefix("stick-")
        if button in ("left", "right"):
            if not self.remote.held(button):  # mantenido no recorre la lista a toda velocidad
                self._try_step(1 if button == "right" else -1)
        elif button in ("up", "down"):
            self._set_sub_delay(self.sub_delay + (-player_ui.SUB_STEP if button == "up" else player_ui.SUB_STEP))
            if self._try is not None:
                self._try["status"] = ""
            self._try_draw()
        elif button == "a":
            self._try_keep()
        elif button == "b":
            if not self.remote.held("b"):
                self._try_cancel()
        return True

    # --- moverse ----------------------------------------------------------------------------------------------------
    def _try_step(self, step: int) -> None:
        trial = self._try
        if trial is None:
            return
        candidates, target = trial["candidates"], trial["index"] + step
        name = (player_ui.language(trial["lang"]) or trial["lang"]).lower()
        if target >= len(candidates):
            trial["status"] = ("Buscando más en tu complemento…" if trial["searching"] else
                               f"No hay más subtítulos en {name}" if candidates else f"No encontré subtítulos en {name}")
        elif target < 0:
            trial["status"] = "Ese es el primero" if candidates else f"No encontré subtítulos en {name}"
        else:
            trial["index"], trial["status"] = target, ""
            self._try_apply(candidates[target], target)
            self._try_schedule_preload()
        self._try_draw()

    def _loaded_track(self, candidate: dict):
        """El id de la pista de mpv de ese subtítulo de internet, si ya se agregó."""
        for t in self.mpv.get("track-list") or []:
            if isinstance(t, dict) and t.get("type") == "sub" and t.get("external") and "id" in t and (
                    (candidate.get("path") and t.get("external-filename") == candidate["path"])
                    or (candidate["url"] and self._sub_url(t) == candidate["url"])):
                return t["id"]
        return None

    def _try_apply(self, candidate: dict, index: int) -> None:
        """Pone ese subtítulo y regresa unos segundos; uno de internet que falta, se baja primero (en su hilo)."""
        track = candidate["track"] if candidate["track"] is not None else self._loaded_track(candidate)
        if track is not None:
            candidate["track"] = track
            self.mpv.command("set_property", "sid", track)
            self.mpv.command("seek", -self.TRY_BACK, "relative")
            return
        trial = self._try
        if trial is None:
            return
        trial["status"] = "Bajando el subtítulo…"
        token = trial["token"]

        def work() -> None:
            path = self._try_download(candidate)
            trial = self._try
            if trial is None or trial["token"] is not token:
                return
            if path is None:
                if trial["candidates"][trial["index"]] is candidate:
                    trial["status"] = "No pude bajar este subtítulo (¿sin internet?) · ▶ el siguiente"
                    self._try_draw()
                return
            if trial["candidates"][trial["index"]] is not candidate:
                return  # ya te moviste a otro: queda bajado por si regresas
            self.mpv.command("sub-add", path, "select", f"Subtítulo {index + 1}", candidate["lang"])
            self.mpv.command("seek", -self.TRY_BACK, "relative")
            trial["status"] = ""
            self._try_draw()

        self.background(work)

    def _try_download(self, candidate: dict) -> str | None:
        """El archivo de ese subtítulo de internet (bajado una sola vez). None si no se pudo."""
        if candidate.get("path"):
            return candidate["path"]
        candidate["loading"] = True
        try:
            path = self.fetch_subtitle(candidate["url"])
        except (OSError, ValueError) as exc:
            log.info("No pude bajar el subtítulo: %s", exc)
            return None
        finally:
            candidate["loading"] = False
        self._sub_urls[path] = candidate["url"]
        candidate["path"] = path
        return path

    def _try_schedule_preload(self) -> None:
        trial = self._try
        if trial is None:
            return
        if trial["timer"] is not None:
            trial["timer"].cancel()
        timer = threading.Timer(self.TRY_PRELOAD_WAIT, self._try_preload, args=(trial["token"], trial["index"]))
        timer.daemon = True
        trial["timer"] = timer
        timer.start()

    def _try_preload(self, token, index: int) -> None:
        """Te quedaste un segundo en uno: se baja el siguiente de internet (solo ese)."""
        trial = self._try
        if trial is None or trial["token"] is not token or trial["index"] != index:
            return
        following = trial["candidates"][index + 1] if index + 1 < len(trial["candidates"]) else None
        if following is None or following["track"] is not None or following.get("path") or following.get("loading"):
            return
        following["loading"] = True
        self.background(lambda: self._try_download(following))

    # --- salir --------------------------------------------------------------------------------------------------------
    def _try_end(self) -> dict | None:
        trial, self._try = self._try, None
        if trial is not None:
            if trial["timer"] is not None:
                trial["timer"].cancel()
            self._overlay(self.TRY, None)
        return trial

    def _try_keep(self) -> None:
        """A «Este va bien»: se queda y el título lo recuerda (el idioma, ese subtítulo y su sincronía)."""
        trial = self._try_end()
        if trial is None:
            return
        candidates, index = trial["candidates"], trial["index"]
        here = candidates[index] if 0 <= index < len(candidates) else None
        meta = getattr(self.current, "meta", None) or {}
        self._keep_delay = True
        if self.on_language and self.current is not None and here is not None:
            self._safe(self.on_language, meta, "subtitles", here["lang"])
        if self.on_sub_kept and self.current is not None:
            self._safe(self.on_sub_kept, meta)
        name = player_ui.language(trial["lang"]) or trial["lang"]
        sync = "" if abs(self.sub_delay) < .05 else f" · {player_ui.delay_label(self.sub_delay)}"
        self.toast(f"Subtítulos: {name} · Subtítulo {index + 1}{sync}" if here else f"Subtítulos como estaban{sync}", 2.5)

    def _try_cancel(self) -> None:
        """B «Dejar el de antes»: el que tenías al entrar, con su sincronía."""
        trial = self._try_end()
        if trial is None:
            return
        before = trial["before"]
        self.mpv.command("set_property", "sid", before["sid"])
        if abs(self.sub_delay - before["delay"]) >= .05:
            self._set_sub_delay(before["delay"])
        self.toast("Volviste a los subtítulos de antes", 2.5)
