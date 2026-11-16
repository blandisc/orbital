"""Ningún .py del repo tiene escapes inválidos («\\p», «\\d» en un texto normal): Python los avisa con SyntaxWarning y un
día serán error. Se escribe «\\\\» o un texto r"…" (16 nov 2026: la CI de Windows mostraba siete de estos avisos)."""

import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_no_python_file_has_invalid_escapes():
    found = []
    for path in sorted(ROOT.glob("**/*.py")):
        if any(part.startswith(".") or part in {"node_modules", "build"} for part in path.relative_to(ROOT).parts):
            continue
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            compile(path.read_text(encoding="utf-8-sig"), str(path), "exec")
        found += [f"{path.relative_to(ROOT)}:{w.lineno}: {w.message}" for w in caught if issubclass(w.category, SyntaxWarning)]
    assert not found, "Escapes inválidos:\n" + "\n".join(found)
