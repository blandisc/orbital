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
    # V5 (24 nov 2026): más idiomas con su nombre; antes, uno fuera de la tabla salía como código («HEB», «tha»).
    "pt-br": "Portugués de Brasil", "pt-pt": "Portugués de Portugal", "ca": "Catalán", "cat": "Catalán",
    "eu": "Euskera", "eus": "Euskera", "baq": "Euskera", "gl": "Gallego", "glg": "Gallego", "da": "Danés", "dan": "Danés",
    "no": "Noruego", "nor": "Noruego", "nb": "Noruego", "nob": "Noruego", "nn": "Noruego", "nno": "Noruego",
    "fi": "Finés", "fin": "Finés", "is": "Islandés", "ice": "Islandés", "isl": "Islandés", "el": "Griego", "gre": "Griego",
    "ell": "Griego", "he": "Hebreo", "iw": "Hebreo", "heb": "Hebreo", "fa": "Persa", "per": "Persa", "fas": "Persa",
    "th": "Tailandés", "tha": "Tailandés", "vi": "Vietnamita", "vie": "Vietnamita", "id": "Indonesio", "ind": "Indonesio",
    "ms": "Malayo", "may": "Malayo", "msa": "Malayo", "tl": "Tagalo", "tgl": "Tagalo", "fil": "Filipino",
    "ro": "Rumano", "rum": "Rumano", "ron": "Rumano", "bg": "Búlgaro", "bul": "Búlgaro", "hr": "Croata", "hrv": "Croata",
    "sr": "Serbio", "srp": "Serbio", "bs": "Bosnio", "bos": "Bosnio", "sl": "Esloveno", "slv": "Esloveno",
    "sk": "Eslovaco", "slo": "Eslovaco", "slk": "Eslovaco", "mk": "Macedonio", "mac": "Macedonio", "mkd": "Macedonio",
    "sq": "Albanés", "alb": "Albanés", "sqi": "Albanés", "lt": "Lituano", "lit": "Lituano", "lv": "Letón", "lav": "Letón",
    "et": "Estonio", "est": "Estonio", "be": "Bielorruso", "bel": "Bielorruso", "ka": "Georgiano", "geo": "Georgiano",
    "kat": "Georgiano", "hy": "Armenio", "arm": "Armenio", "hye": "Armenio", "az": "Azerí", "aze": "Azerí",
    "kk": "Kazajo", "kaz": "Kazajo", "ur": "Urdu", "urd": "Urdu", "bn": "Bengalí", "ben": "Bengalí", "ta": "Tamil",
    "tam": "Tamil", "te": "Telugu", "tel": "Telugu", "ml": "Malayalam", "mal": "Malayalam", "kn": "Canarés", "kan": "Canarés",
    "mr": "Maratí", "mar": "Maratí", "pa": "Panyabí", "pan": "Panyabí", "gu": "Guyaratí", "guj": "Guyaratí",
    "zh-tw": "Chino tradicional", "zh-hant": "Chino tradicional", "zh-cn": "Chino simplificado", "zh-hans": "Chino simplificado",
    "yue": "Cantonés", "cmn": "Mandarín", "la": "Latín", "lat": "Latín", "cy": "Galés", "wel": "Galés", "cym": "Galés",
    "ga": "Irlandés", "gle": "Irlandés", "af": "Afrikáans", "afr": "Afrikáans", "sw": "Suajili", "swa": "Suajili",
    "qu": "Quechua", "que": "Quechua", "gn": "Guaraní", "grn": "Guaraní", "nah": "Náhuatl", "eo": "Esperanto", "epo": "Esperanto",
}

# Sin idioma de verdad: «und» (sin decir), «mul» (varios), «zxx» (sin palabras). Mejor nada que un código.
NO_LANGUAGE = {"und", "mul", "zxx", "mis", "qaa", "none", "unknown"}

