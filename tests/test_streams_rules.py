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


def test_without_the_file_nothing_breaks(tmp_path):
    assert streams.load_rules(tmp_path / "no-existe.json") == {}
