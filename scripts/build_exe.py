"""Empaqueta Orbital como Orbital.exe (carpeta dist/Orbital), sin depender de Python instalado.

    pip install pyinstaller
    python scripts/build_exe.py

La carpeta resultante se puede copiar a cualquier Windows. Ojo: esa copia no se actualiza con
"Actualizar Orbital" (eso usa git); para actualizarla se vuelve a empaquetar.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    import PyInstaller.__main__

    entry = ROOT / "build" / "orbital_entry.py"
    entry.parent.mkdir(exist_ok=True)
    entry.write_text("from orbital.__main__ import main\n\nmain()\n", encoding="utf-8")
    sep = ";" if sys.platform == "win32" else ":"
    PyInstaller.__main__.run([
        str(entry), "--name", "Orbital", "--noconfirm", "--clean", "--windowed",
        "--icon", str(ROOT / "orbital" / "web" / "icons" / "orbital.ico"),
        "--paths", str(ROOT),
        "--add-data", f"{ROOT / 'orbital' / 'web'}{sep}orbital/web",
        "--add-data", f"{ROOT / 'alexa'}{sep}alexa",
        "--collect-submodules", "orbital",
        "--collect-submodules", "uvicorn",
        "--distpath", str(ROOT / "dist"), "--workpath", str(ROOT / "build" / "pyinstaller"),
        "--specpath", str(ROOT / "build"),
    ])
    print("Listo:", ROOT / "dist" / "Orbital" / "Orbital.exe")


if __name__ == "__main__":
    main()
