"""Punto de entrada: `python -m orbital` o `orbital`."""

from __future__ import annotations

import argparse
import logging
import os
import sys
import threading
import time
import urllib.request
from pathlib import Path

import uvicorn

from .config import default_config_path, load_config
from .kiosk import KioskWindow
from .server import create_app, create_public_app

log = logging.getLogger("orbital")

def wait_until_up(url: str, timeout: float = 20) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url + "/api/health", timeout=1):
                return True
        except OSError:
            time.sleep(0.3)
    return False


def open_window(url: str) -> None:
    import webview  # pywebview, opcional: pip install "orbital[window]"

    webview.create_window("Orbital", url, fullscreen=True)
    webview.start()


def print_diagnostics(catalog) -> None:
    from .library import emulators

    ok, bad = "OK ", "!! "
    print("== Diagnóstico")
    print(f"  {ok if catalog.steam_root else bad}Steam: {catalog.steam_root or 'no encontrado'}")
    lib = catalog.esde
    if catalog.config.esde.enabled:
        print(f"  {ok if lib else bad}ES-DE: {lib.home if lib else 'no encontrado (pon esde.path)'}")
        if lib:
            print(f"     ROMs: {lib.rom_root}   portadas: {lib.media_root}")
    counts: dict[str, int] = {}
    for item in catalog.items():
        counts[item.source] = counts.get(item.source, 0) + 1
    if not catalog.emulators:
        print("  !! No hay emuladores: ni en config.yaml ni detectados (revisa detect.dirs)")
    for emu, alternatives in emulators.split_alternatives(catalog.emulators):
        dirs = ", ".join(str(d) for d in emulators.rom_dirs(emu, lib)) or "sin carpeta"
        print(f"  {emu.name}: {counts.get(emu.id, 0)} juegos en {dirs}")
        for each in [emu, *alternatives]:
            exe = emulators.resolve_executable(each)
            role = "principal" if each is emu else "alternativo (ES-DE o menú Y de Orbital)"
            origin = "detectado" if each.id in catalog.detected else "config.yaml"
            name = emulators.runner_name(each, exe)
            print(f"    {ok if exe else bad}{name} [{role}, {origin}]: {exe or 'NO ENCONTRADO -> ' + each.executable}")


def stremio_command(args, config) -> int:
    from .catalog import Catalog, STREMIO_KEY
    from .library.stremio_api import StremioError

    catalog = Catalog(config)
    try:
        if args.action == "login":
            import getpass

            email = input("Correo de Stremio: ").strip()
            password = getpass.getpass("Contraseña (no se guarda): ")
            key = catalog.stremio_client.login(email, password)
            count = catalog.link_stremio(key)
            print(f"Listo: cuenta vinculada, {count} títulos en tu biblioteca.")
        elif args.action == "key":
            count = catalog.link_stremio(args.value)
            print(f"Listo: clave guardada, {count} títulos en tu biblioteca.")
        elif args.action == "logout":
            catalog.unlink_stremio()
            print("Cuenta de Stremio desvinculada de Orbital.")
        else:  # status
            if not catalog.credentials.get(STREMIO_KEY):
                print("Stremio no está vinculado. Usa: orbital stremio login")
                return 1
            catalog.refresh_stremio()
            if catalog.stremio_error:
                print(f"!! {catalog.stremio_error}")
                return 1
            watching = [i for i in catalog.stremio_library() if i.category == "continue"]
            print(f"OK Stremio vinculado: {len(catalog.stremio_library())} títulos, {len(watching)} en Seguir viendo")
            for item in sorted(watching, key=lambda i: i.last_watched or 0, reverse=True)[:10]:
                pct = f"{item.progress:.0%}" if item.progress else ""
                print(f"   {item.title:<40} {item.subtitle:<22} {pct}")
    except StremioError as exc:
        print(f"!! {exc}")
        return 1
    return 0


def alexa_command(args, config) -> int:
    from . import alexa_setup

    path = config.source
    url = args.url or alexa_setup.tailscale_url()
    public_port = config.server.public_port or 8711

    if args.action == "setup":
        token, created = alexa_setup.ensure_token(path)
        skill_dir = path.parent / "alexa-skill"
        alexa_setup.write_skill(skill_dir, alexa_setup.skill_files(url, token, args.skill_id or ""))
        print("== Alexa para Orbital\n")
        print(f"  Token     : {'creado y guardado' if created else 'ya existía'} en {path}")
        if created:
            print("              (reinicia Orbital para que lo use)")
        print(f"  Puerto    : {public_port}  (solo voz y ping, siempre con token; la interfaz NO sale a internet)")
        if url:
            print(f"  Túnel     : {url}  (Tailscale)")
        else:
            print("  Túnel     : no detecté Tailscale. Instálalo desde https://tailscale.com/download e inicia sesión,")
            print("              y vuelve a correr este comando para que la skill lleve la dirección.")
        print(f"  Skill     : {skill_dir}")
        print("              (orbital.json lleva el token: no lo compartas, con él se controla tu consola)")
        print("\nPasos:")
        print(f"  1. Abre el túnel (una sola vez, queda activo tras reiniciar):  tailscale funnel --bg {public_port}")
        print("     La primera vez Tailscale te da un enlace para activar HTTPS y Funnel: ábrelo y acepta.")
        print("  2. Comprueba:  orbital alexa check")
        print("  3. Crea la skill alojada por Amazon (README, sección Alexa) y pega ahí los archivos de la carpeta Skill.")
        return 0

    token = alexa_setup.read_token(path)
    if not token:
        print("!! No hay token en config.yaml. Corre primero: orbital alexa setup")
        return 1
    if not url:
        print("!! No sé la dirección del túnel. Usa --url https://<tu-equipo>.<tu-tailnet>.ts.net")
        return 1
    if args.action == "check":
        print(f"Comprobando {url} ...")
        checks = alexa_setup.check_tunnel(url, token)
        for check in checks:
            print(f"  {'OK' if check.ok else '!!'} {check.label}" + (f"\n     {check.detail}" if check.detail else ""))
        ok = all(c.ok for c in checks)
        print("\nTodo listo: prueba la skill en la pestaña Test de la consola de Alexa." if ok
              else "\nHay problemas: revisa los puntos marcados con !!")
        return 0 if ok else 1
    ok, speech = alexa_setup.say(url, token, args.text)  # action == "say"
    print(f"{'OK' if ok else '!!'} Orbital respondió: {speech}")
    return 0 if ok else 1


