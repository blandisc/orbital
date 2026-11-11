"""Cómo se describe y se ordena una versión (idioma, calidad, la rejilla de «Elegir versión»): funciones sin estado."""

from __future__ import annotations

import logging
import time

from .. import flags, player
from ..library import streams

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


def language_code(code: str | None) -> str | None:
    """Código de pista de mpv ("spa", "es-MX", "eng") -> el de Ajustes ("es", "en"); "" = sin
    subtítulos; None si es otro idioma (no se recuerda)."""
    if code == "":
        return ""
    code = (code or "").lower()
    if code in ("es", "spa", "esl", "esp") or code.startswith(("es-", "es_")):  # «est» es estonio, no español
        return "es"
    if code.startswith("en"):
        return "en"
    return None


def spanish_variant(code: str | None) -> str:
    """El doblaje de una pista o de un ajuste: «es-419» (latino: es-MX, es-419, es-LA…), «es-ES» (castellano) o ""."""
    code = (code or "").lower().replace("_", "-")
    if not code.startswith("es-"):
        return ""
    return "es-ES" if code == "es-es" else "es-419"


SUBTITLE_LINES = {"": "Sin subtítulos", "forced": "Solo traducciones en pantalla"}


def version_line(source: streams.Source, prefs: streams.Preferences, subtitles: str) -> str:
    """Lo que va a sonar con «Ver», en palabras: «Latino · 1080p · Sin subtítulos». El doblaje solo si el nombre de la
    fuente lo dice (si no, «Español»); el idioma que pediste si la fuente lo trae, si no el que trae."""
    lang = version_lang(source, prefs)
    name = source.dub.capitalize() if lang == "es" and source.dub else streams.LANG_NAMES.get(lang, lang)
    subs = SUBTITLE_LINES.get(subtitles) or f"Subtítulos en {streams.LANG_NAMES.get(subtitles, subtitles).lower()}"
    return " · ".join(p for p in (name, source.resolution, subs) if p)


def version_lang(source: streams.Source, prefs: streams.Preferences) -> str:
    """El idioma de lo que va a sonar con «Ver» (el de `version_line`): la ficha lo pone como bandera («🇲🇽 · 1080p»)."""
    return prefs.audio if prefs.audio in source.languages else (source.languages or [""])[0]


WANTED_NAMES = {"es-419": "latino", "es-ES": "castellano"}


def version_note(source: streams.Source, prefs: streams.Preferences) -> str | None:
    """Si lo que va a sonar se sale de lo que pediste para ese título: «Solo en castellano: no hay latino», «No hay en
    inglés: va en español». None si es lo pedido (lo normal no se anuncia)."""
    lang = (source.languages or [""])[0]
    have = source.dub if lang == "es" and source.dub else streams.LANG_NAMES.get(lang, lang).lower()
    if prefs.audio not in source.languages:
        want = WANTED_NAMES.get(prefs.spanish) if prefs.audio == "es" and prefs.spanish else streams.LANG_NAMES.get(prefs.audio, prefs.audio).lower()
        return f"No hay en {want}: va en {have}"
    if prefs.audio == "es" and prefs.spanish in WANTED_NAMES and source.dub and streams.DUB_CODES.get(source.dub) != prefs.spanish:
        return f"Solo en {source.dub}: no hay {WANTED_NAMES[prefs.spanish]}"
    return None


def choice_line(fields: dict) -> str:
    """Lo que recuerda un título, en palabras: «Latino · Sin subtítulos», «Inglés · Subtítulos en español»."""
    audio = fields.get("audio")
    name = WANTED_NAMES.get(fields.get("spanish") or "", "").capitalize() if audio == "es" else ""
    parts = [name or (streams.LANG_NAMES.get(audio, audio) if audio else "")]
    if isinstance(fields.get("subtitles"), str):
        subs = fields["subtitles"]
        parts.append(SUBTITLE_LINES.get(subs) or f"Subtítulos en {streams.LANG_NAMES.get(subs, subs).lower()}")
    return " · ".join(p for p in parts if p)


def handoff_pick(handoff: dict) -> dict | None:
    """Las pistas que venía usando el iPhone, como las recuerda la TV («Continuar»): los subtítulos (o sin) y el audio."""
    sub, audio = handoff.get("subtitle"), handoff.get("audio")
    pick = dict(sub) if isinstance(sub, dict) else {}
    if isinstance(audio, dict):
        pick["audio"] = audio
    return pick or None


def source_label(source: streams.Source, long: bool = False) -> str:
    """"1080p · Al instante" / "4K HDR · Torrentio": de dónde viene lo que ves, en pocas palabras."""
    quality = " ".join(p for p in (source.resolution or "SD", *source.hdr[:1]) if p)
    parts = [quality, "Al instante" if source.cached else source.addon]
    if long:
        parts.append(" + ".join(streams.LANG_NAMES.get(l, l) for l in source.languages[:2]))
        if source.size:
            parts.append(f"{source.size / 1e9:.1f} GB")
    return " · ".join(p for p in parts if p)