# El audio con el nombre que conoce quien lo ve (V5): «Dolby Digital Plus», no «E-AC3». Lo que no aporta (mp3, opus,
# vorbis, flac, pcm: el oído no lo distingue y nadie elige por él) no se dice.
CODECS = {"eac3": "Dolby Digital Plus", "e-ac3": "Dolby Digital Plus", "ac3": "Dolby Digital", "truehd": "Dolby TrueHD",
          "mlp": "Dolby TrueHD", "dts": "DTS", "dca": "DTS", "dtshd": "DTS-HD", "dts-hd": "DTS-HD", "aac": "AAC"}


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
    """El nombre del idioma en español («Inglés», «Español latino»). Con región que no está en la tabla («en-US», «fr_CA»), el
    del idioma; uno que no se conoce, «Otro idioma» (V5: antes salía el código, «HEB»); sin idioma («und»), nada."""
    if not code:
        return ""
    key = str(code).strip().lower().replace("_", "-")
    if not key or key in NO_LANGUAGE:
        return ""
    if key in LANGUAGES:
        return LANGUAGES[key]
    base = key.split("-", 1)[0]
    return LANGUAGES.get(base) or ("" if base in NO_LANGUAGE else "Otro idioma")


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
# Títulos de pista que no dicen nada («Subtítulos», «Subs»): no se repiten junto al idioma.
GENERIC = {"subtítulos", "subtitulos", "subtitles", "subtitle", "subs", "sub", "audio", "track", "pista"}
VARIANTS = {"latino", "latinoamérica", "latinoamericano", "castellano", "españa", "méxico", "brasil", "portugal", "francia", "canadá"}


def track_label(track: dict) -> str:
    """'Inglés · 5.1 · Dolby Digital Plus' / 'Español latino · Estéreo' / 'Español · Forzados' / 'Pista 3'."""
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
    elif title and lowered not in GENERIC and language(track.get("lang")).lower() not in lowered and len(title) <= 28:
        parts.append(title)
    if track.get("type") == "audio":
        channels = track.get("demux-channel-count") or track.get("audio-channels")
        if isinstance(channels, int):
            parts.append({1: "Mono", 2: "Estéreo", 6: "5.1", 8: "7.1"}.get(channels, f"{channels} canales"))
        codec = CODECS.get(str(track.get("codec") or "").lower())
        if codec:
            parts.append(codec)
    if track.get("external"):
        parts.append("de tus complementos")   # «addon» no se dice en la app (26 nov 2026)
    label = " · ".join(p for p in parts if p)
    return label or f"Pista {track.get('id', '')}".strip()


def track_labels(tracks: list[dict]) -> list[str]:
    """Los nombres de una lista de pistas, sin dos iguales: «Español» y «Español» se ven idénticos y no se sabe cuál
    tocar (26 nov 2026), así que los repetidos llevan su número («Español · Opción 1», «Español · Opción 2»)."""
    labels = [track_label(t) for t in tracks]
    count: dict[str, int] = {}
    seen: dict[str, int] = {}
    for label in labels:
        count[label] = count.get(label, 0) + 1
    out = []
    for label in labels:
        if count[label] > 1:
            seen[label] = seen.get(label, 0) + 1
            label = f"{label} · Opción {seen[label]}"
        out.append(label)
    return out


def current_label(tracks: list[dict], kind: str) -> str:
    chosen = next((t for t in tracks if t.get("type") == kind and t.get("selected")), None)
    if chosen is None:
        return "No" if kind == "sub" else "—"
    return language(chosen.get("lang")) or track_label(chosen)


def current_flag(tracks: list[dict]) -> str | None:
    """La bandera del audio que suena (None si no hay pista o su idioma no tiene país)."""
    chosen = next((t for t in tracks if t.get("type") == "audio" and t.get("selected")), None)
    return flags.flag_for(chosen.get("lang"), str(chosen.get("title") or "")) if chosen else None
