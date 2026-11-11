"""Los nombres que enseña el reproductor: idiomas, pistas de audio y subtítulos, y su bandera."""

from __future__ import annotations

import math

from .. import flags

LANGUAGES = {
    "en": "Inglés", "eng": "Inglés", "es": "Español", "spa": "Español", "es-419": "Español latino", "es-mx": "Español latino", "es-es": "Castellano",
    "fr": "Francés", "fre": "Francés", "fra": "Francés", "it": "Italiano", "ita": "Italiano", "de": "Alemán",
    "ger": "Alemán", "deu": "Alemán", "pt": "Portugués", "por": "Portugués", "ja": "Japonés", "jpn": "Japonés",
    "ko": "Coreano", "kor": "Coreano", "zh": "Chino", "chi": "Chino", "zho": "Chino", "ru": "Ruso", "rus": "Ruso",
    "cs": "Checo", "cze": "Checo", "ces": "Checo", "pl": "Polaco", "pol": "Polaco", "hu": "Húngaro", "hun": "Húngaro",
    "tr": "Turco", "tur": "Turco", "ar": "Árabe", "ara": "Árabe", "hi": "Hindi", "hin": "Hindi", "nl": "Neerlandés",
    "dut": "Neerlandés", "nld": "Neerlandés", "sv": "Sueco", "swe": "Sueco", "uk": "Ucraniano", "ukr": "Ucraniano",
}


def esc(value: str) -> str:
    """Texto seguro para ASS (las llaves abren etiquetas)."""
    return str(value).replace("\\", "⧵").replace("{", "(").replace("}", ")").replace("\n", " ")


def clock(seconds: float | None) -> str:
    if not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 0:
        return "--:--"
    s = int(seconds)
    h, m, s = s // 3600, s % 3600 // 60, s % 60
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def language(code: str | None) -> str:
    if not code:
        return ""
    return LANGUAGES.get(code.lower(), code.upper() if len(code) <= 3 else code)


def sub_kind(track: dict) -> str:
    """«forced» (solo los letreros), «sdh» (para sordos: con [música], [risas]…) o «normal»."""
    title = str(track.get("title") or "").strip().lower()
    if track.get("forced") or "forced" in title or "forzad" in title:
        return "forced"
    if track.get("hearing-impaired") or "sdh" in title or title == "cc" or "sordos" in title or "hearing" in title:
        return "sdh"
    return "normal"


# La variante de un idioma va pegada a él («Español latino», no «Español · Latino»): un separador menos y el nombre del audio
# cabe en su columna (RE-1, 2 nov 2026: se cortaba en «Español · Latino · Estér…»).
VARIANTS = {"latino", "latinoamérica", "latinoamericano", "castellano", "españa", "méxico", "brasil", "portugal", "francia", "canadá"}


def track_label(track: dict) -> str:
    """'Inglés · 5.1 · E-AC3' / 'Español latino · Estéreo' / 'Español · Forzados' / 'Pista 3'."""
    parts = [language(track.get("lang"))]
    title = (track.get("title") or "").strip()
    lowered = title.lower()
    kind = sub_kind(track)
    if kind == "forced":
        parts.append("Forzados")
    elif kind == "sdh":
        parts.append("Para sordos")
    elif title and lowered in VARIANTS and parts[0]:
        parts[0] = f"{parts[0]} {lowered}"
    elif title and language(track.get("lang")).lower() not in lowered and len(title) <= 28:
        parts.append(title)
    if track.get("type") == "audio":
        channels = track.get("demux-channel-count") or track.get("audio-channels")
        if isinstance(channels, int):
            parts.append({1: "Mono", 2: "Estéreo", 6: "5.1", 8: "7.1"}.get(channels, f"{channels} canales"))
        if track.get("codec"):
            parts.append(str(track["codec"]).upper().replace("EAC3", "E-AC3"))
    if track.get("external"):
        parts.append("de tu addon")
    label = " · ".join(p for p in parts if p)
    return label or f"Pista {track.get('id', '')}".strip()


def current_label(tracks: list[dict], kind: str) -> str:
    chosen = next((t for t in tracks if t.get("type") == kind and t.get("selected")), None)
    if chosen is None:
        return "No" if kind == "sub" else "—"
    return language(chosen.get("lang")) or track_label(chosen)


def current_flag(tracks: list[dict]) -> str | None:
    """La bandera del audio que suena (None si no hay pista o su idioma no tiene país)."""
    chosen = next((t for t in tracks if t.get("type") == "audio" and t.get("selected")), None)
    return flags.flag_for(chosen.get("lang"), str(chosen.get("title") or "")) if chosen else None
