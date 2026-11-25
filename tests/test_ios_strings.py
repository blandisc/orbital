"""Con la app del iPhone en inglés, ningún texto de pantalla se queda en español (24 nov 2026: quedaban 102)."""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_every_iphone_text_has_english():
    # En Windows el script escribe en la página de códigos de la consola: sin PYTHONIOENCODING, los acentos de su aviso
    # rompían la lectura y la prueba tronaba con un TypeError en vez de decir qué texto falta.
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    run = subprocess.run([sys.executable, str(ROOT / "scripts/ios_strings.py"), "--check"], capture_output=True, text=True, encoding="utf-8",
                         env=env)
    assert run.returncode == 0, run.stdout + run.stderr
