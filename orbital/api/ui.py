"""La interfaz: qué puede hacer, ajustes, wifi y mandos, y abrir/recargar/cerrar su ventana."""

from __future__ import annotations

import asyncio
import json
import threading

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool

from .. import __version__, input_log, system
from .deps import Deps

# Ajustes que se pueden cambiar desde la interfaz (y sus valores válidos).
SETTINGS = {
    "audio": {"en", "es", "es-419", "es-ES"},
    "subtitles": {"en", "es", "forced", ""},
    "quality": {"4K", "1080p", "720p"},
    "sub_scale": {.85, 1.0, 1.25, 1.5},
    "text_size": {"normal", "large", "xlarge"},
    "safe_area": {0, 2, 4, 6},
    "reduce_motion": {True, False},
    "sounds": {True, False},
    "haptics": {True, False},
    "voice_tips": {True, False},
    "game_idle_minutes": {0, 30, 60, 120},
    "video_idle_minutes": {0, 15, 30, 60},
    "video_home": {"pip", "pause"},  # Home durante un video: en pequeño en una esquina, o pausa
    "close_previous": {True, False},  # la frase de Alexa debajo de los botones del héroe
    "game_mode": {"heavy", "off"},  # modo juego: cerrar la ventana de Orbital mientras juegas Switch, Wii U…
    "welcomed": {True, False},
    "emulator_updates": {"avisar", "auto", "nunca"},
    "screensaver_minutes": {0, 5, 10, 20, 30},  # protector de pantalla: el mosaico de Para ti tras ese rato sin tocar nada  # versiones nuevas de los emuladores (emulator_updates.py)  # ya vio "Tu consola" (la pantalla de primer uso)
}
VIEWS = ("buscar", "serie", "seccion", "fuentes")


def valid_setting(key, value) -> bool:
    """¿Ese valor sirve para ese ajuste? Mismo tipo que los permitidos (bool no pasa por número)."""
    allowed = SETTINGS.get(key) if isinstance(key, str) else None
    if allowed is None or isinstance(value, (list, dict)):
        return False
    return any(type(value) is type(option) and value == option for option in allowed) or (
        isinstance(value, int) and not isinstance(value, bool) and any(type(o) is float and value == o for o in allowed))


