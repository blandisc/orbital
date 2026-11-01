"""Lo que necesitan las rutas, en un solo lugar (y fácil de cambiar en pruebas)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from ..catalog import Catalog
    from ..config import Config
    from ..shell import ConsoleShell
    from ..voice import VoiceController
    from .live import SseHub


@dataclass
class Deps:
    config: Config
    catalog: Catalog
    shell: ConsoleShell
    voice: VoiceController
    hub: SseHub
    kiosk: Any = None  # la ventana de Edge que abrió Orbital (None: la abriste tú)
    log_path: Path | None = None
    started: float = 0.0
    alexa_last: float | None = None  # última vez que llegó un comando de voz remoto
    extra: dict = field(default_factory=dict)

    @property
    def alexa_ready(self) -> bool:
        """Alexa configurada: hay un token fijo (no uno inventado en este arranque)."""
        return bool(self.config.server.token) and not self.config.server.token_is_ephemeral

    def status(self) -> dict:
        """Lo que está abierto (y si está en pausa): para /api/status y el evento "status"."""
        running = self.catalog.launcher.status()
        if running is not None:
            running["paused"] = self.shell.is_paused
            if running.get("id") == "media:player":
                holds = getattr(self.shell, "video_holds_screen", None)
                running["front"] = bool(holds and holds())  # el mando es del video: la interfaz no le hace caso
                running["pip"] = bool(getattr(getattr(self.shell, "player", None), "pip", False))  # en pequeño, en la esquina
            live = self.catalog.tv.playing() if running.get("id") == "media:player" else None
            if live:
                running["live"] = live  # qué canal de TV está al aire (la sección lo marca y A vuelve a él)
        return {"running": running}
