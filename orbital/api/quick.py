"""Panel rápido (volumen, brillo, energía, batería) y galería de capturas."""

from __future__ import annotations

import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, Response

from .. import capture, dwm_release, gamepad, health, memory, music, quick
from ..players import players
from .deps import Deps

_LOCAL = re.compile(r"^[A-Za-z]:\\(?!\\)")


def _inside_gallery(path: str) -> Path:
    """Solo imágenes y videos de las carpetas de capturas: nunca rutas arbitrarias. Las rutas de red
    (servidor compartido) se rechazan ANTES de tocarlas: resolverlas colgaba un hilo y abría una conexión SMB."""
    # Solo rutas locales absolutas «C:\…»: «/\servidor», «\\?\UNC», «C:relativa» y similares, fuera.
    path = path.replace("/", "\\") if isinstance(path, str) else ""
    if not path or chr(0) in path or not _LOCAL.match(path) or len(path) > 1024:
        raise HTTPException(404, "Esa captura ya no está")
    try:
        target = Path(path).resolve()
    except (OSError, ValueError) as exc:
        raise HTTPException(404, "Esa captura ya no está") from exc
    inside = any(target.is_relative_to(folder.resolve()) for folder in capture.folders())
    if not inside or target.suffix.lower() not in capture.IMAGE_EXT | capture.VIDEO_EXT or not target.is_file():
        raise HTTPException(404, "Esa captura ya no está")
    return target