def router(d: Deps) -> APIRouter:
    r = APIRouter()
    catalog, shell, kiosk = d.catalog, d.shell, d.kiosk

    @r.get("/api/health")
    def health() -> dict:
        return {"ok": True, "version": __version__}

    @r.get("/api/system")
    async def system_info() -> dict:
        return {"wifi": await run_in_threadpool(system.wifi), "online": await run_in_threadpool(system.online),
                "alexa_last": d.alexa_last}

    @r.get("/api/controllers")
    async def controllers() -> dict:
        from ..gamepad import connected_controllers
        return {"controllers": await run_in_threadpool(connected_controllers)}

    @r.get("/api/ui")
    def ui_info() -> dict:
        return {"can_exit": kiosk is not None, "stremio_linked": catalog.stremio_linked,
                "player": "orbital" if catalog.native_player else "stremio",
                # Alexa configurada (token fijo): la interfaz enseña frases que puedes decirle.
                "alexa": d.alexa_ready}

    @r.get("/api/voice/commands")
    def voice_commands() -> dict:
        """«Lo que puedes decir»: la misma guía que el iPhone (alexa/commands.json; una prueba comprueba que cada frase llega a
        un comando de verdad)."""
        from ..alexa_setup import SKILL_SOURCE

        try:
            return json.loads((SKILL_SOURCE / "commands.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {"how": [], "groups": []}

    @r.get("/api/settings")
    def get_settings() -> dict:
        prefs = catalog.stream_prefs
        return {"audio": prefs.audio, "quality": prefs.quality, "subtitles": catalog.subtitles_lang,
                "sub_scale": float(catalog.watch.setting("sub_scale", 1.0) or 1.0), "text_size": "normal", "safe_area": 4,
                "reduce_motion": False, "sounds": True, "haptics": True, "voice_tips": True,
                "game_idle_minutes": d.config.sessions.game_idle_minutes,
                "video_idle_minutes": d.config.sessions.video_idle_minutes,
                "close_previous": d.config.sessions.close_previous, "screensaver_minutes": 10, "video_home": "pip", "game_mode": "heavy",
                **catalog.state.settings(),
                "stremio_linked": catalog.stremio_linked, "alexa": d.alexa_ready, "alexa_last": d.alexa_last,
                # «Para ti»: Ajustes › Cuentas enseña Trakt, TMDB y RAWG (y si su clave ya está).
                "trakt": catalog.foryou.status()["trakt"], "para_ti": catalog.foryou.status(),
                "onedrive": catalog.onedrive.status()}  # tus videos de OneDrive (Ajustes › Cuentas)

    @r.post("/api/settings")
    def set_settings(body: dict) -> dict:
        # Todo o nada: primero se valida el lote completo, con el tipo exacto (1 no es True, ni
        # False es 0), y después se guarda. Antes un lote a medias quedaba aplicado a medias.
        for key, value in body.items():
            if not valid_setting(key, value):
                raise HTTPException(422, f"Ajuste inválido: {key}")
        for key, value in body.items():
            catalog.state.set_setting(key, value)
        return get_settings()

    ui_state = d.extra.setdefault("ui_state", {"screen": "home", "text_field": False})

    @r.post("/api/ui/state")
    def report_state(body: dict) -> dict:
        """La interfaz cuenta qué pantalla tiene al frente y si hay un campo de texto: el control del iPhone enseña
        «Escribir» solo cuando sirve (/api/companion/now → ui)."""
        screen, section, legend = body.get("screen"), body.get("section"), body.get("legend")
        clean = {k: v[:40] for k, v in legend.items() if isinstance(k, str) and len(k) < 20 and isinstance(v, str)} \
            if isinstance(legend, dict) else {}
        ui_state.update(screen=screen if isinstance(screen, str) and len(screen) < 40 else "home",
                        text_field=body.get("text_field") is True,
                        section=section if isinstance(section, str) and len(section) < 40 else None,
                        legend=dict(list(clean.items())[:16]))
        return {"ok": True}

    @r.post("/api/ui/trace")
    def trace_input(body: dict) -> dict:
        """Diagnóstico de la entrada desde la interfaz (entrada.log): lo que reporta el mando, teclas, rueda y acciones."""
        entries = body.get("entries") if isinstance(body, dict) else None
        clean = [{"from": "ui", **e} for e in entries[:400] if isinstance(e, dict)] if isinstance(entries, list) else []
        input_log.record(clean)
        return {"ok": True}

    @r.post("/api/ui/exit")
    async def ui_exit() -> dict:
        if kiosk is None:
            raise HTTPException(409, "Esta ventana no la abrió Orbital: ciérrala tú (Alt+F4)")
        # Se cierra un instante después para que la respuesta llegue a la página.
        asyncio.get_running_loop().call_later(0.4, lambda: threading.Thread(target=kiosk.close, daemon=True).start())
        return {"ok": True}

    @r.post("/api/ui/reload")
    def ui_reload(body: dict | None = None) -> dict:
        """Recarga la interfaz abierta (tras actualizar Orbital no hace falta reiniciarlo).
        `view`: abrir directo una vista — {"buscar": "dune"} o {"serie": "tt0386676"}."""
        raw = (body or {}).get("view") if isinstance(body, dict) else None
        view = {k: str(v)[:200] for k, v in (raw if isinstance(raw, dict) else {}).items() if k in VIEWS}
        d.hub.publish_threadsafe({"type": "reload", "view": view})
        return {"ok": True}

    @r.post("/api/ui/show")
    def ui_show() -> dict:
        """El ícono del escritorio con Orbital ya abierto: trae (o reabre) la ventana en vez de otra copia."""
        if kiosk is None:
            raise HTTPException(409, "Esta interfaz no la abrió Orbital")
        threading.Thread(target=kiosk.open, daemon=True).start()
        return {"ok": True}

    @r.post("/api/ui/resume")
    def ui_resume() -> dict:
        """Vuelve al juego ("Seguir jugando")."""
        shell.hold = None
        return {"ok": shell.resume()}

    return r
