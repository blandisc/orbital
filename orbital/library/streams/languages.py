"""De qué idioma es cada versión (banderas, palabras, pistas oídas), si es otra serie u otro año, y tus idiomas."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from typing import TYPE_CHECKING

from .rules import (
    CODE_LANG,
    DUBBED_WORD,
    EVIDENCE,
    FLAG_LANG,
    RELEASE_MARKER,
    SCRIPT_FREE,
    SITE_LANG,
    SPANISH,
    SUBS_FROM,
    WORD_LANG,
)

if TYPE_CHECKING:
    from .source import Source


FLAG_RE = re.compile("|".join(map(re.escape, FLAG_LANG)) or r"(?!)")  # sin tabla, ninguna bandera

MARKS = re.compile(r"\b(Dubbed|Dual Audio|Multi Audio|Multi Subs)\b")


def audio_languages(words: str, marks: str = "", site: str = "", original: str | None = None) -> dict[str, str]:
    """Los idiomas de AUDIO de una fuente y cómo lo sabemos (EVIDENCE), de lo que dicen el nombre, el sitio y las marcas de
    Torrentio. Reglas sacadas de 405 fuentes reales (tests/fixtures/streams): las banderas de Torrentio mezclan audio y
    subtítulos; un nombre que lista subtítulos no habla del audio; «Dual» es el original más un doblaje."""
    found: dict[str, str] = {}

    def put(code: str, how: str) -> None:
        if EVIDENCE[how] > EVIDENCE.get(found.get(code, ""), 0):
            found[code] = how

    no_subs = [SUBS_FROM.split(line, 1)[0] for line in words.split("\n")]
    subtitled = "\n".join(no_subs) != words
    audio_words = "\n".join(line[m.start():] if (m := RELEASE_MARKER.search(line)) else line for line in no_subs)
    for pattern, code in WORD_LANG:
        if pattern.search(audio_words):
            put(code, "name")
    for pattern, code in CODE_LANG:
        if pattern.search("\n".join(no_subs)):
            put(code, "name")
    if (lang := SITE_LANG.get(re.sub(r"\W", "", site).lower())) and not (subtitled and lang not in found):
        put(lang, "site")
    flags = list(dict.fromkeys(FLAG_LANG[f] for f in FLAG_RE.findall(marks)))
    dubbed = bool(re.search(r"\b(Dubbed|Multi Audio|Dual Audio)\b", marks))
    dual = "Dual Audio" in marks or bool(re.search(r"\bdual\b", audio_words, re.I))
    if len(flags) >= 5:  # muchas banderas: con doblaje, alguna es pista (no se sabe cuál); sin él, son subtítulos
        for code in flags if dubbed else ():
            put(code, "maybe")
    elif dubbed or "Multi Subs" not in marks:
        for code in flags:
            # 🇲🇽 solo sale cuando el nombre dice latino; con «Dual Audio» y una o dos banderas, esas son las pistas.
            put(code, "name" if code == "es-419" or ("Dual Audio" in marks and len(flags) <= 2) else "maybe")
    if dual:
        # «Dual»: el original y un doblaje (en anime, japonés + inglés). Sin saber el original, inglés supuesto.
        put(original or "en", "name" if original else "assumed")
        if original and original != "en" and not any(c != original and EVIDENCE[h] >= EVIDENCE["name"] for c, h in found.items()):
            put("en", "name")
    if "es" in found and any(EVIDENCE.get(found.get(v, ""), 0) >= EVIDENCE[found["es"]] for v in ("es-419", "es-ES")):
        found.pop("es")  # «SPANiSH.LATiNO»: ya se sabe cuál
    if "es" in found and original in ("es-419", "es-ES"):  # «Spanish» en una serie española: es su castellano
        put(original, found.pop("es"))
    if not found and DUBBED_WORD.search(audio_words):
        return {"en": "maybe"}
    if not any(EVIDENCE[how] >= EVIDENCE["name"] for how in found.values()):
        put(original or "en", "original" if original else "assumed")  # nada lo dice: casi siempre el original
    return dict(sorted(found.items(), key=lambda kv: -EVIDENCE[kv[1]]))


def set_languages(src: Source, langs: dict[str, str]) -> None:
    """`audio_langs` y lo que sale de ahí: `languages` (sin el doblaje) y `dub` (solo si es seguro, para los canales)."""
    src.audio_langs = langs
    src.languages = list(dict.fromkeys("es" if code in SPANISH else code for code in langs)) or ["en"]
    sure = {code for code, how in langs.items() if EVIDENCE[how] >= EVIDENCE["original"]}
    src.dub = "latino" if "es-419" in sure else "castellano" if "es-ES" in sure else ""


TRACK_LANG = {"eng": "en", "spa": "es", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it", "por": "pt",
              "rus": "ru", "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "pol": "pl", "ukr": "uk", "hin": "hi",
              "tur": "tr", "hun": "hu", "cze": "cs", "ces": "cs", "dut": "nl", "nld": "nl", "swe": "sv", "ara": "ar",
              "esl": "es", "esp": "es", "cat": "ca", "dan": "da", "nor": "no", "nob": "no", "fin": "fi", "gre": "el",
              "ell": "el", "heb": "he", "tha": "th", "vie": "vi", "ind": "id", "rum": "ro", "ron": "ro", "bul": "bg"}

LATIN_REGIONS = {"419", "mx", "ar", "us", "co", "cl", "pe", "ve", "uy", "ec", "gt", "cr", "pr", "bo", "py", "do", "hn", "sv", "ni", "pa", "cu"}

LATINO_TRACK = re.compile(r"\blatin|\blat\b|419|latam|m[eé]xic|hispanoam", re.I)

CASTELLANO_TRACK = re.compile(r"castellano|castilian|espa[ñn]a|spain|\bes-es\b|europe|ib[eé]ric", re.I)


def track_languages(tracks: list[dict]) -> list[str]:
    """Los idiomas de las pistas de audio que dio mpv al reproducir ("es-419", "en"…): lo comprobado. Vacío si alguna
    pista no dice su idioma (entonces no se sabe qué trae)."""
    out = []
    for t in tracks or []:
        if not isinstance(t, dict) or t.get("type") != "audio":
            continue
        raw = str(t.get("lang") or "").lower()
        if not raw or raw in ("und", "mul", "zxx"):
            return []
        base, _, region = raw.replace("_", "-").partition("-")
        code = TRACK_LANG.get(base, base if len(base) in (2, 3) and base.isalpha() else "")
        if not code:
            return []
        if code == "es":
            label = f"{raw} {t.get('title') or ''}"
            code = ("es-419" if region in LATIN_REGIONS or LATINO_TRACK.search(label) else
                    "es-ES" if region == "es" or CASTELLANO_TRACK.search(label) else "es")
        out.append(code)
    return list(dict.fromkeys(out))


def heard(src: Source, tracks: list[dict]) -> bool:
    """Lo que Orbital vio al reproducirla reemplaza lo que decía el nombre. False si las pistas no dicen su idioma."""
    langs = track_languages(tracks)
    if not langs:
        return False
    # Una pista «spa» que no dice cuál no borra el doblaje que el nombre sí decía (como el iPhone).
    said = [c for c in ("es-419", "es-ES") if EVIDENCE.get(src.audio_langs.get(c, ""), 0) >= EVIDENCE["original"]]
    if "es" in langs and len(said) == 1 and not set(langs) & {"es-419", "es-ES"}:
        langs = [said[0] if code == "es" else code for code in langs]
    set_languages(src, {code: "seen" for code in langs})
    src.tags = [t for t in src.tags if t not in ("Latino", "Castellano")]
    if src.dub:
        src.tags.insert(0, src.dub.capitalize())
    return True


STOPWORDS = {"the", "and", "los", "las", "del", "une", "les", "der", "die", "das", "una"}


def _plain(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text).split())


def mentions_title(titles: list[str], text: str) -> bool:
    """¿El nombre de la fuente menciona alguno de los títulos (en cualquier idioma)? Lo que está en otra escritura
    (cirílico, japonés…) se da por bueno: no hay cómo compararlo."""
    if not titles or SCRIPT_FREE.search(text):
        return True
    # Basta la palabra más distintiva (la más larga) de algún título: «Dune - Parte due» (italiano) es Dune; pedir todas
    # las palabras marcaba como otro título a 12 de 121. «La casa de la pradera» no dice «papel» ni «heist».
    haystack = _plain(text).replace(" ", "")
    for title in titles:
        words = [w for w in _plain(title).split() if w not in STOPWORDS]
        longest = max((len(w) for w in words), default=0)
        if longest < 3:
            return True  # «Up», «It», «Pi»: caben dentro de cualquier palabra; con ese nombre no se puede decidir
        if any(len(w) == longest and w in haystack for w in words):
            return True
    return False


ARTICLES = frozenset({"the", "a", "an", "el", "la", "los", "las", "le", "les", "il", "der", "die", "das"})

# Donde acaba el nombre de la serie: «S01E01», pero también un paquete («S01-S07», «Season 1», «Complete»), el año o la
# calidad («Star.Wars.The.Clone.Wars.S01-S07.1080p» no trae «S01E01»; como el iPhone).
SERIES_EPISODE_MARK = re.compile(r"[ ._\-\[(](?:s\d{1,2}(?:[ ._]?e\d{1,3})?|seasons?|temporadas?|complete|completa|\d{3,4}p|(?:19|20)\d{2})"
                                 r"(?=[ ._\-\])]|$)", re.IGNORECASE)


def names_another_series(titles: list[str], release: str) -> bool:
    """Otra serie con casi el mismo nombre (Fernando, 8 nov: «Star Wars: Clone Wars» de 2003 bajaba «Star.Wars.The.Clone.Wars»
    de 2008, que Comet le daba por el nombre; como el iPhone, Streams.namesAnotherSeries). El nombre de la serie en el archivo
    (lo de antes de «S01E01») es uno de sus títulos pero con un artículo de más: es la otra. Igual o sin artículo, es esta."""
    mark = SERIES_EPISODE_MARK.search(release.replace("📄", ""))
    if not mark:
        return False
    show = [w for w in _plain(release.replace("📄", "")[: mark.start()]).split() if not w.isdigit()]
    if not show:
        return False
    for title in titles:
        words = _plain(title).split()
        if words == show:
            return False
        extra = [w for w in show if w not in words]
        core, title_core = [w for w in show if w not in ARTICLES], [w for w in words if w not in ARTICLES]
        # Con un artículo de más y lo demás igual, o igual al final del título («The.Clone.Wars» para «Star Wars: Clone Wars»;
        # Fernando, 9 nov: seguía abriendo la de 2008).
        if extra and all(w in ARTICLES for w in extra) and core and (
                core == title_core or 2 <= len(core) < len(title_core) and title_core[-len(core):] == core):
            return True
    return False


def series_years(info: str | None) -> tuple[int, int] | None:
    """Los años de una serie de Cinemeta («2003–2005»; «2019–» sigue al aire), como Streams.seriesYears del iPhone."""
    found = [int(y) for y in YEAR.findall(info or "")]
    if not found:
        return None
    ongoing = (info or "").strip().endswith(("–", "-"))
    end = found[1] if len(found) > 1 else date.today().year if ongoing else found[0]
    return found[0], max(found[0], end)


def other_years(release: str, years: tuple[int, int] | None) -> bool:
    """Una serie de otros años: el nombre trae un solo año y cae fuera de los de la serie, con uno de margen («Star Wars:
    Clone Wars» es de 2003–2005; un «…(2008)…» es la otra; como Streams.otherYears del iPhone)."""
    if not years:
        return False
    found = {int(y) for y in YEAR.findall(release)}
    return len(found) == 1 and not years[0] - 1 <= next(iter(found)) <= years[1] + 1


# «¿Otro episodio?» (las mismas reglas que el iPhone, Streams+Episodes.swift): Torrentio a veces pone en un episodio el
# archivo de otra temporada. Solo con temporada (los de Kitsu van de corrido).
EPISODE_MARK = re.compile(r"\bs(\d{1,2})[ ._-]?e\d{1,3}\b|\b(\d{1,2})x\d{2,3}\b", re.I)

SEASON_WORD = re.compile(r"\b(?:s|season|temporada|saison|stagione|staffel|sezon)[ ._-]?(\d{1,2})\b", re.I)

SEASON_LETTER = re.compile(r"\bT(\d{1,2})\b")  # «T4» (temporada), solo en mayúscula

SEASON_RANGE = re.compile(
    r"\bs\d{1,2}[ ._]*(?:-|~|a|to)[ ._]*s?\d{1,2}\b|\b(?:seasons?|temporadas?)[ ._]*\d{1,2}[ ._]*(?:-|~|a|to|&|y)[ ._]*\d{1,2}\b|"
    r"\bt\d{1,2}[ ._]*-[ ._]*t?\d{1,2}\b", re.I)


YEAR = re.compile(r"\b(19[2-9]\d|20[0-4]\d)\b")


def other_year(release: str, year: int | None) -> bool:
    """El nombre dice un solo año y no es el de la película (como el iPhone, Streams.otherTitle): Cinemeta da el estreno en
    EE. UU. y una extranjera puede llegar allá hasta 3 años después, así que un año anterior cuenta hasta 3."""
    if not year:
        return False
    years = {int(y) for y in YEAR.findall(release)}
    if len(years) != 1:
        return False
    only = years.pop()
    return only - year > 1 or year - only > 3


# El idioma original por el país de Cinemeta cuando TMDB no lo da (como TitleOrigin.originalCode del iPhone): el primer país
# con idioma conocido; uno hispano da es-419 o es-ES según el primero de habla hispana que se nombre.
SPAIN_NAMES = {"es", "spain", "españa"}

LATIN_NAMES = {"mx", "mexico", "méxico", "ar", "argentina", "co", "colombia", "cl", "chile", "pe", "peru", "perú", "ve",
               "venezuela", "uy", "uruguay", "ec", "ecuador", "bo", "bolivia", "py", "paraguay", "cu", "cuba", "do",
               "dominican republic", "gt", "guatemala", "cr", "costa rica", "pa", "panama", "pr", "puerto rico"}

COUNTRY_LANGUAGES = {
    "united states": "en", "us": "en", "usa": "en", "united kingdom": "en", "uk": "en", "gb": "en", "canada": "en",
    "australia": "en", "japan": "ja", "jp": "ja", "south korea": "ko", "korea": "ko", "kr": "ko", "france": "fr", "fr": "fr",
    "germany": "de", "de": "de", "italy": "it", "it": "it", "brazil": "pt", "br": "pt", "portugal": "pt", "india": "hi",
    "china": "zh", "cn": "zh", "russia": "ru"}


def original_from_country(country: object) -> str | None:
    countries = [c.strip() for c in re.split(r"[,/]", str(country or "").lower()) if c.strip()]
    lang = next((COUNTRY_LANGUAGES.get(c) or ("es" if c in LATIN_NAMES or c in SPAIN_NAMES else None)
                 for c in countries if COUNTRY_LANGUAGES.get(c) or c in LATIN_NAMES or c in SPAIN_NAMES), None)
    if lang != "es":
        return lang
    for c in countries:
        if c in LATIN_NAMES:
            return "es-419"
        if c in SPAIN_NAMES:
            return "es-ES"
    return "es"


def season_of(video_id: str) -> int | None:
    """La temporada de un episodio de IMDb («tt0903747:1:2» → 1); None si no es de ese tipo."""
    parts = video_id.split(":")
    if len(parts) != 3 or not parts[0].startswith("tt") or not parts[1].isdigit():
        return None
    return int(parts[1])


def other_episode(release: str, filename: str, season: int) -> bool:
    """El archivo o el nombre dicen otra temporada (y ninguno dice esta)."""
    def seasons(pattern: re.Pattern, text: str) -> list[int]:
        return [int(next(g for g in m.groups() if g)) for m in pattern.finditer(text)]
    for text in (filename, release):
        marked = seasons(EPISODE_MARK, text)
        if marked:
            return season not in marked
    if SEASON_RANGE.search(release):
        return False
    named = seasons(SEASON_WORD, release) + seasons(SEASON_LETTER, release)
    return bool(named) and season not in named


def spanish_dub(text: str) -> str:
    """"latino", "castellano" o "" según lo que diga el título de la fuente. Si dice los dos, "latino" (trae esa pista).
    🇪🇸 sola no lo dice: Torrentio la pone a cualquier «Spanish»."""
    langs = audio_languages(text, " / ".join(FLAG_RE.findall(text)))
    return "latino" if "es-419" in langs else "castellano" if "es-ES" in langs else ""


# El doblaje de una fuente y la variante que se pide en Ajustes (los códigos del iPhone).
DUB_CODES = {"latino": "es-419", "castellano": "es-ES"}

SPANISH_VARIANTS = ("es-419", "es-ES")


@dataclass
class Preferences:
    audio: str = "en"  # idioma de audio preferido
    quality: str = "1080p"  # resolución preferida ("4K" en la TV si quieres)
    spanish: str = ""  # con audio en español: "es-419" (latino), "es-ES" (castellano) o "" (cualquiera)
    original: str = ""  # el idioma original del título ("ja", "en"…): lo pone find(), no Ajustes
    # Tu orden después del primero (N4-A, Ajustes › Tus idiomas): códigos y «original» (el idioma original de cada título).
    # Vacío: el de siempre (con latino o castellano, original → inglés → el otro doblaje).
    plan: tuple[str, ...] = ()


# Ajustes › Tus idiomas (N4-A, Fernando 4 nov): una sola lista ordenada; «original» es un renglón. Por omisión, con latino.
LANGUAGE_CHOICES = ("es-419", "es-ES", "original", "en", "fr", "pt", "it", "de", "ja", "ko")

DEFAULT_LANGUAGES = ("es-419", "original", "en", "es-ES")


def languages_from_audio(audio: str) -> tuple[str, ...]:
    """Tu orden a partir del «Idioma» de antes (un solo valor): latino o castellano con el plan B de siempre; otro, solo él
    y luego el original."""
    if audio == "es-ES":  # la regla de siempre con castellano (como el iPhone): castellano y luego latino
        return ("es-ES", "es-419")
    if audio in ("es-419", "es"):
        return DEFAULT_LANGUAGES
    return (audio or "en", "original")


def valid_languages(value) -> bool:
    return (isinstance(value, list) and 1 <= len(value) <= len(LANGUAGE_CHOICES) and len(set(value)) == len(value)
            and all(isinstance(v, str) and v in LANGUAGE_CHOICES for v in value) and value[0] != "original")


def prefs_from_languages(languages, quality: str = "1080p") -> Preferences:
    """Las preferencias de búsqueda a partir de tu orden: el primero es tu idioma (con su doblaje) y lo demás, el plan B."""
    first, rest = languages[0], tuple(languages[1:])
    if first in SPANISH_VARIANTS:
        return Preferences(audio="es", spanish=first, quality=quality, plan=rest)
    return Preferences(audio=first, quality=quality, plan=rest)
