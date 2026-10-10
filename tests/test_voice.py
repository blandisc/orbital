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
    VoiceController(library).handle_intent("SearchMediaIntent", {"query": "El Padrino"})
    # Con Stremio instalado (config de prueba) el enlace va como argumento del ejecutable.
    assert library.launcher.ran[-1] == ["stremio-test", "stremio:///search?search=El%20Padrino"]


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
