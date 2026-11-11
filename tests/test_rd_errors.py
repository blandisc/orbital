"""A15 · los errores de Real-Debrid salen de una sola tabla (design/realdebrid-errors.json), la misma del iPhone."""

import io
import json
import urllib.error
from pathlib import Path

import pytest

from orbital.library import realdebrid

TABLE = json.loads((Path(__file__).parents[1] / "design" / "realdebrid-errors.json").read_text(encoding="utf-8"))


def test_every_documented_code_has_a_known_cause():
    assert set(TABLE["codes"]) == {str(c) for c in range(-1, 38)} - {"0"}  # los de la documentación pública
    assert all(v["cause"] in TABLE["causes"] for v in TABLE["codes"].values())
    assert set(TABLE["causes"]) == set(realdebrid.CAUSES)
    assert realdebrid.ERROR_CODES == {int(k): v["cause"] for k, v in TABLE["codes"].items()}  # Python la lee de ahí


@pytest.mark.parametrize("case", TABLE["cases"], ids=lambda c: f"{c['http']}-{c['code']}-{c['cause']}")
def test_the_shared_cases(case):
    exc = realdebrid.RealDebridError("x", case["http"], case["code"])
    assert exc.cause == case["cause"]
    flags = {"too_many": exc.too_many, "refused": exc.refused, "slow_down": exc.slow_down, "gone": exc.gone,
             "invalid_session": exc.bad_key, "no_premium": exc.no_premium}
    assert [k for k, on in flags.items() if on] == ([case["cause"]] if case["cause"] != "other" else [])


@pytest.mark.parametrize("code,words", [(36, "Muchas descargas activas"), (34, "Real-Debrid no pudo con ese pedido"),
                                        (28, "Real-Debrid no lo dejó bajar"), (9, "Tu cuenta no tiene Premium"),
                                        (8, "Vuelve a conectar Real-Debrid")])
def test_the_words_follow_the_cause(code, words):
    body = io.BytesIO(json.dumps({"error": "x", "error_code": code}).encode())
    exc = urllib.error.HTTPError("https://api.real-debrid.com", 403, "no", {}, body)  # type: ignore[arg-type]
    assert realdebrid._why(exc) == (words, code)


def test_a_missing_table_still_reads_the_http(tmp_path):
    codes, http = realdebrid.load_errors(tmp_path / "no-existe.json")
    assert codes == {} and http[509] == "too_many" and http[401] == "invalid_session"
