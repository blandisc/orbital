"""El volumen, mantener un botón (salir, probar subtítulos), el cambio de episodio y lo que pide el iPhone."""

from __future__ import annotations

import math
import threading
import time

from .. import player_ui
from ..playback import EXTRA_LABEL, VOLUME_BOOST_MAX, extra_filter
from .input import _Input


class _Extras(_Input):
    """Volumen, mantener un botón, cambio de episodio y el iPhone."""

    # --- un solo volumen: el de Windows ------------------------------------------------------------------------------
    # Con `system_volume` = (leer, escribir) (quick.volume / quick.set_volume, lo conecta watch.py), ▲ ▼ y «Sin sonido»
    # mueven el volumen de la computadora, el mismo de Ajustes rápidos y de Alexa, y mpv se queda al 100 %: antes había
    # tres volúmenes (el de la tele, el de Windows y el del reproductor). Sin él (pruebas), el de mpv como antes.
    def _muted(self) -> bool:
        system = getattr(self, "system_volume", None)
        if system:
            return bool((system[0]() or {}).get("muted"))
        return bool(self._value("mute"))

    def set_muted(self, muted: bool) -> None:
        system = getattr(self, "system_volume", None)
        if system:
            system[1](muted=muted)
        else:
            self.mpv.command("set_property", "mute", muted)
            self._ask("mute", muted)

    def toggle_mute(self) -> bool:
        muted = not self._muted()
        self.set_muted(muted)
        return muted

    def _change_volume(self, direction: int, phone: bool = False) -> None:
        """▲ ▼ (y el + y − del iPhone, `phone`: V5-B, el mismo orden que el mando; la cápsula sale sin sus botones, V7-A)."""
        system = getattr(self, "system_volume", None)
        if system:
            now = system[0]() or {}
            current = int(now.get("level") or 0)
            boost = getattr(self, "boost", 100)
            # Pasado el 100 de Windows, sigue el del reproductor (hasta VOLUME_BOOST_MAX); al bajar, primero se quita eso.
            if (direction > 0 and current >= 100) or (direction < 0 and boost > 100):
                boost = max(100, min(VOLUME_BOOST_MAX, boost + 5 * direction))
                self.boost = boost
                self._apply_extra(boost)
                if direction > 0 and now.get("muted"):
                    system[1](level=current, muted=False)
                self._show_volume(boost, muted=False, touch=False if phone else None)
                return
            level = max(0, min(100, current + 5 * direction))
            after = system[1](level=level, muted=False if direction > 0 else None) or {"level": level}
            self._show_volume(after.get("level", level), muted=bool(after.get("muted")), touch=False if phone else None)
            return
        before = self._value("volume")
        if isinstance(before, (int, float)) and not isinstance(before, bool):
            top = self.mpv.get("volume-max")  # mpv deja pasar de 100 (130 de fábrica)
            top = top if isinstance(top, (int, float)) and not isinstance(top, bool) and top > 0 else 100
            volume = max(0, min(top, before + 5 * direction))
            self.mpv.command("set_property", "volume", volume)
            self._ask("volume", volume)
            self._show_volume(volume, muted=self._muted())
        else:
            self.mpv.command("add", "volume", 5 * direction)
            self.toast("Volumen")

    def _apply_extra(self, boost: float) -> None:
        """V1-C: el Extra no es el volumen de mpv (que solo multiplica y truena): mpv se queda en 100 y el filtro empareja
        y sube. Se cambia completo en cada paso de 5 (es un instante)."""
        self.mpv.command("set_property", "volume", 100)
        self.mpv.command("af", "remove", f"@{EXTRA_LABEL}")
        extra = extra_filter(boost)
        if extra:
            self.mpv.command("af", "add", extra)

    def _show_volume(self, level: float, muted: bool, touch: bool | None = None) -> None:
        """La cápsula del volumen; con el dedo, con sus botones − y + (V2-A) y un rato más a la vista para tocarlos.
        `touch=False`: desde el iPhone, sin los botones y el rato normal (V7-A)."""
        touch = player_ui.TOUCH if touch is None else touch
        self._show_notice(player_ui.volume_ass(level, muted=muted, touch=touch), 4.0 if touch else 1.6, layer=self.VOLUME)

    def volume_tap(self, x: float, y: float) -> bool:
        """Un toque en − o + de la cápsula (V2-A). True si tocó uno."""
        action = player_ui.hit("volume", x, y)
        if action not in ("up", "down"):
            return False
        self._change_volume(1 if action == "up" else -1)
        return True

    def show_volume_now(self) -> None:
        """El botón «Volumen» de abajo (mouse y dedo, V2-A): enseña la cápsula con − y +, sin cambiar nada."""
        system = getattr(self, "system_volume", None)
        if system:
            now = system[0]() or {}
            boost = getattr(self, "boost", 100)
            level = boost if boost > 100 else int(now.get("level") or 0)
            self._show_volume(level, muted=bool(now.get("muted")))
        else:
            value = self._value("volume")
            self._show_volume(value if isinstance(value, (int, float)) else 100, muted=self._muted())

    QUIT_HOLD = 1.5  # s con B mantenido para salir
    HOLD_SHOW_AFTER = .25  # s mantenido B antes de dibujar el anillo de salir
    HOLD_FPS = 30  # el anillo de «Salir» se llena con su propio reloj (antes, a saltos: solo con cada repetición de B)

    def _animate_hold(self, started: float) -> None:
        """Redibuja el anillo a 30 cuadros por segundo mientras B siga mantenido. Solo dibuja: salir lo sigue decidiendo
        `_hold_to_quit` con la repetición de B (soltar a tiempo nunca sale)."""
        def run() -> None:
            time.sleep(self.HOLD_SHOW_AFTER)  # un toque de B no enseña el anillo: parecía que B hacía dos cosas
            while getattr(self, "_quit_hold", None) == started:
                progress = (time.monotonic() - started) / self.QUIT_HOLD
                self._overlay(self.HOLD, player_ui.quit_hold_ass(min(1.0, progress)))
                if getattr(self, "_quit_hold", None) != started:  # soltaste mientras se dibujaba: que no se quede
                    self._overlay(self.HOLD, None)
                    return
                if progress >= 1:
                    return
                time.sleep(1 / self.HOLD_FPS)

        threading.Thread(target=run, daemon=True, name="hold-to-quit").start()

    subs_taught = False  # ya se enseñó «mantén X» al abrir el panel (una vez por Orbital)
    SUBS_HOLD = .6  # s con X mantenido para entrar a «Probar subtítulos» (un toque de X sigue abriendo el panel)

    def _hold_subs(self) -> None:
        """Mantener X: el anillo se llena y, lleno, entra a «Probar subtítulos». Soltar antes abre Audio y subtítulos
        (_release_x)."""
        started = time.monotonic()
        self._subs_hold = started

        def run() -> None:
            time.sleep(self.HOLD_SHOW_AFTER)  # un toque de X no enseña el anillo
            while getattr(self, "_subs_hold", None) == started:
                progress = (time.monotonic() - started) / self.SUBS_HOLD
                self._overlay(self.HOLD, player_ui.quit_hold_ass(min(1.0, progress), "X", "Probar subtítulos"))
                if progress >= 1:
                    self._subs_hold = None
                    self._overlay(self.HOLD, None)
                    self.try_subtitles()
                    return
                time.sleep(1 / self.HOLD_FPS)

        threading.Thread(target=run, daemon=True, name="hold-subs").start()

    def _release_x(self) -> None:
        """Soltaste X: si no se llenó el anillo, era un toque (Audio y subtítulos)."""
        if getattr(self, "_subs_hold", None) is None:
            return  # ya entró a probar, o la X cerró un panel
        self._subs_hold = None
        self._overlay(self.HOLD, None)
        if self.menu is None and self._try is None and self.current is not None:
            self.open_tracks()

    def _hold_to_quit(self) -> None:
        """B sigue mantenido: la barra avanza y, llena, sale. Solo si la pulsación empezó aquí (no la
        que cerró un panel o una tarjeta)."""
        started = getattr(self, "_quit_hold", None)
        if started is None:
            return
        progress = (time.monotonic() - started) / self.QUIT_HOLD
        if progress >= 1:
            self._quit_hold = None
            self._overlay(self.HOLD, None)
            self._quit()
        else:
            self._overlay(self.HOLD, player_ui.quit_hold_ass(progress))

    # s: RT, RT seguidos suman (dos episodios adelante) antes de cargar; y da tiempo de arrepentirse con B
    # (en la Legion Go en la mano, los gatillos se rozan sin querer).
    EPISODE_WAIT = 3.0
    EPISODE_CARD = 9  # capa de la cuenta atrás del cambio de episodio (como la tarjeta «Siguiente episodio»)

    def _queue_episode(self, meta: dict, step: int) -> None:
        """LT/RT: se cuentan las pulsaciones y, cuando paras, se carga ese episodio (antes dos RT rápidos cargaban el
        mismo «siguiente» dos veces). Mientras, la tarjeta de «Siguiente episodio» con la cuenta atrás en su anillo y
        «B Cancelar»: se ve cuándo va a cambiar y hasta cuándo se puede arrepentir (antes solo un aviso que se iba)."""
        self._episode_steps += step
        n = self._episode_steps
        if self._episode_timer:
            self._episode_timer.cancel()
        if n == 0:  # RT y luego LT: de vuelta en el mismo
            self._episode_timer = None
            self._stop_episode_card()
            self.toast("Sigues en este episodio", 2)
            return
        if abs(n) == 1:
            title = "Siguiente" + (f" · {meta['next']}" if n > 0 and meta.get("next") else "") if n > 0 else "Anterior"
        else:
            title = f"{abs(n)} episodios {'adelante' if n > 0 else 'atrás'}"
        self._episode_timer = threading.Timer(self.EPISODE_WAIT, self._step_episodes, args=(meta,))
        self._episode_timer.daemon = True
        self._episode_timer.start()
        self._episode_countdown(title)

    def _episode_countdown(self, title: str) -> None:
        """La tarjeta con el anillo que se vacía y los segundos que faltan, redibujada 30 veces por segundo (como la de
        «Siguiente episodio»; entra subiendo la primera vez, no con cada RT)."""
        started = time.monotonic()
        self._episode_anim = started
        self._episode_title = title
        since = getattr(self, "_episode_since", None)
        if since is None:
            self._episode_since = since = started

        def draw() -> bool:
            now = time.monotonic()
            left = self.EPISODE_WAIT - (now - started)
            if left <= 0 or getattr(self, "_episode_anim", None) != started:
                return False
            appear = min(1.0, (now - since) / self.CARD_IN) if self.CARD_FRAME else 1.0
            self._overlay(self.EPISODE_CARD, player_ui.upnext_ass(
                title, "Cambio de episodio", seconds=math.ceil(left), progress=left / self.EPISODE_WAIT,
                actions=[("B", "Cancelar")], appear=appear))
            return True

        draw()  # ya, sin esperar al hilo: la tarjeta sale en cuanto oprimes RT

        def run() -> None:
            while draw():
                time.sleep(self.CARD_FRAME or .1)

        threading.Thread(target=run, daemon=True, name="episode-countdown").start()

    def _stop_episode_card(self) -> None:
        self._episode_anim = self._episode_since = None
        self._overlay(self.EPISODE_CARD, None)

    def _cancel_episode(self) -> None:
        """B (o «Cancelar» con el dedo) durante la cuenta atrás: no cambia nada."""
        if self._episode_timer is not None:
            self._episode_timer.cancel()
        self._episode_timer, self._episode_steps = None, 0
        self._stop_episode_card()
        self.toast("Sigues en este episodio", 2)

    def _step_episodes(self, meta: dict) -> None:
        delta, self._episode_steps = self._episode_steps, 0
        if not delta or self.current is None:
            self._stop_episode_card()
            return
        # La tarjeta de la cuenta atrás se queda donde estaba y pasa a «Cargando…» (antes se iba y salía otro aviso).
        card = {"kind": "loading", "name": getattr(self, "_episode_title", ""), "since": time.monotonic(), "shown": 0.0}
        self._show_card(card)
        self._stop_episode_card()
        self._in_background(self._load_with_card, card, self.on_episode, meta, delta, failed="No pude cambiar de episodio")

    def _load_with_card(self, card: dict, load, *args):
        """Carga otro episodio con la tarjeta «Cargando…» a la vista: si no se pudo (o ya se avisó por qué), se va; si
        cargó, se va cuando el episodio da imagen (`_started`)."""
        ok = False
        try:
            ok = load(*args)
            return ok
        finally:
            if ok is not True:
                self._end_loading(card)

    def _expected_position(self, step: float) -> float | None:
        """Adónde va el seek que se acaba de pedir (mpv lo confirma un instante después)."""
        pos, dur = self._value("time-pos"), self.mpv.get("duration")
        if not isinstance(pos, (int, float)) or isinstance(pos, bool):
            return None
        end = dur if isinstance(dur, (int, float)) and dur > 0 else pos + abs(step)
        target = max(0.0, min(float(end), pos + step))
        self._ask("time-pos", target)
        return target

    def phone_legend(self) -> dict:
        """Lo que hace cada botón del control del iPhone con el reproductor al frente (las mismas acciones de
        /api/companion/input), para que el iPhone diga «Subtítulos» y no la leyenda de la interfaz."""
        if self._is_live():
            return {"up": "Canal siguiente", "down": "Canal anterior", "options": "Canales", "alt": "Audio",
                    "left": "Bajar volumen", "right": "Subir volumen", "select": "Silencio", "back": "Salir"}
        if self._try is not None:  # «Probar otros» subtítulos (la franja de arriba)
            return {"left": "Subtítulo anterior", "right": "Subtítulo siguiente", "up": "Adelantar subtítulos",
                    "down": "Atrasar subtítulos", "select": "Este va bien", "back": "Listo",
                    "prevsection": "Idioma anterior", "nextsection": "Idioma siguiente"}
        segment = self.segment
        meta = (segment.meta if segment is not None else None) or getattr(self.current, "meta", None) or {}
        series = meta.get("kind") == "series" and self.on_episode is not None
        legend = {"select": "Continuar" if self._value("pause") else "Pausa", "alt": "Audio y subtítulos",
                  "options": "Episodios y versión" if series else "Versión", "left": "Atrasar", "right": "Adelantar",
                  "up": "Subir volumen", "down": "Bajar volumen", "back": "Salir"}
        if series:
            legend |= {"pageleft": "Episodio anterior", "pageright": "Episodio siguiente"}
        # Con un panel abierto (episodios, versión, pausa), B lo cierra primero: el iPhone dice «Atrás», no «Salir»
        # (Fernando, 6 nov: «que sea atrás hasta que estés en la última pantalla de afuera»).
        if self.menu is not None:
            legend["back"] = "Atrás"
        return legend

    def phone_tracks(self) -> dict:
        """Las pistas de audio y subtítulos para el iPhone: {audio: [{id, label, lang, selected}], subtitles: [...]}."""
        tracks = self.mpv.get("track-list") or []

        def of(kind: str) -> list[dict]:
            return [{"id": t["id"], "label": player_ui.track_label(t), "lang": t.get("lang") or None,
                     "selected": bool(t.get("selected"))} for t in tracks if t.get("type") == kind and "id" in t]
        return {"audio": of("audio"), "subtitles": of("sub")}

    def phone_track(self, kind: str, track: int | str | None = None) -> None:
        """Del iPhone: «subtitles» o «audio». Sin `track`, la siguiente pista (los subtítulos pasan por «Sin
        subtítulos»); con `track` (un id de phone_tracks, o "no" para quitar los subtítulos), esa."""
        listed = self.phone_tracks()["subtitles" if kind == "subtitles" else "audio"]
        prop = "sid" if kind == "subtitles" else "aid"
        choices = ([{"id": "no", "label": "Sin subtítulos"}] if kind == "subtitles" else []) + listed
        if track is None:
            if len(choices) < 2:
                raise ValueError("No hay otra pista" if kind == "audio" else "Este video no trae subtítulos")
            here = next((i for i, c in enumerate(choices) if c.get("selected")), 0)
            chosen = choices[(here + 1) % len(choices)]
        else:
            chosen = next((c for c in choices if str(c["id"]) == str(track)), None)
            if chosen is None:
                raise ValueError("Esa pista ya no está")
        self._choose({"action": (prop, chosen["id"]), "label": chosen["label"], "lang": chosen.get("lang") or ""})

    def phone_button(self, action: str) -> None:
        """Un botón del control del iPhone con el reproductor al frente: como el mando, salvo B, que sale sin mantener
        (en el teléfono no hay «mantener B»): con un panel o los controles a la vista, primero los quita."""
        if action == "back":
            if self._try is not None:
                self.press("b")  # «Listo»: se queda el último que probaste
            elif self.menu is not None:
                self.press("b")
                self.press("b-up")
            elif self._hud_visible and not self._value("pause"):
                self.hide_hud()
            else:
                self._quit()
            return
        meta = getattr(self.current, "meta", None) or {}
        if action in ("pageleft", "pageright") and self.menu is None and not self._is_live()                 and meta.get("kind") == "series" and self.on_episode:
            self._queue_episode(meta, -1 if action == "pageleft" else 1)  # en el teléfono no se mantiene: directo
            return
        button = {"select": "a", "alt": "x", "options": "y", "menu": "x", "pageleft": "lt", "pageright": "rt",
                  "prevsection": "lb", "nextsection": "rb"}.get(action, action)
        if button in ("up", "down", "left", "right", "a", "x", "y", "lt", "rt", "lb", "rb"):
            self.press(button)

    def _quit(self) -> None:
        """Cierra mpv anotando ANTES cómo terminó (el catálogo lo lee al volver a Orbital: "Terminaste…"
        en vez de "Guardé dónde ibas"). Antes de cerrar, no después: el lanzador puede ver el proceso
        terminado antes que este vigilante."""
        segment, current = self.segment, self.current
        if segment is not None and current is not None:
            finished = bool(segment.duration) and segment.position >= segment.duration * .9
            # Qué era (película o serie, su IMDb): al terminarla, la interfaz ofrece calificarla (como el iPhone). Un tráiler o
            # un canal no se califican.
            rateable = not segment.live and not segment.meta.get("clip") and not segment.meta.get("synthetic")
            self.last_end = {"title": current.title, "finished": finished, "kind": segment.meta.get("kind"),
                             **({"meta_id": segment.meta.get("meta_id")} if rateable and segment.meta.get("meta_id") else {}),
                             **({"live": True} if segment.live else {})}
        self.mpv.command("quit")