def serve(config, app, public_app) -> None:
    """Interfaz/API en server.port y, si está activo, el puerto de Alexa en server.public_port."""
    import asyncio

    servers = [uvicorn.Server(uvicorn.Config(app, host=config.server.host, port=config.server.port, log_level="info"))]
    if public_app is not None:
        servers.append(uvicorn.Server(uvicorn.Config(public_app, host=config.server.host,
                                                     port=config.server.public_port, log_level="warning")))

    async def run_all():
        await asyncio.gather(*(s.serve() for s in servers))

    asyncio.run(run_all())


def log_file_path() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "orbital" / "orbital.log"


def ensure_streams() -> Path | None:
    """Con pythonw.exe (acceso directo de inicio) no hay consola: sys.stdout/stderr son None y
    uvicorn no arranca. En ese caso todo va a orbital.log (y la ejecución anterior a orbital.log.1)."""
    if sys.stdout is not None and sys.stderr is not None:
        return None
    path = log_file_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.replace(path.with_suffix(".log.1"))
    stream = open(path, "w", encoding="utf-8", buffering=1)  # noqa: SIM115 - vive todo el proceso
    sys.stdout = sys.stdout or stream
    sys.stderr = sys.stderr or stream
    return path


def main(argv: list[str] | None = None) -> None:
    ensure_streams()
    parser = argparse.ArgumentParser(prog="orbital", description="Interfaz de consola para Legion Go")
    parser.add_argument("-c", "--config", type=Path, help=f"Ruta del config.yaml (por defecto {default_config_path()})")
    parser.add_argument("--ui", choices=["browser", "window", "none"], help="Sobrescribe ui.mode")
    parser.add_argument("--list", action="store_true", help="Muestra la biblioteca detectada y sale")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command")
    st = sub.add_parser("stremio", help="Vincular tu cuenta de Stremio (fila Seguir viendo)")
    st.add_argument("action", choices=["login", "key", "status", "logout"],
                    help="login: correo y contraseña · key: pegar la clave de sesión · status · logout")
    st.add_argument("value", nargs="?", help="la clave de sesión (para 'key')")
    al = sub.add_parser("alexa", help="Configurar y comprobar Alexa")
    al.add_argument("action", choices=["setup", "check", "say"],
                    help="setup: token y pasos · check: prueba el túnel · say: envía un comando de prueba")
    al.add_argument("text", nargs="?", default="qué está abierto", help="el comando para 'say'")
    al.add_argument("--url", help="dirección pública del túnel (si no se detecta Tailscale)")
    al.add_argument("--skill-id", help="ID de tu skill (amzn1.ask.skill…): la skill rechaza peticiones de otras")
    args = parser.parse_args(argv)
    if args.command == "stremio" and args.action == "key" and not args.value:
        parser.error("falta la clave: orbital stremio key <clave>")

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    config = load_config(args.config)
    log.info("Configuración: %s", config.source)

    if args.command == "stremio":
        raise SystemExit(stremio_command(args, config))
    if args.command == "alexa":
        raise SystemExit(alexa_command(args, config))
    if config.server.token_is_ephemeral:
        log.warning("No hay token en config.yaml: Alexa no podrá conectarse. Ejecuta: orbital alexa setup")

    if args.list:
        from .catalog import Catalog

        catalog = Catalog(config)
        catalog.refresh()
        print_diagnostics(catalog)
        for row in catalog.grouped():
            print(f"\n== {row['title']} ({len(row['items'])})")
            for item in row["items"]:
                print(f"  {item['title']:<50} {item['id']}")
        return

    url = f"http://127.0.0.1:{config.server.port}"
    mode = args.ui or config.ui.mode
    kiosk = KioskWindow(url, config.ui.browser) if mode == "browser" else None
    app = create_app(config, kiosk=kiosk, shortcuts=True)
    public_app = create_public_app(config, app) if config.server.public_port else None
    if mode == "window":
        # pywebview necesita el hilo principal, así que el servidor va en segundo plano.
        server = threading.Thread(target=serve, args=(config, app, public_app), daemon=True)
        server.start()
        wait_until_up(url)
        open_window(url)
        return
    if kiosk:
        threading.Thread(target=lambda: wait_until_up(url) and kiosk.open(), daemon=True).start()
    serve(config, app, public_app)

if __name__ == "__main__":
    main()
