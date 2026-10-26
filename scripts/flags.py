"""Escribe las banderitas de la interfaz desde orbital/flags.py: web/img/flags/*.svg y web/js/core/flags.js.

    python scripts/flags.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from orbital import flags  # noqa: E402


def outputs() -> dict[Path, str]:
    web = ROOT / "orbital" / "web"
    files = {web / "img" / "flags" / f"{name}.svg": flags.svg(name) for name in flags.FLAGS}
    files[web / "js" / "core" / "flags.js"] = flags.js()
    return files


if __name__ == "__main__":
    for path, text in outputs().items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print(path.relative_to(ROOT))
