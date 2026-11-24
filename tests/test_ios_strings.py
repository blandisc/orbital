"""Con la app del iPhone en inglés, ningún texto de pantalla se queda en español (24 nov 2026: quedaban 102)."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_every_iphone_text_has_english():
    run = subprocess.run([sys.executable, str(ROOT / "scripts/ios_strings.py"), "--check"], capture_output=True, text=True, encoding="utf-8")
    assert run.returncode == 0, run.stdout + run.stderr
