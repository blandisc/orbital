"""Servidor HTTP: sirve la interfaz web y la API (API_PORT, local) y el puerto público (Alexa, el iPhone, el túnel).

Es un paquete: base (quién pregunta —local o de fuera—, la clave, los tipos de archivo, la carpeta web y el guardia de
claves equivocadas), phone (lo que manda el iPhone y la página para escribir en la tele), public (el puerto público:
qué rutas se abren afuera y con qué clave) y app (la app local con todas sus rutas). Aquí, la fachada, con los mismos
nombres de siempre (`create_app`, `create_public_app`, `FailedTokens`…).
"""

from __future__ import annotations

from ..api.play import humane_error  # noqa: F401 - se importa desde aquí
from ..api.ui import SETTINGS  # noqa: F401
from .app import create_app as create_app
from .base import _FORWARD_HEADERS as _FORWARD_HEADERS
from .base import _LOCAL_HOSTNAMES as _LOCAL_HOSTNAMES
from .base import STORE_DELAY as STORE_DELAY
from .base import WEB_DIR as WEB_DIR
from .base import WEB_TYPES as WEB_TYPES
from .base import EventBus as EventBus
from .base import FailedTokens as FailedTokens
from .base import WebFiles as WebFiles
from .base import emulator_updates_for as emulator_updates_for
from .base import invalid_request as invalid_request
from .base import is_local_request as is_local_request
from .base import log as log
from .base import paused_path as paused_path
from .base import register_web_types as register_web_types
from .base import token_ok as token_ok
from .phone import KEY_REQUIRED as KEY_REQUIRED
from .phone import MEDIA_ID as MEDIA_ID
from .phone import QUICK_CODE_WRONG as QUICK_CODE_WRONG
from .phone import RD_FORM as RD_FORM
from .phone import RD_LEAD as RD_LEAD
from .phone import REMOTE_HEADERS as REMOTE_HEADERS
from .phone import REMOTE_PAGE as REMOTE_PAGE
from .phone import ChoiceChange as ChoiceChange
from .phone import ChoicesSync as ChoicesSync
from .phone import CompanionAck as CompanionAck
from .phone import CompanionConsole as CompanionConsole
from .phone import CompanionGame as CompanionGame
from .phone import CompanionInput as CompanionInput
from .phone import CompanionPlayerAction as CompanionPlayerAction
from .phone import CompanionSend as CompanionSend
from .phone import CompanionText as CompanionText
from .phone import KeyRequired as KeyRequired
from .phone import ResumeIn as ResumeIn
from .phone import ResumeSync as ResumeSync
from .phone import ResumeTrack as ResumeTrack
from .phone import _companion_routes as _companion_routes
from .phone import _remote_input_routes as _remote_input_routes
from .phone import bearer as bearer
from .phone import device_of as device_of
from .phone import forget_device as forget_device
from .phone import key_required as key_required
from .phone import remote_page as remote_page
from .phone import resume_for_device as resume_for_device
from .phone import resume_from_device as resume_from_device
from .phone import save_debrid_key as save_debrid_key
from .phone import with_key as with_key
from .public import MAX_PUBLIC_BODY as MAX_PUBLIC_BODY
from .public import _foryou_public_routes as _foryou_public_routes
from .public import _is_game_list as _is_game_list
from .public import _volume as _volume
from .public import create_public_app as create_public_app


