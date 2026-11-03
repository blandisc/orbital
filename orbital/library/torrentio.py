"""Torrentio con tus opciones, armado por Orbital («La TV sin Stremio», corte S3; design/addons-contract.json,
`torrentio_options`).

La dirección se arma en el orden de Torrentio (providers, sort, language, qualityfilter, limit, sizefilter, debridoptions y
al final tu clave de Real-Debrid), saltando lo vacío y lo que es igual a no decirlo. Es la misma que arma el iPhone
(TorrentioConfig.swift): tests/fixtures/torrentio-config.json lo prueba en los dos lados. Una dirección traída de tu
Stremio se lee de vuelta a estas opciones; lo que no se conoce se conserva tal cual (`verbatim`) y la clave va aparte.
"""

from __future__ import annotations

import urllib.parse

BASE = "https://torrentio.strem.fun"
ORDER = ("providers", "sort", "language", "qualityfilter", "limit", "sizefilter", "debridoptions")
PROVIDERS = ("yts", "eztv", "rarbg", "1337x", "ext", "thepiratebay", "kickasstorrents", "torrentgalaxy", "magnetdl",
             "horriblesubs", "nyaasi", "tokyotosho", "anidex", "nekobt", "rutor", "rutracker", "comando", "bludv",
             "micoleaodublado", "torrent9", "ilcorsaronero", "mejortorrent", "wolfmax4k", "cinecalidad", "besttorrents")
PROVIDER_NAMES = {
    "yts": "YTS", "eztv": "EZTV", "rarbg": "RARBG", "1337x": "1337x", "ext": "EXT", "thepiratebay": "ThePirateBay",
    "kickasstorrents": "KickassTorrents", "torrentgalaxy": "TorrentGalaxy", "magnetdl": "MagnetDL", "horriblesubs": "HorribleSubs",
    "nyaasi": "NyaaSi", "tokyotosho": "TokyoTosho", "anidex": "AniDex", "nekobt": "nekoBT", "rutor": "Rutor",
    "rutracker": "Rutracker", "comando": "Comando", "bludv": "BluDV", "micoleaodublado": "MicoLeaoDublado",
    "torrent9": "Torrent9", "ilcorsaronero": "ilCorSaRoNeRo", "mejortorrent": "MejorTorrent", "wolfmax4k": "Wolfmax4k",
    "cinecalidad": "Cinecalidad", "besttorrents": "BestTorrents"}
# Los 41 idiomas que Torrentio sabe poner primero, con su código (el plan B del reproductor), como el iPhone.
LANGUAGES = {
    "latino": "es-419", "spanish": "es-ES", "portuguese": "pt", "french": "fr", "italian": "it", "german": "de", "japanese": "ja",
    "korean": "ko", "chinese": "zh", "taiwanese": "zh-TW", "russian": "ru", "dutch": "nl", "hindi": "hi", "telugu": "te",
    "tamil": "ta", "polish": "pl", "lithuanian": "lt", "latvian": "lv", "estonian": "et", "czech": "cs", "slovakian": "sk",
    "slovenian": "sl", "hungarian": "hu", "romanian": "ro", "bulgarian": "bg", "serbian": "sr", "croatian": "hr",
    "ukrainian": "uk", "greek": "el", "danish": "da", "finnish": "fi", "swedish": "sv", "norwegian": "no", "turkish": "tr",
    "arabic": "ar", "persian": "fa", "hebrew": "he", "vietnamese": "vi", "indonesian": "id", "malay": "ms", "thai": "th"}
QUALITIES = ("brremux", "hdrall", "dolbyvision", "dolbyvisionwithhdr", "threed", "nonthreed", "4k", "1080p", "720p",
             "480p", "other", "scr", "cam", "unknown")
SORTS = ("quality", "qualitysize", "seeders", "size")  # el primero es el de Torrentio y no se escribe
NO_LIMIT = "1000GB"
# Lo que viene con Orbital (T11, igual que AddonOptions del iPhone): latino y español primero; sin cine, Screener ni sin calidad.
RECOMMENDED = {"language": ["latino", "spanish"], "qualityfilter": ["cam", "scr", "unknown"]}
SECRET_KEYS = ("realdebrid", "premiumize", "alldebrid", "debridlink", "offcloud", "putio", "torbox", "easydebrid")


