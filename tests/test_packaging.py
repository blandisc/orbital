"""Las tablas compartidas con el iPhone (`design/*.json`) viajan con Orbital empaquetado y se leen igual desde git
(revisión del 11 nov 2026: el ejecutable se quedaba sin idiomas para elegir versión y sin tabla de Real-Debrid)."""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tomllib
import zipfile
from pathlib import Path

import pytest

from orbital import shared

ROOT = Path(__file__).resolve().parents[1]
READ_BY_PYTHON = ("streams-rules.json", "realdebrid-errors.json", "awards.json")


def test_every_subpackage_is_listed_for_the_wheel():
    config = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))["tool"]["setuptools"]
    found = {".".join(p.parent.relative_to(ROOT).parts) for p in (ROOT / "orbital").rglob("__init__.py")
             if "web" not in p.parts}
    assert set(config["packages"]) == found | {"orbital.design"}
    assert config["package-dir"]["orbital.design"] == "design"
    assert "*.json" in config["package-data"]["orbital.design"]


def test_the_executable_carries_the_tables():
    spec = importlib.util.spec_from_file_location("build_exe", ROOT / "scripts" / "build_exe.py")
    build = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(build)
    args = build.pyinstaller_args(Path("entry.py"), ";")
    data = [args[i + 1] for i, a in enumerate(args) if a == "--add-data"]
    for name in READ_BY_PYTHON:
        assert f"{ROOT / 'design' / name};orbital/design" in data


@pytest.mark.skipif(importlib.util.find_spec("setuptools") is None, reason="sin setuptools no se arma la rueda aquí")
def test_the_wheel_carries_the_tables(tmp_path):
    source = tmp_path / "src"  # una copia: armar la rueda deja build/ y *.egg-info donde se arma
    for part in ("orbital", "design"):
        shutil.copytree(ROOT / part, source / part, ignore=shutil.ignore_patterns("__pycache__", "iconos-grok", "marca"))
    shutil.copy(ROOT / "pyproject.toml", source)
    out = subprocess.run([sys.executable, "-m", "pip", "wheel", "--no-deps", "--no-build-isolation", "-q", "-w",
                          str(tmp_path / "dist"), str(source)], capture_output=True, text=True, timeout=300)
    if out.returncode != 0 and "No module named" in out.stderr:
        pytest.skip(out.stderr[-200:])
    assert out.returncode == 0, out.stderr[-2000:]
    names = zipfile.ZipFile(next((tmp_path / "dist").glob("*.whl"))).namelist()
    for name in READ_BY_PYTHON:
        assert f"orbital/design/{name}" in names
    assert "orbital/web/index.html" in names and "orbital/library/streams/__init__.py" in names


def test_tables_are_found_from_git_and_from_the_package(tmp_path, monkeypatch):
    assert shared.design_file("streams-rules.json") == ROOT / "design" / "streams-rules.json"  # desde git
    package = tmp_path / "site-packages" / "orbital"  # instalado: no hay design/ junto al paquete, sí adentro
    (package / "design").mkdir(parents=True)
    (package / "design" / "streams-rules.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(shared, "PACKAGE", package)
    assert shared.design_file("streams-rules.json") == package / "design" / "streams-rules.json"


def _import_streams_with(rules: dict, tmp_path: Path) -> subprocess.CompletedProcess:
    bad = tmp_path / "streams-rules.json"
    bad.write_text(json.dumps(rules), encoding="utf-8")
    code = ("import logging, sys; from pathlib import Path; logging.basicConfig(level=logging.ERROR);"
            "import orbital.shared as s; s.design_file = lambda name: Path(sys.argv[1]);"
            "import orbital.library.streams as st;"
            "print(len(st.WORD_LANG), st.TOO_BIG_DEFAULT_GB, st.TOO_BIG_GB['4K'], st.FLAG_LANG.get('🇲🇽'))")
    return subprocess.run([sys.executable, "-c", code, str(bad)], capture_output=True, text=True, timeout=60, cwd=ROOT)


def test_a_badly_written_rule_is_skipped_and_orbital_still_starts(tmp_path):
    rules = {"words": [{"pattern": "(sin cerrar", "lang": "es"}, {"lang": "en"}, "no soy una regla",
                       {"pattern": r"\blatino\b", "lang": "es-419", "flags": "i"}],
             "codes": {"no": "lista"},
             "size": {"too_big_default_gb": "mucho", "too_big_gb": {"4K": "sesenta", "1080p": 20}},
             "flags": {"🇲🇽": "es-419", "🇪🇸": 3}}
    out = _import_streams_with(rules, tmp_path)
    assert out.returncode == 0, out.stderr  # antes: re.error al importar y Orbital no arrancaba
    words, default, big, flag = out.stdout.split()
    assert (int(words), float(default), float(big), flag) == (1, 15.0, 60.0, "es-419")  # la buena sí; lo malo, con su respaldo
    assert out.stderr.count("regla inválida") >= 5  # cada una, a la bitácora


def test_a_bad_row_in_the_real_debrid_table_does_not_lose_the_rest(tmp_path):
    from orbital.library import realdebrid

    table = tmp_path / "realdebrid-errors.json"
    table.write_text(json.dumps({"codes": {"8": {"cause": "invalid_session"}, "x": {"cause": "gone"}, "9": "roto"},
                                 "http": {"401": "invalid_session"}}), encoding="utf-8")
    codes, http = realdebrid.load_errors(table)
    assert codes == {8: "invalid_session"} and http == {401: "invalid_session"}
