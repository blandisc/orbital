"""Catálogo: la biblioteca de Orbital (juegos, apps, películas y series) y la puerta a todo lo demás.

Se divide en piezas que no se llaman entre sí, se comunican por eventos (events.EventBus):
  * Catalog (aquí): escanear fuentes, filas de la interfaz, preferencias y búsqueda por nombre.
  * Sessions (sessions.py): abrir algo, la pantalla de carga y saber cuándo termina.
  * Watch (watch/): cuenta de Stremio, fuentes y el reproductor de Orbital.
  * ForYou (foryou/): «Para ti», recomendaciones de Trakt, TMDB, RAWG y tus juegos.
  * LiveTV (tv.py): «TV en vivo», los canales de México, su salud y ponerlos en el reproductor.
  * focus.py: ventanas y foco (pantalla de carga encima del emulador).
Catalog expone también los métodos de Sessions y Watch que usan el servidor y la voz, para que
ellos solo conozcan una cosa.

Es un paquete: cada pieza en su módulo (base: el estado y las constantes; query: consultar y preferencias; facts: datos de
la tienda de Steam; art: portadas y fondos; scan: escanear fuentes) y `Catalog`, aquí, es la fachada, con la misma API de
siempre. Las piezas se heredan en cadena (cada una ve las de antes) solo para que los tipos se revisen; el estado y sus
candados se arman una sola vez, en base.py.
"""

from __future__ import annotations

from ..focus import READY_TIMEOUT as READY_TIMEOUT  # compatibilidad
from ..focus import bring_app_to_front as bring_app_to_front
from ..focus import bring_game_to_front as bring_game_to_front
from ..focus import game_ready as game_ready
from ..focus import is_orbital_window as is_orbital_window
from ..focus import pin_orbital as pin_orbital
from ..sessions import QUICK_EXIT as QUICK_EXIT
from ..text import normalize as normalize
from ..watch import STREMIO_KEY as STREMIO_KEY
from ..watch import STREMIO_STALE_SECONDS as STREMIO_STALE_SECONDS
from ..watch import enrich_watch_item as enrich_watch_item
from ..watch import source_label as source_label
from ..watch import stremio_item as stremio_item
from ..watch import time_left as time_left
from ..watch import trailer_id as trailer_id
from .base import CATEGORIES as CATEGORIES
from .base import CONTINUE_LIMIT as CONTINUE_LIMIT
from .base import JUMP_LIMIT as JUMP_LIMIT
from .base import NEW_FOR as NEW_FOR
from .base import STEAM_STATS_DELAY as STEAM_STATS_DELAY
from .base import Listener as Listener
from .base import art_version as art_version
from .base import default_credentials as default_credentials
from .base import default_state as default_state
from .base import log as log
from .base import tone_path as tone_path
from .match import FILLER as FILLER
from .match import title_match as title_match
from .scan import _Scan


class Catalog(_Scan):
    """La biblioteca de Orbital y la puerta a todo lo demás (ver las piezas: base, query, facts, art, scan)."""
