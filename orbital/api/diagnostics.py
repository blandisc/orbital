"""Diagnóstico: qué ve Orbital de su equipo, en una sola pantalla.

Lo primero que hay que mirar cuando algo "no sale": en qué carpetas vive, si Windows le redirige
AppData, si encuentra mpv/ES-DE/Stremio, memoria y los últimos avisos del registro (sin claves).
"""

from __future__ import annotations

import os
import re
import sys
import time
from collections import Counter
from pathlib import Path

from fastapi import APIRouter
from fastapi.concurrency import run_in_threadpool

from .. import __version__, health, player, runtime
from ..launcher import redact
from .deps import Deps

PROBLEM = re.compile(r"\b(WARNING|ERROR|CRITICAL)\b")
URL = re.compile(r"(https?://[^\s\"']+|stremio:///player/\S+)")
TAIL_BYTES = 200_000
MAX_PROBLEMS = 15
GAMES = {"emulators", "steam", "geforcenow"}  # las categorías del catálogo que son juegos (lo demás: videos, apps, Buscar)


def library_counts(items) -> dict[str, int]:
    """Cuántos juegos por sistema («Nintendo Switch 13», «Steam 116», «GeForce NOW 71»). Solo juegos: los videos (subtítulo
    «T1 E1 · quedan 48 min») salían como una consola más, y el subtítulo de Steam («Sin instalar · En GeForce NOW»)
    partía un sistema en varios renglones."""
    def system(i) -> str:
        if i.category == "steam":
            return "Steam"
        if i.category == "geforcenow":
            return "GeForce NOW"
        return (i.subtitle or i.system or i.source).split(" · ")[0]
    return dict(Counter(system(i) for i in items if i.category in GAMES))


def recent_problems(log_path: Path | None, limit: int = MAX_PROBLEMS) -> list[str]:
    """Las últimas líneas de aviso o error del registro, con las URLs recortadas (llevan claves)."""
    if not log_path or not log_path.is_file():
        return []
    with log_path.open("rb") as fh:
        fh.seek(max(0, log_path.stat().st_size - TAIL_BYTES))
        lines = fh.read().decode("utf-8", "replace").splitlines()
    found = [URL.sub(lambda m: redact(m.group(0)), line.strip()) for line in lines if PROBLEM.search(line)]
    return found[-limit:]


def collect(d: Deps) -> dict:
    catalog = d.catalog
    items = catalog.items()
    dwm = health.dwm_gpu_mb()
    from ..gamepad import connected_controllers

    return {
        "version": __version__,
        "python": sys.version.split()[0],
        "uptime": int(time.time() - d.started) if d.started else None,
        "paths": {
            "config": str(d.config.source) if getattr(d.config, "source", None) else None,
            "data": str(Path(os.environ.get("LOCALAPPDATA", "")) / "orbital"),
            "log": str(d.log_path) if d.log_path else None,
            "appdata_redirected": runtime.virtualized_appdata(),
        },
        "found": {
            "mpv": player.find_mpv(),
            "esde": catalog.esde is not None,
            "steam": str(catalog.steam_root) if catalog.steam_root else None,
            "stremio": catalog.stremio_linked,
            "alexa": d.alexa_ready,
            "alexa_last": d.alexa_last,
        },
        "library": library_counts(items),  # por sistema y en palabras («Nintendo GameCube 5»), solo juegos
        "running": d.status()["running"],
        "memory": {"free_mb": health.free_ram_mb(), "dwm_shared_mb": dwm[0] if dwm else None,
                   "dwm_dedicated_mb": dwm[1] if dwm else None},
        "controllers": connected_controllers(),
        "problems": recent_problems(d.log_path),
    }


def router(d: Deps) -> APIRouter:
    r = APIRouter()

    @r.get("/api/diagnostics")
    async def diagnostics() -> dict:
        return await run_in_threadpool(collect, d)

    return r
