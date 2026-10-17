"""El corpus de frases compartido con el iPhone (tests/fixtures/voice/corpus.json): lo que llega a la consola debe
entenderse como dice. Las frases con «phone» las atiende el iPhone y se saltan aquí (VoiceRouterTests las prueba allá)."""

import json
from pathlib import Path

import pytest

from orbital.voice import parse_text

CORPUS = json.loads((Path(__file__).parent / "fixtures" / "voice" / "corpus.json").read_text(encoding="utf-8"))["phrases"]
CONSOLE = [p for p in CORPUS if not p.get("phone")]


@pytest.mark.parametrize("phrase", CONSOLE, ids=[p["text"] for p in CONSOLE])
def test_console_understands_the_shared_corpus(phrase):
    got = parse_text(phrase["text"])
    intent, slots = got if got else (None, {})
    assert intent == phrase.get("intent"), (phrase["text"], got)
    for key, value in (phrase.get("slots") or {}).items():
        assert str(slots.get(key)) == str(value), (phrase["text"], got)
