import pytest

from orbital.voice import VoiceController, VoiceResult, parse_text


@pytest.mark.parametrize("text,expected", [
    ("Abre Hollow Knight", ("LaunchGameIntent", {"game": "hollow knight"})),
    ("busca Interstellar en Stremio", ("SearchMediaIntent", {"query": "interstellar"})),
    ("abre stremio", ("OpenStremioIntent", {})),
    ("abre Steam", ("OpenSteamIntent", {})),
    ("cierra el juego", ("CloseGameIntent", {})),
    ("ve a la derecha", ("NavigateIntent", {"direction": "derecha"})),
    ("hola", None),
])
def test_parse_text(text, expected):
    assert parse_text(text) == expected


def test_launch_by_voice(library):
    voice = VoiceController(library)
    result = voice.handle_text("juega hades")
    assert result.ok and result.speech == "Abriendo Hades."
    assert library.launcher.opened[-1] == "steam://rungameid/1145360"
    assert result.events == [{"type": "toast", "message": "Abriendo Hades.", "ok": True, "voice": True}]


def test_unknown_game(library):
    result = VoiceController(library).handle_intent("LaunchGameIntent", {"game": "tetris"})
    assert not result.ok and "tetris" in result.speech


def test_search_media(library):
    result = VoiceController(library).handle_intent("SearchMediaIntent", {"query": "El Padrino"})
    # Sin coincidencia exacta, la búsqueda de Orbital con el texto ya escrito (se elige con el mando).
    assert result.events == [{"type": "open-view", "view": {"buscar": "El Padrino"}, "message": "Buscando «El Padrino»"}]


def test_close_only_managed_processes(library):
    voice = VoiceController(library)
    voice.handle_intent("LaunchGameIntent", {"game": "hades"})
    assert not voice.handle_intent("CloseGameIntent").ok  # lo maneja Steam
    voice.handle_intent("LaunchGameIntent", {"game": "chrono trigger"})
    assert voice.handle_intent("CloseGameIntent").speech == "Cerré Chrono Trigger."


def test_navigate_emits_event(library):
    result = VoiceController(library).handle_intent("NavigateIntent", {"direction": "izquierda"})
    assert result.events == [{"type": "navigate", "direction": "left"}]


def test_unknown_intent(library):
    assert not VoiceController(library).handle_intent("MakeCoffeeIntent").ok


def test_natural_watch_phrases():
    from orbital.voice import parse_text

    assert parse_text("quiero ver dune") == ("SearchMediaIntent", {"query": "dune"})
    assert parse_text("reproduce the office") == ("SearchMediaIntent", {"query": "the office"})
    assert parse_text("sigue viendo")[0] == "ContinueWatchingIntent"  # no se confunde


@pytest.mark.parametrize("text, expected", [
    ("cuánto le falta", ("TimeLeftIntent", {})),
    ("toma una captura", ("CaptureIntent", {})),
    ("sube el volumen", ("VolumeIntent", {"volume": "sube"})),
    ("bájale volumen", ("VolumeIntent", {"volume": "bajale"})),
    ("pon el volumen en 40", ("VolumeIntent", {"level": "40"})),
])
def test_new_phrases(text, expected):
    assert parse_text(text) == expected


def test_volume_by_voice(library, monkeypatch):
    from orbital import quick

    state = {"level": 50, "muted": True}
    monkeypatch.setattr(quick, "volume", lambda: dict(state))
    monkeypatch.setattr(quick, "set_volume", lambda level=None, muted=None: state.update(level=level, muted=muted) or dict(state))
    voice = VoiceController(library)
    assert voice.handle_text("sube el volumen").speech == "Volumen en 60 por ciento." and state["muted"] is False
    assert voice.handle_intent("VolumeIntent", {"volume": "down"}).speech == "Volumen en 50 por ciento."
    assert voice.handle_text("pon el volumen en 120").speech == "Volumen en 100 por ciento."


def test_time_left_needs_something_playing(library):
    assert not VoiceController(library).handle_text("cuánto le falta").ok


