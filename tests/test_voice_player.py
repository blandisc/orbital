"""Voz y reproductor de Orbital: pausa, adelantar, subtítulos, audio, siguiente episodio, nube."""

import importlib.util
import json
from pathlib import Path

import pytest

from orbital import alexa_setup
from orbital.library.models import LibraryItem
from orbital.voice import VoiceController, parse_text

ROOT = Path(__file__).parent.parent


@pytest.mark.parametrize("text, expected", [
    ("pausa", ("PauseIntent", {})),
    ("pon pausa", ("PauseIntent", {})),
    ("reanuda el video", ("ResumeIntent", {})),
    ("adelanta 5 minutos", ("SeekIntent", {"direction": "adelanta", "amount": "5", "unit": "minutos"})),
    ("regresa un minuto", ("SeekIntent", {"direction": "regresa", "unit": "minuto"})),
    ("pon subtitulos en español", ("SubtitlesIntent", {"language": "espanol"})),
    ("pon subtítulos", ("SubtitlesIntent", {})),
    ("quita los subtitulos", ("SubtitlesOffIntent", {})),
    ("cambia el audio a inglés", ("AudioLanguageIntent", {"language": "ingles"})),
    ("siguiente episodio", ("NextEpisodeIntent", {})),
    ("pon el siguiente capitulo", ("NextEpisodeIntent", {})),
    # Lo de antes sigue igual.
    ("regresa a la consola", ("OpenOrbitalIntent", {})),
    ("pon hades", ("LaunchGameIntent", {"game": "hades"})),
])
def test_player_phrases(text, expected):
    assert parse_text(text) == expected


class FakePlayer:
    def __init__(self, playing=True, tracks=("en",)):
        self.playing = playing
        self.tracks = tracks
        self.calls = []
        self.current = None

    def set_pause(self, paused): self.calls.append(("pause", paused))
    def seek(self, seconds): self.calls.append(("seek", seconds))
    def subtitles_off(self): self.calls.append(("subs", None))
    def add_subtitles(self, url, lang): self.calls.append(("add-subs", url, lang))

    def select_language(self, kind, lang):
        if lang in self.tracks:
            self.calls.append((kind, lang))
            return True
        return False


@pytest.fixture
def voice(library):
    library.player = FakePlayer()
    return VoiceController(library)


def test_nothing_playing(library):
    library.player = FakePlayer(playing=False)
    result = VoiceController(library).handle_intent("PauseIntent")
    assert not result.ok and "reproduciéndose" in result.speech


def test_pause_resume_and_seek(voice):
    assert voice.handle_intent("PauseIntent").speech == "En pausa."
    voice.handle_intent("ResumeIntent")
    # Alexa manda los valores canónicos de los tipos (forward/back, minutes/seconds).
    assert voice.handle_intent("SeekIntent", {"direction": "forward", "amount": "5", "unit": "minutes"}).speech \
        == "Adelantando 5 minutos."
    assert voice.handle_intent("SeekIntent", {"direction": "back", "unit": "minutes"}).speech == "Regresando 1 minuto."
    assert voice.handle_intent("SeekIntent", {"direction": "forward"}).speech == "Adelantando 30 segundos."
    assert voice.catalog.player.calls == [("pause", True), ("pause", False), ("seek", 300), ("seek", -60), ("seek", 30)]


def test_player_commands_dont_toast_over_the_video(voice):
    events = voice.handle_intent("PauseIntent").events
    assert events and all(e["type"] != "toast" for e in events)


def test_subtitles_and_audio(voice):
    assert voice.handle_intent("SubtitlesIntent", {"language": "en"}).speech == "Subtítulos en inglés."
    voice.handle_intent("SubtitlesOffIntent")
    assert voice.handle_intent("AudioLanguageIntent", {"language": "en"}).speech == "Audio en inglés."
    missing = voice.handle_intent("AudioLanguageIntent", {"language": "es"})
    assert not missing.ok and missing.speech == "Este video no trae audio en español."
    assert voice.catalog.player.calls == [("sub", "en"), ("subs", None), ("audio", "en")]


def test_subtitles_fall_back_to_addons(voice, monkeypatch):
    player = voice.catalog.player
    player.current = type("P", (), {"meta": {"kind": "movie", "video_id": "tt1"}})()
    monkeypatch.setattr(voice.catalog.credentials, "get", lambda key: "clave")
    monkeypatch.setattr(voice.catalog.streams, "subtitles", lambda auth, kind, vid, lang: [f"https://subs/{vid}.{lang}.srt"])
    assert voice.handle_intent("SubtitlesIntent", {"language": "es"}).speech == "Subtítulos en español."
    assert player.calls == [("add-subs", "https://subs/tt1.es.srt", "es")]


def test_next_episode(voice, monkeypatch):
    monkeypatch.setattr(voice.catalog, "play_next_episode", lambda: "T2 E4")
    assert voice.handle_intent("NextEpisodeIntent").speech == "Poniendo T2 E4."
    monkeypatch.setattr(voice.catalog, "play_next_episode", lambda: None)
    assert not voice.handle_intent("NextEpisodeIntent").ok


