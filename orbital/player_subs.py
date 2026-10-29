"""«Probar otros» subtítulos en la TV: cambiar de uno a otro hasta dar con el bueno, igual que el iPhone.

Se entra manteniendo X (un toque de X sigue abriendo Audio y subtítulos), con la tecla S, con el botón «Probar subtítulos»
(mouse y touch) o desde X › Subtítulos › «Probar otros» (la primera fila). Arriba sale una franja
(player_ui.sub_trial_ass): la bandera y «Español · Subtítulo 2 de 5», por qué está ahí («Hecho para tu copia»), la copia
para la que se hizo, sus descargas y la sincronía. El video sigue:

  ◀ ▶ (← →, la rueda del mouse) el anterior / siguiente, y al final da la vuelta; regresa 8 s para oír la misma frase ·
  LB RB (RePág AvPág) otro idioma · ↑ ↓ adelantar o atrasar medio segundo (cada subtítulo guarda la suya) ·
  A «Este va bien»: en una serie, los siguientes episodios ponen primero los de esa misma copia ·
  B (Esc, «Listo») sale y deja el último que probaste, como el iPhone · Y ajusta la velocidad si es de otra edición.

Cada cambio se recuerda al momento (el idioma, ese subtítulo y su sincronía): no hace falta confirmar con A.
El orden es el del iPhone (library/subtitles.py): primero los del video, luego los de internet hechos para tu copia, los de
tu misma versión y los más bajados; con la huella del archivo, los de tu copia exacta. Los de sordos y los forzados se
saltan (salvo que el que tenías sea de ese tipo). De internet se baja solo el que eliges y, tras un segundo sin moverte,
el siguiente (uno, no dos): así ▶ es casi inmediato.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from . import flags, player_ui
from .library import subtitles as subtitle_lib
from .playback import base_language

log = logging.getLogger(__name__)

PREFERRED = ("es", "en")  # después del idioma que tienes, en LB/RB: español e inglés primero


class SubtitleTrial:
    """Se mezcla en PlayerScreen/OrbitalPlayer: usa su mpv, toast, _overlay, _sub_urls, fetch_subtitle…"""

    TRY = 10  # su capa (encima de la barra y los avisos)
    TRY_BACK = 8  # s que regresa al cambiar de subtítulo: la misma frase con el nuevo
    TRY_PRELOAD_WAIT = 1.0  # s sin moverte antes de bajar el siguiente de internet
    SUBS_OVER_PANEL = 46  # sub-pos (% del alto) con el panel X abierto: los subtítulos se ven encima del panel (desde 520)

    _try: dict | None = None
    _subs_lifted: float | None = None  # el sub-pos de antes de abrir el panel X (None: no se movieron)
    _keep_delay = False  # la sincronía se recuerda junto con los subtítulos (current_subtitle)
    subtitle_search = None  # (meta, url) -> [opción de subtítulo de internet] | None: todos los idiomas, con su copia
    good_release = None  # (meta) -> la copia buena de esta serie («…-NTb») | None
    on_good_release = None  # (meta, release): «Este va bien» en una serie

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
        tracks = self._sub_tracks()
        chosen = next((t for t in tracks if t.get("selected")), None)
        wanted = self._subs_lang if self._subs_lang not in ("", "forced") else ""
        lang = base_language(chosen.get("lang")) if chosen else base_language(wanted)
        if not lang and tracks:
            lang = base_language(tracks[0].get("lang"))
        searching = self.subtitle_search is not None or (self._fallback_subs is not None and base_language(self._subs_lang) == lang)
        if not lang or (not tracks and not searching):
            self.toast("Este video no trae subtítulos para probar", 3)
            return "Este video no trae subtítulos para probar"
        token = object()
        self._try = {"token": token, "lang": lang, "home": lang, "options": None, "searching": searching, "status": "", "timer": None,
                     "chosen": chosen["id"] if chosen else None, "candidates": [], "index": -1}
        self._try_build(lang)
        if self._hud_visible:
            self.hide_hud()
        if searching:
            self.background(lambda: self._try_fetch(token))
        self._try_draw()
        return None

    def _sub_tracks(self) -> list[dict]:
        return [t for t in self.mpv.get("track-list") or [] if isinstance(t, dict) and t.get("type") == "sub" and "id" in t]

    def _release_wanted(self) -> str | None:
        """La copia con la que se comparan los de internet: la buena de esta serie (si dijiste «Este va bien») o la tuya."""
        meta = getattr(self.current, "meta", None) or {}
        good = self._safe(self.good_release, meta) if self.good_release else None
        return good or meta.get("release") or None

    def _try_build(self, lang: str) -> None:
        """Los candidatos de ese idioma: los del video primero (sin sordos ni forzados, salvo el que tenías) y luego los de
        internet en el orden del iPhone. El puesto queda marcado."""
        trial = self._try
        if trial is None:
            return
        tracks = self._sub_tracks()
        chosen = next((t for t in tracks if t["id"] == trial["chosen"]), None)
        allowed = {"normal", player_ui.sub_kind(chosen) if chosen else "normal"}
        candidates = []
        for t in tracks:
            if base_language(t.get("lang")) != lang or (player_ui.sub_kind(t) not in allowed and t is not chosen):
                continue
            external = bool(t.get("external"))
            candidates.append({"track": t["id"], "origin": "addon" if external else "video", "lang": t.get("lang") or lang,
                               "url": self._sub_url(t) if external else "", "release": None, "downloads": None, "match": 0})
        known = {c["url"] for c in candidates if c["url"]}
        for option in subtitle_lib.ranked(trial["options"] or [], lang, self._release_wanted()):
            if option["url"] not in known:
                known.add(option["url"])
                candidates.append({"track": None, "origin": "addon", "url": option["url"], "lang": option["lang"],
                                   "release": option.get("release"), "downloads": option.get("downloads"),
                                   "match": option.get("match", 0)})
        here = next((i for i, c in enumerate(candidates) if chosen is not None and c["track"] == chosen["id"]), -1)
        trial.update(lang=lang, candidates=candidates, index=here)

    def _try_fetch(self, token) -> None:
        """Los de internet de todos los idiomas, con su copia y sus descargas (en su hilo: es internet)."""
        meta = getattr(self.current, "meta", None) or {}
        offline = False
        options: list[dict] | None
        try:
            if self.subtitle_search is not None:
                options = self.subtitle_search(meta, getattr(self.segment, "url", None))
                offline = options is None
            else:  # sin el buscador (un video de tu carpeta, pruebas): las de tu complemento en tu idioma
                urls = [u for u in (self._fallback_subs() or []) if isinstance(u, str)]
                lang = self._try["lang"] if self._try else ""
                options = [{"url": u, "lang": lang, "release": None, "downloads": None} for u in dict.fromkeys(urls)]
        except Exception:  # noqa: BLE001 - sin internet o el complemento no contestó
            log.info("No pude buscar subtítulos para probar", exc_info=True)
            options, offline = None, True
        trial = self._try
        if trial is None or trial["token"] is not token:
            return
        current = trial["candidates"][trial["index"]] if 0 <= trial["index"] < len(trial["candidates"]) else None
        trial["options"], trial["searching"] = options or [], False
        self._try_build(trial["lang"])
        if current is not None:  # el que estaba puesto sigue marcado aunque la lista creció
            trial["index"] = next((i for i, c in enumerate(trial["candidates"])
                                   if (current["track"] is not None and c["track"] == current["track"])
                                   or (current["url"] and c["url"] == current["url"])), trial["index"])
            trial["candidates"][trial["index"]].update({k: current[k] for k in ("delay", "path", "edition", "speed_on")
                                                        if k in current})
        if offline:
            trial["status"] = "Sin internet: solo los subtítulos del video"
        self._try_draw()
        self._try_schedule_preload()

    def _languages(self) -> list[str]:
        """Los idiomas que hay para probar (del video y de internet): el tuyo, español, inglés y los demás."""
        trial = self._try
        if trial is None:
            return []
        seen = [base_language(t.get("lang")) for t in self._sub_tracks()] + \
               [subtitle_lib.language(o.get("lang")) for o in trial["options"] or [] if not subtitle_lib.hides(o)]
        found = {c for c in seen if c}
        # El orden no cambia mientras recorres (LB/RB dan la vuelta): el idioma con el que entraste, español, inglés…
        first = [c for c in dict.fromkeys([trial["home"], *PREFERRED]) if c in found or c in (trial["home"], trial["lang"])]
        return first + sorted(found - set(first), key=lambda c: player_ui.language(c) or c)

    # --- la franja --------------------------------------------------------------------------------------------------
    def _here(self) -> dict | None:
        trial = self._try
        return trial["candidates"][trial["index"]] if trial and 0 <= trial["index"] < len(trial["candidates"]) else None

    def _try_draw(self) -> None:
        trial = self._try
        if trial is None:
            return
        here = self._here()
        status = trial["status"] or ("Buscando más en internet…" if trial["searching"] else "")
        self._overlay(self.TRY, player_ui.sub_trial_ass(player_ui.SubTrial(
            language=player_ui.language(trial["lang"]) or trial["lang"].upper(), number=trial["index"] + 1 if here else 0,
            total=len(trial["candidates"]), origin=here["origin"] if here else "video", delay=self.sub_delay, status=status,
            flag=flags.flag_for(trial["lang"]), badge=subtitle_lib.badge(here["match"]) if here else "",
            release=(here or {}).get("release") or "", downloads=(here or {}).get("downloads"),
            languages=len(self._languages()), edition=bool(here and here.get("edition")),
            edition_on=bool(here and here.get("speed_on")))))

    def _try_press(self, button: str) -> bool:
        """Los botones mientras pruebas subtítulos. True si el botón era de la franja (todos menos Home y los soltados)."""
        if button.endswith("-up") and not button.startswith("wheel-"):
            return False  # soltar B, X, LT o RT: de la barra, no de la franja
        button = button.removeprefix("stick-")
        if button in ("left", "right", "wheel-up", "wheel-down"):
            if not self.remote.held(button):  # mantenido no recorre la lista a toda velocidad
                self._try_step(1 if button in ("right", "wheel-down") else -1)
        elif button in ("lb", "rb"):
            if not self.remote.held(button):
                self._try_language(1 if button == "rb" else -1)
        elif button in ("up", "down"):
            self._set_sub_delay(self.sub_delay + (-player_ui.SUB_STEP if button == "up" else player_ui.SUB_STEP))
            here = self._here()
            if self._try is not None:
                self._try["status"] = ""
            if here is not None:
                here["delay"] = self.sub_delay  # la sincronía es de este subtítulo, no del siguiente
                self._try_remember()
            self._try_draw()
        elif button == "y":
            self._try_speed()
        elif button == "a":
            self._try_keep(good=True)
        elif button in ("b", "done"):
            if not self.remote.held("b"):
                self._try_keep(good=False)
        return True

    # --- moverse ----------------------------------------------------------------------------------------------------
    def _try_step(self, step: int) -> None:
        trial = self._try
        if trial is None:
            return
        candidates = trial["candidates"]
        name = (player_ui.language(trial["lang"]) or trial["lang"]).lower()
        if not candidates:
            trial["status"] = "Buscando en internet…" if trial["searching"] else f"No encontré subtítulos en {name}"
        else:
            target = (trial["index"] + step) % len(candidates)  # al final da la vuelta, como el iPhone
            wrapped = trial["index"] >= 0 and ((step > 0 and target <= trial["index"]) or (step < 0 and target >= trial["index"]))
            trial["status"] = ("De vuelta al primero" if step > 0 else "Del primero al último") if wrapped else ""
            self._try_select(target)
        self._try_draw()

    def _try_language(self, step: int) -> None:
        """LB/RB: otro idioma, sin salir de la franja; se pone el mejor de ese idioma."""
        trial = self._try
        if trial is None:
            return
        langs = self._languages()
        if len(langs) < 2:
            trial["status"] = "Buscando más idiomas…" if trial["searching"] else "Solo hay subtítulos en este idioma"
            return self._try_draw()
        here = self._here()
        if here is not None:
            here["delay"] = self.sub_delay
        lang = langs[(langs.index(trial["lang"]) + step) % len(langs)] if trial["lang"] in langs else langs[0]
        self._try_build(lang)
        trial["index"], trial["status"] = -1, ""
        if trial["candidates"]:
            self._try_select(0)
        else:
            trial["status"] = f"No encontré subtítulos en {(player_ui.language(lang) or lang).lower()}"
        self._try_draw()

    def _try_select(self, index: int) -> None:
        here = self._here()
        if here is not None:
            here["delay"] = self.sub_delay
        trial = self._try
        if trial is None:
            return
        trial["index"] = index
        self._try_apply(trial["candidates"][index], index)
        self._try_schedule_preload()

    def _loaded_track(self, candidate: dict):
        """El id de la pista de mpv de ese subtítulo de internet, si ya se agregó."""
        for t in self._sub_tracks():
            if t.get("external") and (
                    (candidate.get("path") and t.get("external-filename") == candidate["path"])
                    or (candidate["url"] and self._sub_url(t) == candidate["url"])):
                return t["id"]
        return None

    def _try_put(self, candidate: dict) -> None:
        """Ya está en mpv: su sincronía (la que le dejaste, o a tiempo), su velocidad y la misma frase otra vez."""
        delay = float(candidate.get("delay") or 0.0)
        if abs(delay - self.sub_delay) >= .05:
            self._set_sub_delay(delay)
        if candidate.get("edition") or candidate.get("speed_on") is not None:
            self.mpv.command("set_property", "sub-speed", subtitle_lib.PAL_SPEED if candidate.get("speed_on") else 1.0)
        self.mpv.command("seek", -self.TRY_BACK, "relative")
        self._try_remember()

    def _try_apply(self, candidate: dict, index: int) -> None:
        """Pone ese subtítulo y regresa unos segundos; uno de internet que falta, se baja primero (en su hilo)."""
        track = candidate["track"] if candidate["track"] is not None else self._loaded_track(candidate)
        if track is not None:
            candidate["track"] = track
            self.mpv.command("set_property", "sid", track)
            self._try_put(candidate)
            return
        trial = self._try
        if trial is None:
            return
        said, trial["status"] = trial["status"], "Bajando el subtítulo…"  # «De vuelta al primero» vuelve al bajarlo
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
            self._try_put(candidate)
            trial["status"] = "Parece de otra edición del video · Y ajusta la velocidad" if candidate.get("edition") else said
            self._try_draw()

        self.background(work)

    def _try_download(self, candidate: dict) -> str | None:
        """El archivo de ese subtítulo de internet (bajado una sola vez). None si no se pudo. Si es de otra edición del
        video (sigue después de que acaba), lo anota para ofrecer ajustar la velocidad."""
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
        try:
            end = subtitle_lib.last_cue(Path(path).read_text("utf-8", errors="replace"))
            candidate["edition"] = subtitle_lib.edition_speed(self.mpv.get("duration"), end)
        except OSError:
            pass
        return path

    def _try_speed(self) -> None:
        """Y: el subtítulo es de otra edición (más lenta): se ajusta su velocidad (otra vez Y, como venía)."""
        trial, here = self._try, self._here()
        if trial is None:
            return
        if here is None or not here.get("edition"):
            trial["status"] = "Este subtítulo es de tu misma edición"
            return self._try_draw()
        here["speed_on"] = not here.get("speed_on")
        self.mpv.command("set_property", "sub-speed", subtitle_lib.PAL_SPEED if here["speed_on"] else 1.0)
        trial["status"] = "Velocidad ajustada a tu edición" if here["speed_on"] else "Velocidad como venía"
        self._try_draw()

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

    # --- recordar y salir -----------------------------------------------------------------------------------------------
    def _try_remember(self) -> None:
        """Cada cambio se recuerda al momento (como el iPhone): el idioma, ese subtítulo y su sincronía."""
        here = self._here()
        if here is None or self.current is None:
            return
        meta = getattr(self.current, "meta", None) or {}
        self._keep_delay = True
        if self.on_language:
            self._safe(self.on_language, meta, "subtitles", here["lang"])
        if self.on_sub_kept:
            self._safe(self.on_sub_kept, meta)

    def _try_end(self) -> dict | None:
        trial, self._try = self._try, None
        if trial is not None:
            if trial["timer"] is not None:
                trial["timer"].cancel()
            self._overlay(self.TRY, None)
        return trial

    def _try_keep(self, good: bool) -> None:
        """Salir deja el último que probaste (B, Esc, «Listo»: como el iPhone). A «Este va bien» además le dice a la serie
        que esa copia es la buena: los siguientes episodios ponen primero los subtítulos de esa misma copia."""
        here = self._here()
        if here is not None:
            self._try_remember()  # otra vez al salir: lo que mpv ya tiene puesto (por si el último cambio aún bajaba)
        trial = self._try_end()
        if trial is None:
            return
        meta = getattr(self.current, "meta", None) or {}
        if good and here is not None and here.get("release") and self.on_good_release and meta.get("kind") == "series":
            self._safe(self.on_good_release, meta, here["release"])
        name = player_ui.language(trial["lang"]) or trial["lang"]
        sync = "" if abs(self.sub_delay) < .05 else f" · {player_ui.delay_label(self.sub_delay)}"
        if here is None:
            self.toast(f"Subtítulos como estaban{sync}", 2.5)
        else:
            self.toast(f"{'Este va bien' if good else 'Listo'} · {name} · Subtítulo {trial['index'] + 1}{sync}", 2.5)