def player_source_label(source: streams.Source) -> str:
    """"Español · 1080p · Al instante · 1.2 GB": el idioma primero, que es lo que se busca al cambiar."""
    langs = " + ".join(streams.LANG_NAMES.get(lang, lang) for lang in source.languages[:2])
    size = f"{source.size / 1e9:.1f} GB" if source.size else ""
    return " · ".join(p for p in (langs, source_label(source), size) if p)


def player_ui_day(when: float) -> str:
    """«el viernes 6», «mañana», «hoy a las 9 p. m.»: cuándo sale algo, como lo dice la interfaz."""
    from datetime import UTC, datetime, timedelta

    # Cinemeta da el estreno como un día (medianoche UTC): en México eso era la tarde del día anterior y decía «sale el
    # jueves 17» de lo que sale el viernes 18 (error 3 del iPhone). Un día se dice en UTC; una hora, en la tuya.
    day = datetime.fromtimestamp(when, UTC).replace(tzinfo=None) if when % 86400 == 0 else datetime.fromtimestamp(when)
    today = datetime.fromtimestamp(time.time()).date()
    if day.date() == today:
        return "hoy"
    if day.date() == today + timedelta(days=1):
        return "mañana"
    names = ("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")
    return f"el {names[day.weekday()]} {day.day}"


FALLBACK_TRIES = 6  # versiones que se prueban solas antes de rendirse (primero tu idioma, luego otro)


def ready_now(source: streams.Source) -> bool:
    """Arranca ya y es de verdad este título: está en Real-Debrid, o no pasa por él (un enlace directo). Una «Hay que
    bajarla» solo da el video de aviso de 30 s de Real-Debrid; una grabada en el cine, un tráiler o una que parece de otro
    título no cuentan («El viento tiene miedo»: se ofrecía «Verlo al instante» con una que no era)."""
    return (source.cached or not source.debrid) and not ({"CAM", "Tráiler"} & set(source.tags)) and not source.doubtful


def fallback_source(found: list[streams.Source], audio: str, native: bool = True) -> streams.Source | None:
    """La versión que se prueba sola cuando una falla (Fernando, 2 nov 2026: «checar otras versiones en ese idioma y después
    en otro idioma»): primero las de tu idioma que arrancan ya, luego las de otro idioma que arrancan ya. Nunca una
    grabación de cine ni un tráiler, ni una que Real-Debrid aún no tiene. `found` viene ordenada de mejor a peor."""
    usable = [s for s in found if ready_now(s) and not ({"CAM", "Tráiler"} & set(s.tags))
              and (not native or player.stream_url(s.stream) or s.stream.get("onedrive"))]
    mine = [s for s in usable if audio in s.languages]
    return (mine or usable or [None])[0]


def give_up_words(title: str, left: list[streams.Source], audio: str) -> tuple[str, str]:
    """Por qué no se pudo y qué hacer, en palabras (aviso con título y detalle)."""
    language = streams.LANG_NAMES.get(audio, audio)
    if any(audio in s.languages and s.debrid and not s.cached for s in left):
        return (f"{title} todavía no está en la nube en {language.lower()}",
                "Pídelo a la nube desde la ficha: lo baja y te aviso cuando esté")
    if any(not s.cached and s.debrid for s in left):
        return f"{title} todavía no está en la nube", "Pídelo a la nube desde la ficha: lo baja y te aviso cuando esté"
    return f"No pude abrir ninguna versión de {title}", "Las que hay no abrieron · inténtalo más tarde o elige otra con Y"


VERSION_RES = ("4K", "1080p", "720p", "SD")


JUNK_TAGS = {"CAM", "Tráiler", "3D"}


def _sure(how: str) -> bool:
    return streams.EVIDENCE.get(how, 0) >= streams.EVIDENCE["original"]


def version_rows(found: list[streams.Source], prefs: streams.Preferences, current: int | None = None) -> list[dict]:
    """Las versiones en una lista («Latino · 1080p», con «Al instante · 2.1 GB» a la derecha): version_grid, renglón por
    renglón."""
    return [{"id": cell["id"], "label": f"{row['label']} · {cell['label']}",
             "hint": " · ".join(p for p in (cell["doubt"], cell["hint"], cell["size"]) if p), "current": cell["current"]}
            for row in version_grid(found, prefs, current) for cell in row["cells"]]


QUALITY_ORDER = ("4K", "1080p", "720p", "SD")


LATIN_ORDER = ("original", "en", "es-ES")  # el orden por omisión con latino (Fernando, 3 nov), como Preferences.latinOrder


def _quality(src: streams.Source) -> str:
    res = streams.res_class(src.resolution)
    return res if res in QUALITY_ORDER else "SD"


def _row_code(code: str, how: str) -> str:
    """La fila de un idioma (como SourcesModel.rowCode del iPhone): el español «tal vez» va a «Español (no dice cuál)»."""
    base = code.split("-")[0]
    if base == "es":
        return code if how != "maybe" else "es"
    return base


