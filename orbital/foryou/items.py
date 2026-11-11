"""Las tarjetas de «Para ti» (películas, series, juegos, el calendario): funciones sin estado.
"""

from __future__ import annotations

import logging
import re
from datetime import date, datetime
from typing import Any

from ..text import clock
from .base import DAWN_HOUR, METAHUB, STEAM_ART, WEEKDAYS

log = logging.getLogger("orbital.foryou")  # el mismo nombre de siempre: la bitácora no cambia


# ---------------------------------------------------------------- textos
def runtime_text(minutes: int | None) -> str | None:
    if not minutes:
        return None
    hours, rest = divmod(int(minutes), 60)
    return f"{hours} h {rest} min" if hours and rest else f"{hours} h" if hours else f"{rest} min"



def hours_text(seconds: float) -> str:
    """«48 h», «1 h 30 min», «35 min»: lo jugado."""
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} h" if minutes >= 600 or minutes % 60 == 0 else f"{minutes // 60} h {minutes % 60} min"



def fold(text: str) -> str:
    """Para comparar títulos: «Baldur's Gate 3» y «Baldurs Gate III» no, pero «HADES» y «Hades» sí."""
    return re.sub(r"[^a-z0-9]+", "", str(text or "").lower())



# ---------------------------------------------------------------- piezas
def video_item(e: dict, why: str, *, title: str | None = None, poster: str | None = None,
               wide: str | None = None, overview: str | None = None, seasons: int | None = None,
               in_list: bool = False) -> dict:
    """Una película o serie: lo que necesita el mosaico, las listas, la ficha y el reproductor. `in_list`: viene de una
    lista de Trakt o de un complemento («En «RT: Certified Fresh»»): el destacado no pone ese nombre como etiqueta."""
    imdb, kind = e["imdb"], e["kind"]
    nxt = e.get("next")
    episode = f"T{nxt['season']} E{nxt['episode']}" if nxt else None
    if kind == "movie":
        detail = runtime_text(e.get("runtime")) or (str(e["year"]) if e.get("year") else "")
        facts = [["Duración", runtime_text(e.get("runtime"))], ["Año", e.get("year")]]
        video_id, action = imdb, "Ver"
    else:
        count = f"{seasons} temporada{'s' if seasons != 1 else ''}" if seasons else (
            f"{e['episodes']} episodios" if e.get("episodes") else None)
        detail = f"Sigue {episode}" if episode else count or (str(e["year"]) if e.get("year") else "")
        facts = [["Sigue", episode] if episode else ["Temporadas", seasons] if seasons else ["Episodios", e.get("episodes")],
                 ["Año", e.get("year")]]
        video_id = f"{imdb}:{nxt['season']}:{nxt['episode']}" if nxt else f"{imdb}:1:1"
        # Una serie abre su ficha (temporadas, sinopsis, en qué episodio vas), nunca un episodio directo.
        action = "Ver la serie"
    return {
        "key": f"video:{imdb}", "id": f"cinemeta:{kind}:{imdb}", "source": "cinemeta", "kind": kind, "meta_id": imdb,
        "title": title or e["title"], "year": e.get("year"), "why": why, "detail": detail,
        **({"in_list": True} if in_list else {}),
        "facts": [[k, str(v)] for k, v in facts if v],
        "image": poster or METAHUB.format(kind="poster", imdb=imdb),
        "hero": wide or METAHUB.format(kind="background", imdb=imdb),
        "logo": METAHUB.format(kind="logo", imdb=imdb),
        "overview": overview or "", "video_id": video_id, "episode": episode, "action": action,
        # Para «Decide por mí» del iPhone (sin preguntarle a Cinemeta título por título): en inglés, como vienen.
        **({"genres": list(e["genres"])} if e.get("genres") else {}),
        **({"runtime": int(e["runtime"])} if isinstance(e.get("runtime"), int) and e["runtime"] > 0 else {}),
        # La calificación de Trakt (para ordenar «Mejor calificadas en Trakt», en la TV y en el iPhone).
        **({"rating": e["rating"]} if isinstance(e.get("rating"), (int, float)) and e["rating"] > 0 else {}),
    }



def series_only(item: dict) -> dict:
    """El mosaico propone series, nunca un episodio (Fernando, 4 nov 2026: «Puedes sugerir una serie, pero no un episodio
    específico»): sin «Sigue T3 E5» ni el episodio en sus datos. La ficha sigue sabiendo en cuál vas."""
    if item.get("kind") != "series" or not (item.get("episode") or str(item.get("detail") or "").startswith("Sigue ")):
        return item
    facts = [f for f in item.get("facts") or [] if f[0] not in ("Sigue", "Episodio")]
    year = next((v for k, v in facts if k == "Año"), "")
    detail = "" if str(item.get("detail") or "").startswith("Sigue ") else item.get("detail")
    return {**item, "episode": None, "facts": facts, "detail": detail or year}



def library_entry(item) -> dict | None:
    """Un título que Orbital ya tiene (tu Stremio o lo popular de Cinemeta), en la forma de video_item."""
    extra = item.extra or {}
    imdb, kind = str(extra.get("meta_id") or ""), extra.get("kind")
    if not re.fullmatch(r"tt\d+", imdb) or kind not in ("movie", "series"):
        return None
    year = re.match(r"\d{4}", str(extra.get("year") or ""))
    minutes = re.match(r"\d+", str(extra.get("runtime") or ""))
    e: dict[str, Any] = {"imdb": imdb, "kind": kind, "title": item.title, "year": int(year.group()) if year else None}
    if minutes:  # en una serie, lo que dura un episodio
        e["runtime"] = int(minutes.group())
    if isinstance(extra.get("genres"), list) and extra["genres"]:
        e["genres"] = [str(g) for g in extra["genres"]][:4]
    parts = str(extra.get("video_id") or "").split(":")
    if kind == "series" and len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        e["next"] = {"season": int(parts[1]), "episode": int(parts[2])}  # el episodio en que vas
    return e



def day_label(day: date, today: date) -> tuple[str, str]:
    """(«Hoy», «jueves 15») · («Mañana», «viernes 16») · («Ayer», «martes 13») · («Domingo 18», «octubre»)."""
    name = f"{WEEKDAYS[day.weekday()]} {day.day}"
    delta = (day - today).days
    if delta == 0:
        return "Hoy", name
    if delta == 1:
        return "Mañana", name
    if delta == -1:
        return "Ayer", name
    months = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    return name[:1].upper() + name[1:], months[day.month - 1]



def calendar_item(g: dict, today: date) -> dict:
    """Un estreno («Próximos estrenos»): la serie (A abre su ficha) con su día, hora, episodio y dónde sale."""
    when: datetime = g["when"]
    time_text = "Desde la madrugada" if when.hour < DAWN_HOUR else clock(when)
    if g["count"] > 1:
        episode = f"T{g['season']} E{g['first']}–E{g['last']}"
        episode_long = f"{episode} · {g['count']} episodios"
    else:
        episode = f"T{g['season']} E{g['episode']}"
        episode_long = f"{episode} · {g['episode_title']}" if g.get("episode_title") else episode
    day, sub = day_label(when.date(), today)
    when_text = f"{day} · madrugada" if when.hour < DAWN_HOUR else f"{day} · {time_text}"
    released = when.date() < today  # ya salió (en «Lo nuevo de lo tuyo», la semana que pasó)
    # Un día solo («Miércoles 4») no decía qué pasaba: «Episodio nuevo el miércoles 4», «Episodio nuevo mañana» (PS-2, 2 nov 2026).
    soon = "Episodio nuevo mañana" if day == "Mañana" else f"Episodio nuevo el {day[:1].lower()}{day[1:]}"
    item = video_item({**g, "kind": "series", "next": None}, "Sale hoy" if day == "Hoy" else "Ya salió" if released else soon)
    return {**item, "key": f"video:{g['imdb']}", "day": when.date().isoformat(), "day_label": day, "day_sub": sub,
            "time": time_text, "today": day == "Hoy", "released": released, "episode": None, "episode_label": episode,
            "network": g.get("network") or "",
            "detail": " · ".join(p for p in (time_text, g.get("network")) if p),
            # Datos cortos (la ficha los pinta en una fila); el nombre del episodio va en la descripción.
            "facts": [[k, v] for k, v in (("Cuándo", when_text), ("Episodio", episode), ("Dónde", g.get("network") or "")) if v],
            "overview": " · ".join(p for p in (episode_long if (g["count"] > 1 or g.get("episode_title")) else "", item.get("overview")) if p)}



def game_item(described: dict, why: str) -> dict:
    """Un juego tuyo (de la biblioteca): A lo abre como en Juegos."""
    played = float(described.get("playtime") or 0)
    detail = f"{hours_text(played)} jugadas" if played >= 60 else "Nunca lo has abierto"
    extra = described.get("extra") or {}
    steam_id = str(described["id"]).removeprefix("steam:")
    appid = extra.get("steam_appid") or described.get("steam_appid") or (
        int(steam_id) if str(described["id"]).startswith("steam:") and steam_id.isdigit() else None)
    return {
        "key": f"game:{described['id']}", "id": described["id"], "kind": "game", "item": described, "owned": True,
        "title": described["title"], "why": why, "detail": detail,
        "facts": [["Jugadas", hours_text(played) if played >= 60 else "0 h"]],
        "image": described.get("image"), "hero": described.get("hero") or described.get("image"),
        "logo": extra.get("logo"), "overview": "", "action": "Jugar",
        "steam_appid": appid or None,
        # El «hero» de Steam es un fondo hecho para llevar el logo encima (el de Cult of the Lamb es un
        # patrón de corderitos): sin foco, la pieza ancha usa la cápsula de la tienda, que sí lleva el juego.
        "wide": STEAM_ART.format(appid=appid, file="capsule_616x353.jpg") if appid else None,
        # Sin un fondo ancho de verdad (el respaldo de Orbital o una captura chiquita): siempre en vertical.
        "hero_weak": bool(extra.get("placeholder_hero") or extra.get("hero_lowres")),
        "placeholder": bool(extra.get("placeholder_cover")),  # sin portada propia: la genérica de Orbital
    }



def whiten_if_dark(png: bytes) -> bytes:
    """Un logo oscuro (negro sobre transparente, como el de Severance) en blanco: sobre los fondos de Orbital no se veía en
    la ficha ni en el héroe. Los de color se dejan como vienen."""
    try:
        import io

        from PIL import Image

        image = Image.open(io.BytesIO(png)).convert("RGBA")
        small = image.copy()
        small.thumbnail((96, 96))
        visible = [px[:3] for px in small.getdata() if isinstance(px, tuple) and len(px) == 4 and px[3] > 128]
        if not visible or sum(.2126 * r + .7152 * g + .0722 * b for r, g, b in visible) / len(visible) >= 64:
            return png
        alpha = image.getchannel("A")
        white = Image.new("RGBA", image.size, (255, 255, 255, 255))
        white.putalpha(alpha)
        out = io.BytesIO()
        white.save(out, "PNG")
        return out.getvalue()
    except Exception:  # noqa: BLE001 - sin Pillow o un PNG raro: el logo como venía
        return png
