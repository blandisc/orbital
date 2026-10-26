import sys
from pathlib import Path

from orbital import flags, player_ui

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import flags as flags_script  # noqa: E402


def test_the_web_flags_are_written_from_the_same_drawings():
    """La interfaz y el reproductor enseñan la misma bandera: los SVG y core/flags.js salen de orbital/flags.py."""
    for path, text in flags_script.outputs().items():
        assert path.read_text(encoding="utf-8") == text, f"{path.name} desactualizado: corre python scripts/flags.py"


def test_each_language_gets_its_flag_as_fernando_decided():
    """Igual que el iPhone: latino y el español que no dice cuál → México; castellano → España; portugués → Brasil."""
    assert flags.flag_for("es-419") == "mx" and flags.flag_for("spa", "Latino 5.1") == "mx"
    assert flags.flag_for("es-ES") == "es" and flags.flag_for("spa", "Castellano") == "es"
    assert flags.flag_for("spa") == "mx" and flags.flag_for("es") == "mx"
    assert flags.flag_for("eng") == "us" and flags.flag_for("en-GB") == "gb"
    assert flags.flag_for("por") == "br" and flags.flag_for("por", "Portugal") == "pt" and flags.flag_for("jpn") == "jp"
    assert flags.flag_for("ara") is None and flags.flag_for(None) is None and flags.flag_for("") is None


def test_the_player_draws_the_flag_before_the_language():
    tracks = [{"type": "audio", "id": 1, "lang": "spa", "title": "Latino", "selected": True},
              {"type": "audio", "id": 2, "lang": "eng"}, {"type": "sub", "id": 3, "lang": "spa"}]
    panel = player_ui.tracks_panel(tracks, 1.0)
    audio = panel.columns[0].options
    assert [o["flag"] for o in audio] == ["mx", "us"]
    drawn = player_ui.panel_ass(panel)
    assert drawn.count("\clip(") >= len(flags.FLAGS["mx"]) + len(flags.FLAGS["us"])  # cada figura, recortada a la silueta
    assert "&H476800&" in drawn  # el verde de México (#006847, en ASS va al revés)
