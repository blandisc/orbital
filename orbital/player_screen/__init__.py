"""Lo que se ve encima del video (barra, pausa, adelantar, paneles, tarjetas, avisos) y qué hace cada botón del mando.

Es un paquete: una pieza por tema de `PlayerScreen` (cards: las tarjetas y la imagen de fondo; hud: la barra, la pausa y
el logo; menus: los paneles de pistas y Más; input: toques, ratón, teclas y botones; extras: el volumen, mantener un
botón, el cambio de episodio y lo que pide el iPhone; live: la TV en vivo) y base (la bitácora y cómo se preparan las
imágenes). `PlayerScreen`, aquí, es la fachada, con la misma API de siempre: OrbitalPlayer (player.py) la hereda y le da
su estado (mpv, segment…). Las piezas se heredan en cadena (cada una ve las de antes) solo para que los tipos se revisen.
"""

from __future__ import annotations

import threading  # noqa: F401  (player_screen.threading: las pruebas lo usan)

from .. import player_ui
from .base import SEEK_LINGER as SEEK_LINGER
from .base import log as log
from .base import logo_bgra as logo_bgra
from .base import still_bgra as still_bgra
from .live import _Live


class PlayerScreen(_Live):
    """Lo que se ve encima del video (barra, pausa, adelantar, paneles, tarjetas, avisos) y qué
    hace cada botón del mando. Se mezcla en OrbitalPlayer: usa su estado (mpv, segment…)."""

    # --- paneles de columnas: X (Audio · Subtítulos · Tamaño) y Y (Más) ---------------------------
    def open_tracks(self, focus: str = "audio") -> None:
        tracks = self.mpv.get("track-list") or []
        extra = []
        if not self._is_live() and (self._fallback_subs or any(t.get("type") == "sub" for t in tracks)):
            # Primera fila de Subtítulos, y dice el atajo (regla de las cuatro superficies): mantener X, la tecla S.
            how = "Tecla S" if player_ui.KEYBOARD else "Uno por uno" if player_ui.TOUCH else "Mantén X"
            extra.append({"label": "Probar otros", "hint": how, "action": ("try", None), "current": False, "first": True})
        if self._fallback_subs and self._subs_lang:
            extra.append({"label": f"Buscar en {player_ui.language(self._subs_lang).lower()}…",
                          "action": ("fetch", self._subs_lang), "current": False})
        meta = getattr(self.current, "meta", None) or {}
        # Tu idioma (y los que esta no trae) en otra versión: de la lista ya buscada, sin esperar a internet.
        versions = self._safe(self.versions_provider, meta) if self.versions_provider and self.current else None
        self._open_panel(player_ui.tracks_panel(tracks, self.sub_scale, extra, focus, sub_delay=self.sub_delay,
                                                versions=versions or None))
        if extra and extra[0].get("first") and not player_ui.TOUCH and not PlayerScreen.subs_taught:
            PlayerScreen.subs_taught = True  # la primera vez (en esta Orbital): cómo se llega directo
            key = "S" if player_ui.KEYBOARD else "X"
            self.toast(f"Para probar subtítulos sin abrir esto: {'oprime' if player_ui.KEYBOARD else 'mantén'} {key}", 4)
