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
        return {"running": running}