def router(d: Deps) -> APIRouter:
    r = APIRouter()

    def protected() -> set[int]:
        """Lo que nunca se ofrece cerrar: Orbital, su ventana y el juego abierto (ese se cierra aparte)."""
        import os

        from .. import windows

        keep = {os.getpid(), os.getppid()}
        running = d.catalog.launcher.status()
        if running and running.get("pid"):
            keep |= windows.process_tree(int(running["pid"]))
        return keep

    @r.get("/api/music")
    async def music_now() -> dict:
        return {"now": await run_in_threadpool(music.now_playing), "apple_music": music.apple_music_installed()}

    @r.post("/api/music")
    async def music_command(body: dict) -> dict:
        action = str(body.get("action") or "")
        if action not in ("toggle", "play", "pause", "next", "previous"):
            raise HTTPException(422, "Acción desconocida")
        ok = await run_in_threadpool(music.command, action)
        return {"ok": ok, "now": await run_in_threadpool(music.now_playing)}

    @r.get("/api/music/art")
    async def music_art() -> Response:
        data = await run_in_threadpool(music.art)
        if not data:
            raise HTTPException(404)
        return Response(data, media_type="image/png" if data[:4] == bytes([137, 80, 78, 71]) else "image/jpeg",
                        headers={"Cache-Control": "no-cache"})

    @r.get("/api/memory")
    async def memory_usage() -> dict:
        def read() -> dict:
            dwm = health.dwm_gpu_mb()
            # La memoria de video que Windows se queda (ver dwm_release.py): cuánta y si se puede liberar sin reiniciar.
            video = None if dwm is None else {"dwm_mb": dwm[0], "release": "ready" if dwm_release.available() else "setup"}
            return {"room_mb": health.commit_room_mb(), "free_mb": health.free_ram_mb(), "video": video,
                    "apps": [a.public() for a in memory.usage(protect_pids=protected())]}
        return await run_in_threadpool(read)

    @r.get("/api/players")
    async def players_list() -> dict:
        """Jugadores: quién es quién y, con un juego abierto, si toma un control nuevo solo o hay que reiniciarlo."""
        def read() -> dict:
            from .. import windows

            running = d.catalog.launcher.status()
            game = None
            if running and running.get("managed"):
                exe = windows.exe_name(int(running["pid"])) if running.get("pid") else ""
                game = {"title": running.get("title"), "live_join": exe in d.shell.LIVE_JOIN}
            return {"players": players.snapshot(), "game": game}
        return await run_in_threadpool(read)

    @r.post("/api/players/first")
    def players_first(body: dict) -> dict:
        slot = body.get("slot")
        if not isinstance(slot, int) or not players.make_first(slot):
            raise HTTPException(404, "Ese control ya no está conectado")
        return {"ok": True, "players": players.snapshot()}

    @r.post("/api/players/identify")
    def players_identify(body: dict) -> dict:
        """Hace vibrar ese control: «¿cuál es el Jugador 2?»."""
        slot = body.get("slot")
        if not isinstance(slot, int) or not 0 <= slot < 4:
            raise HTTPException(422, "Control desconocido")
        return {"ok": gamepad.rumble(slot, seconds=.6, strength=.8)}

    @r.post("/api/players/restart")
    def players_restart() -> dict:
        d.shell.unpause()  # estaba congelado por Home: que se cierre limpio
        if not d.catalog.sessions.restart_with_players():
            raise HTTPException(409, "No hay un juego abierto que se pueda reiniciar")
        return {"ok": True}

    @r.post("/api/video-memory/release")
    def video_memory_release() -> dict:
        """Reiniciar DWM para que suelte la memoria de video: la pantalla parpadea. Nunca con un juego o video abierto."""
        if d.catalog.launcher.status():
            raise HTTPException(409, "Cierra el juego o el video primero: la pantalla parpadea un momento")
        if not dwm_release.available():
            raise HTTPException(409, "Primero actívalo (Windows pide permiso una vez)")
        before = health.dwm_gpu_mb()
        if not dwm_release.run():
            raise HTTPException(500, "Windows no lo dejó")
        return {"ok": True, "before_mb": before[0] if before else None}

    @r.post("/api/video-memory/setup")
    async def video_memory_setup() -> dict:
        """Crea la tarea de Windows que lo permite. Windows muestra su aviso de permiso en la pantalla."""
        return {"ok": await run_in_threadpool(dwm_release.setup)}

    @r.post("/api/memory/close")
    def memory_close(body: dict) -> dict:
        try:
            freed = memory.close(str(body.get("exe") or ""), protect_pids=protected())
        except LookupError as exc:
            raise HTTPException(404, str(exc))
        except PermissionError as exc:
            raise HTTPException(409, str(exc))
        return {"ok": True, "freed_mb": freed}

    @r.get("/api/quick")
    async def get_quick() -> dict:
        return await run_in_threadpool(quick.snapshot)

    @r.post("/api/quick")
    def set_quick(body: dict) -> dict:
        # Se valida todo antes de tocar nada (tipos exactos: "false" no es un booleano).
        number = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 100  # noqa: E731
        if "volume" in body and not number(body["volume"]):
            raise HTTPException(422, "Volumen: un número de 0 a 100")
        if "brightness" in body and not number(body["brightness"]):
            raise HTTPException(422, "Brillo: un número de 0 a 100")
        if "muted" in body and not isinstance(body["muted"], bool):
            raise HTTPException(422, "Silencio: sí o no")
        if "power_mode" in body and (not isinstance(body["power_mode"], str) or body["power_mode"] not in quick.POWER_MODES):
            raise HTTPException(422, "Modo de energía desconocido")
        if "volume" in body:
            quick.set_volume(level=int(body["volume"]))
        if "muted" in body:
            quick.set_volume(muted=body["muted"])
        if "brightness" in body:
            quick.set_brightness(int(body["brightness"]))
        if "power_mode" in body:
            quick.set_power_mode(body["power_mode"])
        return quick.snapshot()

    @r.post("/api/capture")
    def take_capture() -> dict:
        running = d.catalog.launcher.status()
        event = capture.take_and_describe(running["title"] if running else "")
        return {"ok": event.get("ok", True), "message": event["message"]}

    @r.get("/api/captures")
    async def captures() -> dict:
        items = await run_in_threadpool(capture.gallery)
        return {"items": items, "folders": [str(f) for f in capture.folders()]}

    @r.get("/api/captures/file")
    def capture_file(path: str) -> FileResponse:
        return FileResponse(_inside_gallery(path), headers={"Cache-Control": "max-age=3600"})

    @r.post("/api/captures/open")
    def open_capture(body: dict) -> dict:
        """Un clip: se abre con su reproductor (fuera de Orbital)."""
        target = _inside_gallery(str(body.get("path") or ""))
        d.catalog.launcher.open_uri(str(target))
        return {"ok": True}

    return r