def version_layout(found: list[streams.Source], prefs: streams.Preferences,
                   refused: set[str] | frozenset[str] = frozenset()) -> tuple[list[dict], list[dict], int]:
    """«Versión», con las reglas del iPhone (SourcesModel.languageRows; los escenarios comunes lo comparan): una fila por
    idioma; en cada calidad, la mejor según el orden general (nunca una de otro título u otro episodio si hay otra); SD solo
    si ese idioma no tiene nada mejor (salvo la recomendada); las filas en tu orden. Devuelve (las de tu orden, «más
    idiomas», cuántas se esconden). Cada fila: {"code", "original", "options": [{"res", "source", "how", "all"}]}."""
    visible = [s for s in found if not {"CAM", "Tráiler"} & set(s.tags)] or found
    recommended = visible[0].index if visible else None
    cells: dict[str, dict[str, list[streams.Source]]] = {}
    how_of: dict[tuple[str, int], str] = {}
    order: list[str] = []
    originals: set[str] = set()
    original_row = _row_code(prefs.original, "name") if prefs.original else None
    for src in visible:
        placed: set[str] = set()
        langs = src.audio_langs or {code: "assumed" for code in src.languages}
        for code, how in langs.items():
            row = _row_code(code, how)
            if row not in cells:
                order.append(row)
                cells[row] = {}
            if row not in placed:
                placed.add(row)
                cells[row].setdefault(_quality(src), []).append(src)
            key = (row, src.index)
            if key not in how_of or streams.EVIDENCE.get(how, 0) > streams.EVIDENCE.get(how_of[key], 0):
                how_of[key] = how
            if how == "original" or row == original_row:
                originals.add(row)
    want = prefs.spanish if prefs.audio == "es" and prefs.spanish in streams.SPANISH_VARIANTS else prefs.audio
    plan = list(prefs.plan) if prefs.plan else list(LATIN_ORDER) if want == "es-419" else []
    plan = [c for c in dict.fromkeys(plan) if c != want]

    def build(code: str) -> dict:
        options = []
        for q in QUALITY_ORDER:
            # Estable: lo dudoso y lo que Real-Debrid no dejó bajar (FQ2-A), al final de su casilla.
            listed = sorted(cells[code].get(q, []), key=lambda s: (s.doubtful, not s.cached and s.info_hash in refused))
            if listed:
                best = listed[0]
                options.append({"res": q, "source": best, "how": how_of.get((code, best.index), "maybe"),
                                "all": [s.index for s in listed]})
        if len(options) > 1:
            options = [o for o in options if o["res"] != "SD" or o["source"].index == recommended]
        return {"code": code, "original": code in originals, "options": options}

    def rank(row: dict) -> int:
        code = row["code"]
        yours = code == want or (len(want) == 2 and code.startswith(want))
        if code == want and (len(want) > 2 or not want.startswith("es")):
            return 0
        if yours:
            return 2 if code == "es" else 1
        if code == "es" and want.startswith("es"):
            return 2
        place = next((i for i, c in enumerate(plan) if (row["original"] if c == "original" else c == code)), None)
        if place is not None:
            return 3 + place
        if row["original"]:
            return 15
        if code.startswith("es"):
            return 20
        return 30

    rows = [r for r in (build(code) for code in order) if r["options"]]
    count = {id(r): sum(len(o["all"]) for o in r["options"]) for r in rows}
    ranked = sorted(enumerate(rows), key=lambda x: (rank(x[1]), -count[id(x[1])], x[0]))
    rows = [r for _, r in ranked]
    return [r for r in rows if rank(r) < 30], [r for r in rows if rank(r) == 30], len(found) - len(visible)


def version_grid(found: list[streams.Source], prefs: streams.Preferences, current: int | None = None,
                 refused: set[str] | frozenset[str] = frozenset()) -> list[dict]:
    """Y › Versión en el reproductor, lo mismo que «Versión» de la ficha: las filas de version_layout (las de tu orden y
    luego las demás), cada una con su mejor versión por calidad. La puesta se marca en su idioma y calidad.
    [{"label": "Latino", "cells": [{"id", "label": "1080p", "hint": "Al instante", "size", "doubt", "addon", "current"}]}]"""
    main, more, _ = version_layout(found, prefs, refused)
    out = []
    for row in [*main, *more]:
        name = streams.LANG_NAMES.get(row["code"], row["code"]) if row["code"] else "Sin idioma"
        cells = []
        for option in row["options"]:
            src = option["source"]
            cells.append({"id": src.index, "label": " ".join(p for p in (option["res"], *src.hdr[:1]) if p),
                          "hint": "Al instante" if src.cached else "Hay que bajarla",
                          "size": f"{src.size / 1e9:.1f} GB" if src.size else "",
                          "doubt": "Idioma dudoso" if option["how"] == "maybe" else "",
                          "addon": src.kind,  # Ⓣ Torrentio, Ⓒ Comet o la pieza, junto a la calidad (addon_kind)
                          "current": current is not None and current in option["all"]})
        out.append({"label": name, "flag": flags.flag_for(row["code"]), "cells": cells})
    return out
