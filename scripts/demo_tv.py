"""Canales de TV en vivo de mentiras para el demo: sin Internet, sin mpv y sin abrir nada de verdad.

Los nombres son inventados (nada de marcas reales). Los logos también: se dibujan aquí, de los cuatro tipos que
llegan en la vida real (letras claras, letras oscuras, de color y con fondo propio), y uno de cada siete no trae
logo para ver las letras de respaldo.
"""

from __future__ import annotations

import io
import re
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from orbital.library import iptv, iptv_logos

# (nombre, categorías de iptv-org, calidad)
CHANNELS = [
    ("Canal Centro", "General", "720p"), ("Telenorte", "General", "1080p"), ("Mi Ciudad TV", "General", "720p"),
    ("Canal Veintidós", "General;Culture", "720p"), ("Imagen del Sur", "General", "1080p"), ("Telebajío", "General", "480p"),
    ("Pacífico Uno", "General", "720p"), ("Frontera TV", "General", "720p"), ("Canal Estrella", "General;Entertainment", "1080p"),
    ("Noticias 24 Horas", "News", "1080p"), ("Informativo MX", "News;General", "720p"), ("Hoy en Línea", "News", "720p"),
    ("Mundo Noticias", "News", "480p"), ("Reporte Nacional", "News", "720p"), ("Panorama TV", "News", "1080p"),
    ("Deportes Total", "Sports", "1080p"), ("Gol Directo", "Sports", "720p"), ("Liga Plus", "Sports", "720p"),
    ("Arena Deportiva", "Sports", "1080p"), ("Motor y Pista", "Sports;Auto", "720p"),
    ("Cine Estelar", "Movies", "1080p"), ("Cine de Barrio", "Movies", "720p"), ("Clásicos del Cine", "Movies;Classic", "480p"),
    ("Pantalla Grande", "Movies", "720p"), ("Estreno Cine", "Movies", "1080p"),
    ("Peques TV", "Animation;Kids", "720p"), ("Aventuras Animadas", "Animation;Kids", "720p"), ("Chiquitines", "Kids", "480p"),
    ("Mundo Infantil", "Kids", "720p"),
    ("Música Hoy", "Music", "720p"), ("Ritmo Latino", "Music", "720p"), ("Rock en Vivo", "Music", "480p"), ("Banda Plus", "Music", "720p"),
    ("Cultura Viva", "Culture", "720p"), ("Arte y Letras", "Culture;Education", "720p"), ("Aula Abierta", "Education", "480p"),
    ("Canal Educativo", "Education", "720p"), ("Ciencia Hoy", "Education;Science", "720p"),
    ("Sin Categoría Uno", "Undefined", "480p"), ("Sin Categoría Dos", "Undefined", "720p"),
]
if __import__("os").environ.get("ORBITAL_DEMO_LONG") == "1":  # pruebas: nombres larguísimos
    CHANNELS = [(f"{n} Internacional Señal Premium en Alta Definición" if i % 3 == 0 else n, c, q) for i, (n, c, q) in enumerate(CHANNELS)]
SHAKY = "Frontera TV"  # ya falló una vez: sale al final de su lista, atenuado y con su aviso (con otro fallo se ocultaría)
COLORS = [(224, 82, 99), (66, 133, 244), (244, 180, 0), (15, 157, 88), (171, 71, 188), (255, 112, 67)]


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", iptv.fold(name))


def logo_png(index: int, name: str) -> bytes | None:
    """El logo inventado de un canal: cuatro estilos que se reparten, y uno de cada siete sin logo."""
    if index % 7 == 6:
        return None
    word = iptv.fold(name).upper()  # sin acentos: la tipografía de Pillow no los trae todos
    image = Image.new("RGBA", (460, 170), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    size = 64
    font = ImageFont.load_default(size=size)
    while draw.textlength(word, font=font) > 400 and size > 20:  # que el nombre quepa en el logo
        size -= 4
        font = ImageFont.load_default(size=size)
    color = COLORS[index % len(COLORS)]
    style = index % 4
    if style == 0:  # letras claras sobre transparente (se ve directo sobre el fondo oscuro)
        draw.text((230, 85), word, font=font, fill=(255, 255, 255, 255), anchor="mm")
    elif style == 1:  # letras oscuras sobre transparente (necesita placa clara)
        draw.text((230, 85), word, font=font, fill=(20, 20, 24, 255), anchor="mm")
    elif style == 2:  # de color
        draw.ellipse((150, 5, 310, 165), fill=(*color, 255))
        draw.text((230, 85), "".join(w[0] for w in word.split()[:2]), font=ImageFont.load_default(size=64), fill=(255, 255, 255, 255), anchor="mm")
    else:  # con fondo propio
        draw.rounded_rectangle((0, 0, 459, 169), radius=26, fill=(*color, 255))
        draw.text((230, 85), word, font=font, fill=(255, 255, 255, 255), anchor="mm")
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


def install(catalog, directory: Path) -> None:
    """Pone los canales en la TV del catálogo y apaga lo que saldría a Internet o abriría mpv."""
    lines = ["#EXTM3U\n"]
    logos = {}
    for i, (name, group, quality) in enumerate(CHANNELS):
        png = logo_png(i, name)
        url = f"https://logos.demo.example/{slug(name)}.png" if png else ""
        if png:
            logos[url] = png
        lines.append(f'#EXTINF:-1 tvg-id="{slug(name)}.mx@SD" tvg-logo="{url}" group-title="{group}",{name} ({quality})\n'
                     f"https://tv.example.mx/{slug(name)}/playlist.m3u8\n")
    tv = catalog.tv
    tv.logos = iptv_logos.LogoCache(directory / "tv-logos")
    for url, png in logos.items():
        tv.logos.put(url, png)
    tv.set_channels(iptv.parse_m3u("".join(lines)))
    for channel in tv.visible():
        tv.store.record(channel.id, channel.name != SHAKY, "" if channel.name != SHAKY else "no abre")
    tv.updated = time.time()
    on_air = {"id": None}

    def play(channel_id: str, category: str = "todos", *, keep: bool = False) -> dict:
        channel = tv.channel(channel_id)
        if channel is None:
            raise LookupError("Ese canal ya no está disponible. Elige otro.")
        tuned = on_air["id"] is not None and catalog.launcher.status() is not None
        on_air["id"] = channel.id
        catalog.launcher.track("media:player", channel.name, object(), runner="Reproductor")
        # Como el reproductor de verdad: al cerrar, anota que era la tele (el aviso dice «De vuelta de la TV en vivo»).
        catalog.watch.player.last_end = {"title": channel.name, "finished": False, "kind": "tv", "live": True}
        return {"ok": True, "reveal": False, **({"tuned": True} if tuned else {})}

    tv.play = play  # type: ignore[method-assign] - en el demo, sintonizar solo anota qué está «abierto»
    tv.playing = lambda: on_air["id"] if catalog.launcher.status() else None  # type: ignore[method-assign]
    tv.refresh = lambda background=False: True  # type: ignore[method-assign] - sin Internet
    tv.start = lambda: None  # type: ignore[method-assign]
