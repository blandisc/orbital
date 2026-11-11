"""Dónde están las tablas que comparten la TV y el iPhone (`design/*.json`: reglas para elegir versión, errores de
Real-Debrid, premios…).

Desde git viven en `design/`, junto a la carpeta `orbital/`. Empaquetado (la rueda de pip o Orbital.exe) viajan DENTRO del
paquete, en `orbital/design/` (`pyproject.toml` mapea `orbital.design` a `design/`; `scripts/build_exe.py` las copia).
`design_file` busca primero la de git y luego la del paquete: así las dos formas de correr leen lo mismo.
"""

from __future__ import annotations

from pathlib import Path

PACKAGE = Path(__file__).resolve().parent


def design_file(name: str) -> Path:
    """La ruta de `design/<name>`: la de git si existe; si no, la que viaja en el paquete. Si no está en ningún lado,
    la de git (quien la lee anota que falta y sigue con su respaldo)."""
    for folder in (PACKAGE.parent / "design", PACKAGE / "design"):
        candidate = folder / name
        if candidate.is_file():
            return candidate
    return PACKAGE.parent / "design" / name
