"""Las versiones de una película o un episodio: se piden a tus complementos, se leen y se ordenan.

Es un paquete: rules (las tablas compartidas con el iPhone, design/streams-rules.json, y lo que sale de ellas),
languages (de qué idioma es cada versión y tus idiomas), source (cómo se lee lo que dice un complemento: tamaño,
calidad, si es al instante), ranking (el orden: puntos por calidad, idioma y semillas; los enlaces para el reproductor) y finder
(StreamFinder: pedirlas a tus complementos a la vez, con caché). Aquí, la fachada, con los mismos nombres de siempre.
"""

from __future__ import annotations

import re  # noqa: F401  (streams.re: las pruebas lo usan)

from .. import addons as addons
from .finder import StreamFinder as StreamFinder
from .languages import ARTICLES as ARTICLES
from .languages import CASTELLANO_TRACK as CASTELLANO_TRACK
from .languages import COUNTRY_LANGUAGES as COUNTRY_LANGUAGES
from .languages import DEFAULT_LANGUAGES as DEFAULT_LANGUAGES
from .languages import DUB_CODES as DUB_CODES
from .languages import EPISODE_MARK as EPISODE_MARK
from .languages import FLAG_RE as FLAG_RE
from .languages import LANGUAGE_CHOICES as LANGUAGE_CHOICES
from .languages import LATIN_NAMES as LATIN_NAMES
from .languages import LATIN_REGIONS as LATIN_REGIONS
from .languages import LATINO_TRACK as LATINO_TRACK
from .languages import MARKS as MARKS
from .languages import SEASON_LETTER as SEASON_LETTER
from .languages import SEASON_RANGE as SEASON_RANGE
from .languages import SEASON_WORD as SEASON_WORD
from .languages import SERIES_EPISODE_MARK as SERIES_EPISODE_MARK
from .languages import SPAIN_NAMES as SPAIN_NAMES
from .languages import SPANISH_VARIANTS as SPANISH_VARIANTS
from .languages import STOPWORDS as STOPWORDS
from .languages import TRACK_LANG as TRACK_LANG
from .languages import YEAR as YEAR
from .languages import Preferences as Preferences
from .languages import _plain as _plain
from .languages import audio_languages as audio_languages
from .languages import heard as heard
from .languages import languages_from_audio as languages_from_audio
from .languages import mentions_title as mentions_title
from .languages import names_another_series as names_another_series
from .languages import original_from_country as original_from_country
from .languages import other_episode as other_episode
from .languages import other_year as other_year
from .languages import other_years as other_years
from .languages import prefs_from_languages as prefs_from_languages
from .languages import season_of as season_of
from .languages import series_years as series_years
from .languages import set_languages as set_languages
from .languages import spanish_dub as spanish_dub
from .languages import track_languages as track_languages
from .languages import valid_languages as valid_languages
from .ranking import COMET_DOUBT as COMET_DOUBT
from .ranking import LANG_POINTS as LANG_POINTS
from .ranking import STEP_BASE as STEP_BASE
from .ranking import STEP_EACH as STEP_EACH
from .ranking import STEP_UNSURE_SPANISH as STEP_UNSURE_SPANISH
from .ranking import WRONG_LANGUAGE as WRONG_LANGUAGE
from .ranking import _encode_component as _encode_component
from .ranking import cache_key as cache_key
from .ranking import encode_stream as encode_stream
from .ranking import is_opensubtitles as is_opensubtitles
from .ranking import language_score as language_score
from .ranking import player_link as player_link
from .ranking import rank as rank
from .ranking import score as score
from .rules import _SIZE as _SIZE
from .rules import _WAITS as _WAITS
from .rules import CACHE_SECONDS as CACHE_SECONDS
from .rules import CODE_LANG as CODE_LANG
from .rules import DUBBED_WORD as DUBBED_WORD
from .rules import EVIDENCE as EVIDENCE
from .rules import FLAG_LANG as FLAG_LANG
from .rules import LANG_CODES as LANG_CODES
from .rules import LANG_NAMES as LANG_NAMES
from .rules import RELEASE_MARKER as RELEASE_MARKER
from .rules import REQUEST_TIMEOUT as REQUEST_TIMEOUT
from .rules import RES as RES
from .rules import RULES as RULES
from .rules import RULES_FILE as RULES_FILE
from .rules import SCRIPT_FREE as SCRIPT_FREE
from .rules import SEEDERS as SEEDERS
from .rules import SERIES_SIZE_FACTOR as SERIES_SIZE_FACTOR
from .rules import SITE as SITE
from .rules import SITE_LANG as SITE_LANG
from .rules import SIZE as SIZE
from .rules import SPANISH as SPANISH
from .rules import SUBS_FROM as SUBS_FROM
from .rules import TOO_BIG_DEFAULT_GB as TOO_BIG_DEFAULT_GB
from .rules import TOO_BIG_GB as TOO_BIG_GB
from .rules import TOO_SMALL_GB as TOO_SMALL_GB
from .rules import UNITS as UNITS
from .rules import WORD_LANG as WORD_LANG
from .rules import _bad as _bad
from .rules import _number as _number
from .rules import _patterns as _patterns
from .rules import _section as _section
from .rules import _table as _table
from .rules import load_rules as load_rules
from .rules import log as log
from .rules import res_class as res_class
from .source import _NOTICE_VIDEO as _NOTICE_VIDEO
from .source import ACCOUNT_NOTICES as ACCOUNT_NOTICES
from .source import CACHE_MAX as CACHE_MAX
from .source import DEBRID_MARK as DEBRID_MARK
from .source import FIND_DEADLINE as FIND_DEADLINE
from .source import PARSE_ERRORS as PARSE_ERRORS
from .source import RETRY_FAILED as RETRY_FAILED
from .source import Source as Source
from .source import _size_number as _size_number
from .source import _who as _who
from .source import addon_kind as addon_kind
from .source import instant_mark as instant_mark
from .source import is_link as is_link
from .source import parse as parse
from .source import stable_index as stable_index
from .source import torrentio_notice as torrentio_notice