def test_what_people_say_after_a_courtesy_is_understood():
    """«Alexa, pídele a Orbital que por favor…», «quiero que abras…», «¿puedes subir el volumen?»: el subjuntivo de tú y los
    infinitivos después de una cortesía no se entendían (sí «ponga»), y Alexa los manda tal cual por el texto libre."""
    from orbital.voice import parse_text

    cases = {
        "quiero que abras hades": ("LaunchGameIntent", {"game": "hades"}),
        "necesito que pongas algo de terror": ("RecommendIntent", {"genre": "terror"}),
        "me puedes subir el volumen": ("VolumeIntent", {"volume": "sube"}),
        "podrias bajar el volumen": ("VolumeIntent", {"volume": "baja"}),
        "puedes pausar": ("PauseIntent", {}),
        "puedes quitar los subtitulos": ("SubtitlesOffIntent", {}),
        "adelantar cinco minutos": ("SeekIntent", {"seek": "adelanta", "amount": "5", "unit": "minutos"}),
        "quiero que cierres el juego": ("CloseGameIntent", {}),
        "ve al inicio": ("NavigateIntent", {"direction": "inicio"}),
        "regresa al inicio": ("NavigateIntent", {"direction": "inicio"}),
        "pidele a orbital que pongas the office temporada 2 episodio 3":
            ("WatchEpisodeIntent", {"series": "the office", "season": "2", "episode": "3"}),
    }
    for said, expected in cases.items():
        assert parse_text(said) == expected, said


# «Alexa, pausa en Orbital»: Alexa deja el nombre de la skill pegado (a veces junto: «norbital»). Así llegaba al registro
# («continúa viendo la película norbital») y nada coincidía.
@pytest.mark.parametrize("text, expected", [
    ("pausa en orbital", ("PauseIntent", {})),
    ("pausa norbital", ("PauseIntent", {})),
    ("sube el volumen con orbital", ("VolumeIntent", {"volume": "sube"})),
    ("pon dune n orbital", ("LaunchGameIntent", {"game": "dune"})),
    ("abre orbital", ("OpenOrbitalIntent", {})),  # el nombre a secas sigue siendo abrir la consola
])
def test_the_skill_name_stuck_to_the_phrase_is_dropped(text, expected):
    found = parse_text(text)
    assert found is not None and (found[0], {k: v for k, v in found[1].items() if k in expected[1]}) == expected


@pytest.mark.parametrize("value, expected", [
    ("Dune en Orbital", "Dune"), ("the office norbital", "the office"), ("Hades con Orbital.", "Hades"),
    ("viendo la película n orbital", "viendo la película"), ("Hades", "Hades"),
])
def test_alexa_slots_lose_the_skill_name(value, expected):
    from orbital.voice import slot_text

    assert slot_text(value) == expected


def test_a_slot_with_the_skill_name_still_finds_the_game(library):
    result = VoiceController(library).handle_intent("LaunchGameIntent", {"game": "hades norbital"})
    assert result.ok and result.speech == "Abriendo Hades."


def test_continue_watching_the_movie_is_just_continue(library, monkeypatch):
    voice = VoiceController(library)
    seen = []
    monkeypatch.setattr(voice, "_resume_intent", lambda slots: seen.append(slots) or VoiceResult("Sigue."))
    monkeypatch.setattr(type(library.player), "playing", property(lambda self: True), raising=False)
    assert voice.handle_intent("ContinueWatchingIntent", {"show": "viendo la película norbital"}).speech == "Sigue."
    assert seen == [{}]


def test_what_alexa_did_not_understand_is_reported(library):
    result = VoiceController(library).handle_intent("FallbackIntent")
    assert not result.ok and result.speech.startswith("No entendí")


def _siri_commands() -> list[str]:
    import re
    from pathlib import Path

    swift = (Path(__file__).resolve().parent.parent / "ios/App/Sources/Platform/OrbitalIntents.swift").read_text(encoding="utf-8")
    body = swift[swift.index("var said: String"):]
    return re.findall(r'case \.\w+: "([^"]+)"', body[:body.index("\n    }\n}")])


def test_siri_quick_commands_are_all_listed():
    assert len(_siri_commands()) >= 20


@pytest.mark.parametrize("said", _siri_commands())
def test_every_siri_quick_command_reaches_a_command(said):
    """«Oye Siri, pausa en Orbital»: lo que `OrbitalCommand` le dice a la consola, ella lo entiende."""
    assert parse_text(said) is not None, f"«{said}» no llega a ningún comando"
