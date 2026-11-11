"""Trakt: tu cuenta (código en el celular), lo que viste, tus listas, calificaciones y notas, y lo que sigue.

Es un paquete: base (las medidas, los errores y las funciones que leen y arman lo que Trakt manda) y una pieza por tema
de `Trakt` (account: conectar, la clave y las llamadas; lists: Mi lista, tus listas, favoritos, calificaciones y
ocultas; history: lo que viste, notas, el calendario, el avance y lo que sigue). `Trakt`, aquí, es la fachada: arma el
estado y hace las llamadas a la red (`http_json`, que las pruebas cambian en `trakt.http_json`: por eso _call y unlink
viven aquí), con la misma API de siempre. Las piezas se heredan en cadena solo para que los tipos se revisen.
"""

from __future__ import annotations

import threading
from urllib.parse import urlencode

from ...net import NET_FAILURES, RETRIES, http_json
from .base import API as API
from .base import DROPPED_SECTIONS as DROPPED_SECTIONS
from .base import FAVORITES_FULL as FAVORITES_FULL
from .base import FAVORITES_TTL as FAVORITES_TTL
from .base import HIDDEN_SECTIONS as HIDDEN_SECTIONS
from .base import HOST as HOST
from .base import KINDS as KINDS
from .base import NOTE_LIMIT as NOTE_LIMIT
from .base import PLAYBACK_TTL as PLAYBACK_TTL
from .base import PRIVACIES as PRIVACIES
from .base import PROGRESS_SHOWS as PROGRESS_SHOWS
from .base import REDIRECTS as REDIRECTS
from .base import REPEAT_WINDOW as REPEAT_WINDOW
from .base import SAME_VIEWING_WINDOW as SAME_VIEWING_WINDOW
from .base import SCROBBLE_ACTIONS as SCROBBLE_ACTIONS
from .base import TOKENS_KEY as TOKENS_KEY
from .base import DeviceCode as DeviceCode
from .base import TraktAuthError as TraktAuthError
from .base import TraktError as TraktError
from .base import TraktFavoritesFull as TraktFavoritesFull
from .base import _dict as _dict
from .base import _iso as _iso
from .base import _positive as _positive
from .base import _typed as _typed
from .base import _when as _when
from .base import activity_stamps as activity_stamps
from .base import entry as entry
from .base import history_body as history_body
from .base import history_play as history_play
from .base import latest_resume as latest_resume
from .base import log as log
from .base import playback_entry as playback_entry
from .base import playback_key as playback_key
from .base import playback_row as playback_row
from .base import repeats as repeats
from .base import scrobble_target as scrobble_target
from .base import show_completed as show_completed
from .base import show_progress as show_progress
from .history import _History


class Trakt(_History):
    def __init__(self, client_id: str, client_secret: str, credentials, timeout: float = 10) -> None:
        self.client_id = client_id
        self.client_secret = client_secret
        self.credentials = credentials
        self.timeout = timeout
        self._lock = threading.Lock()
        self._playback: tuple[float, dict[str, dict]] | None = None  # (cuándo se pidió, {llave: avance})
        self._favorites: tuple[float, str | None, list[dict]] | None = None  # (cuándo, marca de last_activities, títulos)

    def unlink(self) -> None:
        tokens = self._tokens()
        self.credentials.set(TOKENS_KEY, None)
        if tokens:  # que la sesión deje de servir también en Trakt (si no hay internet, da igual)
            try:
                http_json(f"{API}/oauth/revoke", method="POST", timeout=self.timeout,
                          body=self._client(token=tokens["access_token"]))
            except NET_FAILURES:
                pass

    # --- peticiones --------------------------------------------------------------------------
    def _call(self, method: str, path: str, *, body: dict | None = None, auth: bool = True, params: dict | None = None,
              retries: int = RETRIES, idempotent: bool = False):
        """`idempotent`: repetir este POST no cambia nada (poner en Mi lista dos veces es lo mismo), así que la red puede
        reintentarlo ante un 5xx. Una vista o un scrobble no: dos veces es una vista doble en tu historial."""
        headers = {"trakt-api-version": "2", "trakt-api-key": self.client_id}
        if auth:
            headers["Authorization"] = f"Bearer {self._access()}"
        url = f"{API}{path}" + (f"?{urlencode(params)}" if params else "")
        extra: dict = {}
        if retries != RETRIES:  # solo si cambia: los dobles de las pruebas no saben de reintentos
            extra["retries"] = retries
        if idempotent:
            extra["idempotent"] = True
        try:
            return http_json(url, method=method, headers=headers, body=body, timeout=self.timeout, **extra)
        except NET_FAILURES as exc:
            raise TraktError(f"No pude conectar con Trakt: {exc}") from exc
