"""Lo que el reproductor dibuja encima del video (ASS de libass, el formato que mpv pinta), con la paleta de Orbital.

Es un paquete: canvas (el lienzo, con qué se maneja —mando, teclado o dedo— y el tamaño del texto; los colores y las
medidas), labels (los nombres de idiomas y pistas), draw (las figuras, el vidrio, los íconos y el texto), hud (la barra
de abajo y la pausa), panels (los paneles de pistas, Más y episodios) y overlays (probar subtítulos, la TV en vivo, la
tarjeta del siguiente episodio, avisos, volumen, la ventanita y el telón). Aquí, la fachada, con los mismos nombres de
siempre (`player_ui.…`).

W, TOUCH, KEYBOARD y _text_scale cambian mientras corre (set_canvas, set_input, set_text_size) y viven solo en
canvas.py: las piezas los leen como `canvas.W`, y `player_ui.W` (lo que leen el reproductor y las pruebas) los pide a
canvas.py en el momento (ver __getattr__ abajo). Para cambiarlos en una prueba: `monkeypatch.setattr(player_ui.canvas, …)`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from . import canvas as canvas
from .canvas import EDGE_TOKENS as EDGE_TOKENS
from .canvas import FLAG_GAP as FLAG_GAP
from .canvas import FLAG_H as FLAG_H
from .canvas import FONT as FONT
from .canvas import FONT_SEMI as FONT_SEMI
from .canvas import FS as FS
from .canvas import GLASS_TOKENS as GLASS_TOKENS
from .canvas import GLYPH as GLYPH
from .canvas import GLYPH_SOLID as GLYPH_SOLID
from .canvas import KEY_NAMES as KEY_NAMES
from .canvas import LIVE as LIVE
from .canvas import LOGO_BOX as LOGO_BOX
from .canvas import MARGIN as MARGIN
from .canvas import MUTED as MUTED
from .canvas import NEXT as NEXT
from .canvas import ON_LIGHT as ON_LIGHT
from .canvas import PALETTE as PALETTE
from .canvas import PANEL as PANEL
from .canvas import RADIUS_CARD as RADIUS_CARD
from .canvas import SHADE as SHADE
from .canvas import SOFT as SOFT
from .canvas import TEXT as TEXT
from .canvas import TEXT_SCALES as TEXT_SCALES
from .canvas import H as H
from .canvas import ass_color as ass_color
from .canvas import hit as hit
from .canvas import placed as placed
from .canvas import set_canvas as set_canvas
from .canvas import set_input as set_input
from .canvas import set_text_size as set_text_size
from .canvas import set_touch as set_touch
from .canvas import targets as targets
from .draw import _ALPHA as _ALPHA
from .draw import _NARROW as _NARROW
from .draw import _NUMBER as _NUMBER
from .draw import ICON_PATHS as ICON_PATHS
from .draw import SHADE_BUDGET as SHADE_BUDGET
from .draw import _alpha as _alpha
from .draw import _shape as _shape
from .draw import arc as arc
from .draw import circle as circle
from .draw import fade as fade
from .draw import fit as fit
from .draw import glass as glass
from .draw import glass_fill as glass_fill
from .draw import glyph as glyph
from .draw import gradient as gradient
from .draw import hints as hints
from .draw import hints_width as hints_width
from .draw import icon as icon
from .draw import ring as ring
from .draw import rrect as rrect
from .draw import rrect_path as rrect_path
from .draw import side_gradient as side_gradient
from .draw import text as text
from .draw import text_width as text_width
from .draw import wrap as wrap
from .draw import wrap_sentences as wrap_sentences
from .hud import BAR_Y as BAR_Y
from .hud import Hud as Hud
from .hud import _times as _times
from .hud import _touch_bar as _touch_bar
from .hud import _touch_items as _touch_items
from .hud import buttons as buttons
from .hud import chapter_at as chapter_at
from .hud import hud_ass as hud_ass
from .hud import info_ass as info_ass
from .hud import info_line as info_line
from .hud import paused_ass as paused_ass
from .hud import pills as pills
from .hud import pills_width as pills_width
from .hud import progress_bar as progress_bar
from .labels import LANGUAGES as LANGUAGES
from .labels import VARIANTS as VARIANTS
from .labels import clock as clock
from .labels import current_flag as current_flag
from .labels import current_label as current_label
from .labels import esc as esc
from .labels import language as language
from .labels import sub_kind as sub_kind
from .labels import track_label as track_label
from .overlays import BUFFER_Y as BUFFER_Y
from .overlays import CARD_RISE as CARD_RISE
from .overlays import EXTRA as EXTRA
from .overlays import LIVE_STATUS as LIVE_STATUS
from .overlays import NOTICE_Y as NOTICE_Y
from .overlays import PIP_BUTTON as PIP_BUTTON
from .overlays import PIP_PLAY as PIP_PLAY
from .overlays import STILL_BOX as STILL_BOX
from .overlays import TRY_H as TRY_H
from .overlays import TRY_ROWS as TRY_ROWS
from .overlays import TRY_TOUCH_H as TRY_TOUCH_H
from .overlays import VOLUME_NORMAL as VOLUME_NORMAL
from .overlays import VOLUME_TOP as VOLUME_TOP
from .overlays import LiveHud as LiveHud
from .overlays import SubTrial as SubTrial
from .overlays import _downloads as _downloads
from .overlays import _entering as _entering
from .overlays import _line_path as _line_path
from .overlays import channels_panel as channels_panel
from .overlays import curtain_ass as curtain_ass
from .overlays import ease_out as ease_out
from .overlays import lines_of as lines_of
from .overlays import live_hud_ass as live_hud_ass
from .overlays import live_info_line as live_info_line
from .overlays import muted_ass as muted_ass
from .overlays import pip_ass as pip_ass
from .overlays import quit_hold_ass as quit_hold_ass
from .overlays import seek_label as seek_label
from .overlays import skip_ass as skip_ass
from .overlays import speaker as speaker
from .overlays import sub_trial_ass as sub_trial_ass
from .overlays import toast_ass as toast_ass
from .overlays import toast_seconds as toast_seconds
from .overlays import try_items as try_items
from .overlays import try_pills as try_pills
from .overlays import upnext_ass as upnext_ass
from .overlays import volume_ass as volume_ass
from .panels import ADDON_MARKS as ADDON_MARKS
from .panels import CELL_ICON as CELL_ICON
from .panels import CELL_STATES as CELL_STATES
from .panels import GRID_NAME as GRID_NAME
from .panels import ICON_COLUMNS as ICON_COLUMNS
from .panels import ICON_SIZE as ICON_SIZE
from .panels import PANEL_BOTTOM as PANEL_BOTTOM
from .panels import PANEL_INSET as PANEL_INSET
from .panels import PANEL_ROWS as PANEL_ROWS
from .panels import PANEL_TOP as PANEL_TOP
from .panels import ROWS_BOTTOM as ROWS_BOTTOM
from .panels import ROWS_TOP as ROWS_TOP
from .panels import SUB_SCALES as SUB_SCALES
from .panels import SUB_STEP as SUB_STEP
from .panels import TAB_NAMES as TAB_NAMES
from .panels import Column as Column
from .panels import Panel as Panel
from .panels import _column as _column
from .panels import _grid_rows as _grid_rows
from .panels import _icon_row_lines as _icon_row_lines
from .panels import _icon_rows as _icon_rows
from .panels import cell_states as cell_states
from .panels import delay_label as delay_label
from .panels import episodes_column as episodes_column
from .panels import legend_items as legend_items
from .panels import legend_width as legend_width
from .panels import more_panel as more_panel
from .panels import panel_ass as panel_ass
from .panels import states_legend as states_legend
from .panels import sub_scale_label as sub_scale_label
from .panels import sync_options as sync_options
from .panels import track_options as track_options
from .panels import tracks_panel as tracks_panel

_LIVE = ("W", "TOUCH", "KEYBOARD", "_text_scale")  # cambian mientras corre: viven en canvas.py
if TYPE_CHECKING:  # para los tipos (en ejecución los da __getattr__)
    from .canvas import KEYBOARD as KEYBOARD
    from .canvas import TOUCH as TOUCH
    from .canvas import W as W
    from .canvas import _text_scale as _text_scale


def __getattr__(name: str):
    """`player_ui.W` (y TOUCH, KEYBOARD, _text_scale) es siempre el de ahora: se lee de canvas.py, donde vive."""
    if name in _LIVE:
        return getattr(canvas, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