def _clean(values) -> list[str]:
    out = []
    for value in values or []:
        word = "".join(ch for ch in str(value).lower() if ch.isalnum())
        if word and word not in out:
            out.append(word)
    return out


def parts(options: dict) -> list[str]:
    """Las partes de la dirección (sin la clave), en el orden de Torrentio."""
    out = []
    providers = _clean(options.get("providers"))
    if providers and set(providers) != set(PROVIDERS):
        out.append("providers=" + ",".join(providers))
    sort = (_clean([options["sort"]]) or [""])[0] if options.get("sort") else ""
    if sort and sort != SORTS[0]:
        out.append(f"sort={sort}")
    if (languages := _clean(options.get("language"))):
        out.append("language=" + ",".join(languages))
    if (hidden := _clean(options.get("qualityfilter"))):
        out.append("qualityfilter=" + ",".join(hidden))
    limit = options.get("limit")
    if isinstance(limit, int) and not isinstance(limit, bool) and 1 <= limit <= 999:
        out.append(f"limit={limit}")
    size = "".join(ch for ch in str(options.get("sizefilter") or "") if ch.isalnum() or ch in ",.")
    if size:
        out.append(f"sizefilter={size}")
    if (debrid := _clean(options.get("debridoptions"))):
        out.append("debridoptions=" + ",".join(debrid))
    out += [v for v in options.get("verbatim") or [] if isinstance(v, str) and "=" in v and "/" not in v and "|" not in v
            and v.split("=", 1)[0].lower() not in SECRET_KEYS]
    return out


def manifest_url(options: dict, key: str | None, base: str = BASE) -> str | None:
    """La dirección del manifiesto con tu clave al final. None sin clave."""
    if not key:
        return None
    return f"{base}/{'|'.join([*parts(options), 'realdebrid=' + urllib.parse.quote(key, safe='')])}/manifest.json"


def parse(url: str) -> tuple[dict, str | None] | None:
    """Lo que trae una dirección de Torrentio (de tu Stremio): (opciones, tu clave). None si no es un Torrentio."""
    decoded = urllib.parse.unquote(url or "")
    if "://" not in decoded:
        return None
    rest = decoded.split("://", 1)[1].removesuffix("/manifest.json")
    host, _, path = rest.partition("/")
    if "torrentio" not in host.lower():
        return None
    options: dict = {"language": [], "qualityfilter": []}  # sin opciones, Torrentio no esconde nada ni pone idiomas
    key = None
    as_list = lambda value: [x.strip() for x in value.split(",") if x.strip()]  # noqa: E731
    for part in (p for p in path.split("|") if p):
        name, _, value = part.partition("=")
        name = name.lower()
        if name in ("providers", "language", "qualityfilter", "debridoptions"):
            options[name] = as_list(value)
        elif name == "sort":
            options["sort"] = value
        elif name == "limit" and value.isdigit() and 1 <= int(value) <= 999:
            options["limit"] = int(value)
        elif name == "sizefilter":
            options["sizefilter"] = value
        elif name == "realdebrid":
            key = value
        elif name not in SECRET_KEYS:
            options.setdefault("verbatim", []).append(part)
    return options, key


def is_torrentio(url: str) -> bool:
    return parse(url) is not None


def sizes(sizefilter: str | None) -> tuple[str | None, str | None]:
    """«10GB,2GB» como (películas, episodios); None = sin límite."""
    values = [None if v.upper() == NO_LIMIT else v.upper() for v in (sizefilter or "").split(",") if v]
    if not values:
        return None, None
    return values[0], values[-1]


def sizefilter(movies: str | None, episodes: str | None) -> str | None:
    if movies is None and episodes is None:
        return None
    if movies == episodes:
        return movies
    return f"{movies or NO_LIMIT},{episodes or NO_LIMIT}"
