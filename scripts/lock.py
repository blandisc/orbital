"""Escribe requirements.lock y requirements-dev.lock con las versiones exactas del entorno actual.

Sin herramientas extra (ni uv ni pip-tools): se sigue el árbol de dependencias de pyproject.toml
en el .venv que ya funciona. Para actualizar: `pip install -U ...`, correr las pruebas y luego

    python scripts/lock.py
"""

from __future__ import annotations

import re
import sys
import tomllib
from importlib import metadata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER_OK = {"sys_platform": sys.platform, "platform_system": "Windows" if sys.platform == "win32" else "",
             "python_version": f"{sys.version_info.major}.{sys.version_info.minor}"}


def _name(req: str) -> str:
    return re.split(r"[\s;<>=!~\[(]", req, maxsplit=1)[0].lower().replace("_", "-")


def _applies(req: str) -> bool:
    """Las dependencias con 'extra ==' no se instalan solas; el resto se evalúan con este equipo."""
    if ";" not in req:
        return True
    marker = req.split(";", 1)[1]
    if "extra" in marker:
        return False
    try:
        from packaging.markers import Marker  # viene con pip/setuptools casi siempre

        return Marker(marker).evaluate()
    except ImportError:
        return True


def closure(roots: list[str]) -> dict[str, str]:
    found: dict[str, str] = {}
    pending = [_name(r) for r in roots]
    while pending:
        name = pending.pop()
        if name in found:
            continue
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            print(f"aviso: {name} no está instalado", file=sys.stderr)
            continue
        found[name] = dist.version
        pending += [_name(r) for r in dist.requires or [] if _applies(r)]
    return found


def write(path: Path, pins: dict[str, str], header: str) -> None:
    lines = [f"# {header}", "# Generado por scripts/lock.py — no editar a mano.", ""]
    lines += [f"{name}=={version}" for name, version in sorted(pins.items())]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{path.name}: {len(pins)} paquetes")


def main() -> None:
    project = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))["project"]
    runtime = closure(project["dependencies"])
    dev = closure(project["dependencies"] + project["optional-dependencies"]["dev"])
    write(ROOT / "requirements.lock", runtime, "Orbital: lo que necesita para correr")
    write(ROOT / "requirements-dev.lock", dev, "Orbital: lo de correr + pruebas y revisión de código")


if __name__ == "__main__":
    main()
