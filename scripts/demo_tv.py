"""Canales de TV en vivo de mentiras para el demo: sin Internet, sin mpv y sin abrir nada de verdad.

Los nombres son inventados (nada de marcas reales) y no tienen logo: así se ven las letras de respaldo.
"""

from __future__ import annotations

import re
import time

from orbital.library import iptv

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
SHAKY = "Frontera TV"  # ya falló una vez: se ve atenuado (con otro fallo se ocultaría)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", iptv.fold(name))


def install(catalog) -> None:
    """Pone los canales en la TV del catálogo y apaga lo que saldría a Internet o abriría mpv."""
    text = "#EXTM3U\n" + "".join(
        f'#EXTINF:-1 tvg-id="{slug(name)}.mx@SD" group-title="{group}",{name} ({quality})\nhttps://tv.example.mx/{slug(name)}/playlist.m3u8\n'
        for name, group, quality in CHANNELS)
    tv = catalog.tv
    tv.set_channels(iptv.parse_m3u(text))
    for channel in tv.visible():
        tv.store.record(channel.id, channel.name != SHAKY, "" if channel.name != SHAKY else "no abre")
    tv.updated = time.time()

    def play(channel_id: str, category: str = "todos", *, keep: bool = False) -> dict:
        channel = tv.channel(channel_id)
        if channel is None:
            raise LookupError("Ese canal ya no está disponible. Elige otro.")
        catalog.launcher.track("media:player", channel.name, object(), runner="Reproductor")
        # Como el reproductor de verdad: al cerrar, anota que era la tele (el aviso dice «De vuelta de la TV en vivo»).
        catalog.watch.player.last_end = {"title": channel.name, "finished": False, "kind": "tv", "live": True}
        return {"ok": True, "reveal": False}

    tv.play = play  # type: ignore[method-assign] - en el demo, sintonizar solo anota qué está «abierto»
    tv.refresh = lambda background=False: True  # type: ignore[method-assign] - sin Internet
    tv.start = lambda: None  # type: ignore[method-assign]
