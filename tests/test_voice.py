import pytest

from orbital.voice import VoiceController, parse_text


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
    assert result.events == [{"type": "toast", "message": "Abriendo Hades.", "ok": True}]


def test_unknown_game(library):
    result = VoiceController(library).handle_intent("LaunchGameIntent", {"game": "tetris"})
    assert not result.ok and "tetris" in result.speech


def test_search_media(library):
    result = VoiceController(library).handle_intent("SearchMediaIntent", {"query": "El Padrino"})
    # Sin coincidencia exacta, la búsqueda de Orbital con el texto ya escrito (se elige con el mando).
    assert result.events == [{"type": "reload", "view": {"buscar": "El Padrino"}}]


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