def test_play_next_episode_stops_and_plays_the_following(library, monkeypatch):
    from orbital.library import cinemeta

    meta = {"name": "The Office", "videos": [{"id": "s:2:3", "season": 2, "episode": 3},
                                             {"id": "s:2:4", "season": 2, "episode": 4}]}
    monkeypatch.setattr(cinemeta.Cinemeta, "meta", lambda self, kind, mid: meta)
    played, stopped = [], []

    class Player:
        playing = True
        current = type("P", (), {"meta": {"kind": "series", "meta_id": "s", "video_id": "s:2:3", "title": "The Office"}})()

        def stop(self): stopped.append(True)

    library.player = Player()
    monkeypatch.setattr(library, "play_title", lambda *args: played.append(args))
    assert library.play_next_episode() == "T2 E4"
    assert stopped and played == [("series", "s", "s:2:4", "The Office · T2 E4")]


def test_voice_plays_movies_in_orbital_player(library, monkeypatch):
    played = []
    monkeypatch.setattr(library, "play_title", lambda *args: played.append(args))
    library.cinemeta.search = lambda kind, q: [{"id": "tt0816692", "name": "Interstellar"}] if kind == "movie" else []
    assert VoiceController(library).handle_text("quiero ver interstellar").speech == "Poniendo Interstellar."
    assert played == [("movie", "tt0816692", "tt0816692", "Interstellar")]


def test_open_game_in_the_cloud(library, monkeypatch):
    gfn = LibraryItem(id="gfn:1", title="Fortnite", category="geforcenow", source="geforcenow",
                      argv=["GeForceNOWStreamer.exe", "--url-route=#?cmsId=1"])
    monkeypatch.setattr(library, "items", lambda: [gfn])
    launched = []
    monkeypatch.setattr(library, "launch", lambda item_id, runner=None: launched.append(item_id))
    voice = VoiceController(library)
    assert voice.handle_text("abre fortnite en la nube").speech == "Abriendo Fortnite en GeForce NOW."
    assert voice.handle_text("abre fortnite en geforce now").ok and launched == ["gfn:1", "gfn:1"]
    assert not voice.handle_text("abre hades en la nube").ok


# --- skill alojada por Amazon -----------------------------------------------------------------
def test_skill_reads_orbital_json(tmp_path, monkeypatch):
    for var in ("ORBITAL_URL", "ORBITAL_TOKEN", "ALEXA_SKILL_ID"):
        monkeypatch.delenv(var, raising=False)
    files = alexa_setup.skill_files("https://legion.tail.ts.net/", "secreto", "amzn1.ask.skill.mia")
    alexa_setup.write_skill(tmp_path, files)
    spec = importlib.util.spec_from_file_location("hosted_skill", tmp_path / "lambda_function.py")
    skill = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(skill)
    assert (skill.ORBITAL_URL, skill.ORBITAL_TOKEN, skill.ALEXA_SKILL_ID) == \
        ("https://legion.tail.ts.net", "secreto", "amzn1.ask.skill.mia")
    assert json.loads((tmp_path / "interaction_model.es-MX.json").read_text(encoding="utf-8"))


def test_skill_without_tunnel_says_not_configured(tmp_path, monkeypatch):
    for var in ("ORBITAL_URL", "ORBITAL_TOKEN", "ALEXA_SKILL_ID"):
        monkeypatch.delenv(var, raising=False)
    alexa_setup.write_skill(tmp_path, alexa_setup.skill_files(None, "secreto"))
    spec = importlib.util.spec_from_file_location("hosted_skill2", tmp_path / "lambda_function.py")
    skill = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(skill)
    out = skill.lambda_handler({"request": {"type": "IntentRequest", "intent": {"name": "PauseIntent"}}})
    assert "no está configurada" in out["response"]["outputSpeech"]["text"]


def test_skill_maps_built_in_pause(monkeypatch):
    import io

    monkeypatch.setenv("ORBITAL_URL", "https://x")
    monkeypatch.setenv("ORBITAL_TOKEN", "t")
    monkeypatch.delenv("ALEXA_SKILL_ID", raising=False)
    spec = importlib.util.spec_from_file_location("hosted_skill3", ROOT / "alexa" / "lambda_function.py")
    skill = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(skill)
    sent = []
    monkeypatch.setattr(skill.urllib.request, "urlopen",
                        lambda req, timeout: sent.append(json.loads(req.data)) or io.BytesIO(b'{"ok": true, "speech": "En pausa."}'))
    skill.lambda_handler({"request": {"type": "IntentRequest", "intent": {"name": "AMAZON.PauseIntent"}}})
    assert sent == [{"intent": "PauseIntent", "slots": {}}]


def test_read_token_never_writes(tmp_path):
    cfg = tmp_path / "config.yaml"
    assert alexa_setup.read_token(cfg) is None and not cfg.exists()
    cfg.write_text('server:\n  token: "CAMBIA-ESTE-TOKEN"\n', encoding="utf-8")
    assert alexa_setup.read_token(cfg) is None
    cfg.write_text('server:\n  token: "abc"\n', encoding="utf-8")
    assert alexa_setup.read_token(cfg) == "abc"
