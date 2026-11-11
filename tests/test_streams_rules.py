"""F2 · las reglas para elegir versión salen de design/streams-rules.json (las mismas que leerá el iPhone)."""

import json
from pathlib import Path

from orbital.library import streams

RULES = json.loads((Path(__file__).parents[1] / "design" / "streams-rules.json").read_text(encoding="utf-8"))


def test_the_tables_come_from_the_shared_file():
    assert streams.FLAG_LANG == RULES["flags"] and streams.SITE_LANG == RULES["sites"]
    assert [(p.pattern, lang) for p, lang in streams.WORD_LANG] == [(r["pattern"], r["lang"]) for r in RULES["words"]]
    assert [(p.pattern, lang) for p, lang in streams.CODE_LANG] == [(r["pattern"], r["lang"]) for r in RULES["codes"]]
    assert streams.TOO_BIG_GB == RULES["size"]["too_big_gb"] and streams.FIND_DEADLINE == RULES["waits"]["find_deadline_s"]
    assert streams.REQUEST_TIMEOUT == RULES["waits"]["per_addon_s"]


def test_the_shared_rules_still_read_a_real_name():
    src = streams.parse({"name": "Torrentio\n1080p [RD+]", "title": "Dune.2021.1080p.WEB-DL.LAT.ENG\n💾 2 GB\n🇲🇽 / 🇬🇧",
                         "url": "https://rd.example/x"}, "Torrentio", "https://t.example/manifest.json", 0)
    assert src.audio_langs == {"es-419": "name", "en": "name"}


def test_each_proposed_change_says_which_side_moves():
    rules = {"flags", "words", "size.too_big_gb.1440p", "waits.per_addon_s"}
    assert {u["rule"] for u in RULES["unify"]} == rules and all(u["changes"] in ("tv", "ios") for u in RULES["unify"])
    for u in RULES["unify"]:
        if u["rule"] == "words":
            for rule in u["proposed"]:  # que la propuesta ya compile como la leería la TV
                streams.re.compile(rule["pattern"])


def _langs(title: str) -> dict[str, str]:
    return streams.parse({"name": "Torrentio\n1080p [RD+]", "title": title, "url": "https://rd.example/x"}, "Torrentio",
                         "https://t.example/manifest.json", 0).audio_langs


def test_the_tv_reads_the_latino_marks_the_iphone_already_reads():
    """F2 · lo que `unify` pedía de la TV: las banderas 🇨🇴 🇨🇱 🇵🇪 🇻🇪 y las marcas de Streams.moreWordLanguages."""
    for flag in ("🇨🇴", "🇨🇱", "🇵🇪", "🇻🇪"):
        assert _langs(f"Dune.2021.1080p.WEB-DL\n💾 2 GB\n{flag}") == {"es-419": "name"}
    for name in ("Los.Simpson.S08E23.1080p.WEB-DL [lat]", "Dune.2021.1080p.WEB-DL.Esp-Lat", "Dune.2021.1080p.Lat-Ing",
                 "Dune.2021.1080p.WEB-DL.es-MX", "Dune.2021.1080p.spa_mx", "Dune.2021.1080p.Mexicano",
                 "Los.Simpson.S03E17.Homero.y.el.Bat.720p"):
        assert _langs(f"{name}\n💾 1 GB") == {"es-419": "name"}, name
    for name in ("Dune.2021.1080p [cast]", "Dune.2021.1080p.Esp-Cast", "Dune.2021.1080p.es_ES", "Dune 2021 1080p Español de España"):
        assert _langs(f"{name}\n💾 1 GB") == {"es-ES": "name"}, name
    assert _langs("Show.S01.Dual\nEpisódio 02 - Radioactive Man.avi\n💾 300 MB")["pt"] == "name"
    # Solo en lo técnico: en el título no son idiomas.
    assert _langs("Homero.2021.1080p\n💾 2 GB") == {"en": "assumed"}


def test_what_the_tv_had_to_change_is_already_in_its_tables():
    for u in RULES["unify"]:
        if u["changes"] != "tv":
            continue
        assert u["estado"].startswith("vigente")
        if u["rule"] == "flags":
            assert u["proposed"].items() <= RULES["flags"].items()
        elif u["rule"] == "words":
            assert [(r["pattern"], r["lang"]) for r in u["proposed"]] == [(r["pattern"], r["lang"]) for r in RULES["words"][-4:]]
        elif u["rule"] == "waits.per_addon_s":
            assert u["tv"] == u["proposed"] == RULES["waits"]["per_addon_s"] == streams.REQUEST_TIMEOUT == 10


def test_without_the_file_nothing_breaks(tmp_path):
    assert streams.load_rules(tmp_path / "no-existe.json") == {}
