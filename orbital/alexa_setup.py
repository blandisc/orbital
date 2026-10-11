"""Asistente de Alexa: token fijo, detección del túnel de Tailscale y comprobación de extremo a extremo."""

from __future__ import annotations

import json
import re
import secrets
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

PLACEHOLDER_TOKENS = {"", "CAMBIA-ESTE-TOKEN"}


# ----------------------------------------------------------------------------- token
def ensure_token(config_path: Path) -> tuple[str, bool]:
    """Garantiza un token fijo en config.yaml (Alexa necesita siempre el mismo).

    Devuelve (token, creado). Edita el texto para no perder los comentarios del archivo.
    """
    import yaml

    text = config_path.read_text(encoding="utf-8-sig") if config_path.exists() else ""
    server = (yaml.safe_load(text) or {}).get("server") or {}
    current = str(server.get("token") or "").strip()
    if current not in PLACEHOLDER_TOKENS:
        return current, False

    token = secrets.token_urlsafe(32)
    line = re.search(r'^(?P<indent>[ \t]+)token:.*$', text, re.MULTILINE)
    if line:
        text = text[:line.start()] + f'{line.group("indent")}token: "{token}"' + text[line.end():]
    elif re.search(r"^server:[ \t]*$", text, re.MULTILINE):
        text = re.sub(r"^server:[ \t]*$", f'server:\n  token: "{token}"', text, count=1, flags=re.MULTILINE)
    elif not server and not re.search(r"^server:", text, re.MULTILINE):
        text = f'server:\n  token: "{token}"\n' + (("\n" + text) if text else "")
    else:
        raise ValueError(f'No sé editar la sección server de {config_path}: añade  token: "{token}"  a mano.')
    if (yaml.safe_load(text) or {}).get("server", {}).get("token") != token:
        raise ValueError(f"No pude guardar el token en {config_path}")
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(text, encoding="utf-8")
    return token, True


def read_token(config_path: Path) -> str | None:
    """El token de config.yaml, sin crear nada (para comprobar o probar)."""
    import yaml

    if not config_path.exists():
        return None
    server = (yaml.safe_load(config_path.read_text(encoding="utf-8-sig")) or {}).get("server") or {}
    token = str(server.get("token") or "").strip()
    return None if token in PLACEHOLDER_TOKENS else token


# ----------------------------------------------------------------------------- skill
SKILL_SOURCE = Path(__file__).resolve().parent.parent / "alexa"


def skill_files(url: str | None, token: str, skill_id: str = "") -> dict[str, str]:
    """Los archivos de la carpeta `lambda` de la skill alojada por Amazon (Alexa-hosted), más el
    modelo de voz para pegar en el editor JSON."""
    # Sin túnel todavía, la URL va vacía: la skill dice "no está configurada" en vez de "apagada".
    config = {"url": url or "", "token": token}
    if skill_id:
        config["skill_id"] = skill_id
    return {
        "lambda_function.py": (SKILL_SOURCE / "lambda_function.py").read_text(encoding="utf-8"),
        "orbital.json": json.dumps(config, indent=2) + "\n",
        "interaction_model.es-MX.json": (SKILL_SOURCE / "interaction_model.es-MX.json").read_text(encoding="utf-8"),
    }


def write_skill(dest: Path, files: dict[str, str]) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (dest / name).write_text(content, encoding="utf-8")


# ----------------------------------------------------------------------------- túnel
def tailscale_exe() -> str | None:
    found = shutil.which("tailscale")
    if found:
        return found
    if sys.platform == "win32":
        default = Path(r"C:\Program Files\Tailscale\tailscale.exe")
        return str(default) if default.exists() else None
    return None


def parse_tailscale_status(raw: str) -> str | None:
    """De `tailscale status --json` saca https://<equipo>.<tailnet>.ts.net"""
    try:
        dns = (json.loads(raw).get("Self") or {}).get("DNSName", "")
    except ValueError:
        return None
    dns = dns.rstrip(".")
    return f"https://{dns}" if dns else None


def tailscale_url() -> str | None:
    exe = tailscale_exe()
    if not exe:
        return None
    kwargs = {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}  # type: ignore[attr-defined]
    try:
        out = subprocess.run([exe, "status", "--json"], capture_output=True, text=True, timeout=8, **kwargs)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return parse_tailscale_status(out.stdout) if out.returncode == 0 else None


# ----------------------------------------------------------------------------- comprobación
@dataclass
class Check:
    ok: bool
    label: str
    detail: str = ""


def _get(url: str, token: str | None = None, data: dict | None = None, timeout: float = 10) -> tuple[int, str]:
    headers = {"Content-Type": "application/json", "User-Agent": "Orbital-check"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.status, res.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def check_tunnel(url: str, token: str, fetch=_get) -> list[Check]:
    """Comprueba que el túnel llega al puerto de Alexa, que exige token y que no expone la interfaz."""
    url = url.rstrip("/")
    checks: list[Check] = []
    try:
        status, body = fetch(f"{url}/api/ping", token)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return [Check(False, "El túnel responde", f"No pude conectar con {url}: {exc}. "
                      "¿Está corriendo `tailscale funnel --bg 8711`?")]
    if status == 401:
        return [Check(False, "El túnel responde", "Llega a Orbital pero el token no coincide con config.yaml.")]
    if status != 200 or '"service":"orbital"' not in body.replace(" ", ""):
        return [Check(False, "El túnel responde",
                      f"Respondió HTTP {status} pero no es el puerto de Alexa de Orbital. "
                      "El túnel debe apuntar al puerto 8711 (server.public_port).")]
    checks.append(Check(True, "El túnel llega al puerto de Alexa de Orbital"))

    status, _ = fetch(f"{url}/api/ping")
    checks.append(Check(status == 401, "Sin token no deja pasar",
                        "" if status == 401 else f"Respondió HTTP {status} sin token: revisa la configuración."))
    status, _ = fetch(f"{url}/api/library", token)
    checks.append(Check(status in (401, 404), "La interfaz y la biblioteca no se ven desde internet",
                        "" if status in (401, 404) else "¡El túnel apunta al puerto principal (8710)! Cámbialo a 8711."))
    return checks


def say(url: str, token: str, text: str, fetch=_get) -> tuple[bool, str]:
    try:
        status, body = fetch(f"{url.rstrip('/')}/api/voice", token, {"text": text})
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return False, f"No pude conectar con {url}: {exc}"
    if status != 200:
        return False, f"HTTP {status}: {body[:200]}"
    data = json.loads(body)
    return bool(data.get("ok")), data.get("speech", "")
