"""Los valores de diseño compartidos salen de design/tokens.json (F3): el bloque «generado» de tokens.css (la TV) y el de
DesignTokens.swift (el iPhone) están al día. Si falla: python scripts/generar_tokens.py."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _generator():
    spec = importlib.util.spec_from_file_location("generar_tokens", ROOT / "scripts" / "generar_tokens.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_shared_tokens_are_generated_from_tokens_json():
    stale = _generator().stale()
    assert stale == [], f"No están al día (corre python scripts/generar_tokens.py): {[str(p.relative_to(ROOT)) for p in stale]}"


def test_the_generated_block_is_only_between_its_marks():
    gen = _generator()
    css = gen.CSS.read_text(encoding="utf-8")
    start, end = css.index(gen.CSS_MARKS[0]), css.index(gen.CSS_MARKS[1])
    before, after = css[:start], css[end + len(gen.CSS_MARKS[1]):]
    outside = before + after  # lo compartido se define solo en el bloque
    assert not re.search(r"^\s*--(palette|space|weight)-[\w-]+:", outside, re.M)
    assert "--radius-pill" in after and "--duration-snap" in after  # lo de la TV sigue fuera, escrito a mano
