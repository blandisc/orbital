"""Frases como las dice la gente (Alexa, Siri «dile a Orbital que…», el micrófono del iPhone) → lo que se entiende.
Un banco que crece: cada frase que alguien diga y no se entienda, aquí."""

import pytest

from orbital.text import normalize
from orbital.voice import kind_hint, parse_text, tidy

BANK = [
    # Títulos, con muletillas de Siri y de la gente
    ("Pon El viaje de Chihiro", "LaunchGameIntent", {"game": "el viaje de chihiro"}),
    ("pon el viaje de chihiro por favor", "LaunchGameIntent", {"game": "el viaje de chihiro"}),
    ("Oye, pon Dune", "LaunchGameIntent", {"game": "dune"}),
    ("que ponga Dune", "LaunchGameIntent", {"game": "dune"}),
    ("dile a orbital que ponga dune", "LaunchGameIntent", {"game": "dune"}),
    ("pídele a orbital que ponga dune", "LaunchGameIntent", {"game": "dune"}),
    ("Orbital, pon Dune", "LaunchGameIntent", {"game": "dune"}),
    ("ponme Dune en la tele", "LaunchGameIntent", {"game": "dune"}),
    ("pon Dune en la televisión", "LaunchGameIntent", {"game": "dune"}),
    ("quiero ver Dune", "SearchMediaIntent", {"query": "dune"}),
    ("quisiera ver Dune", "SearchMediaIntent", {"query": "dune"}),
    ("me gustaría ver Dune", "SearchMediaIntent", {"query": "dune"}),
    ("vamos a ver Dune", "SearchMediaIntent", {"query": "dune"}),
    ("pon la película Dune", "LaunchGameIntent", {"game": "dune", "kind": "movie"}),
    ("pon la serie The Office", "LaunchGameIntent", {"game": "the office", "kind": "series"}),
    ("reproduce Dune", "SearchMediaIntent", {"query": "dune"}),
    ("pon Dune.", "LaunchGameIntent", {"game": "dune"}),
    ("Pon Toy Story 3", "LaunchGameIntent", {"game": "toy story 3"}),
    ("pon toy story tres", "LaunchGameIntent", {"game": "toy story tres"}),
    ("ponme algo", "RecommendIntent", {}),
    # Juegos
    ("abre Hollow Knight", "LaunchGameIntent", {"game": "hollow knight"}),
    ("quiero jugar Hollow Knight", "LaunchGameIntent", {"game": "hollow knight"}),
    ("vamos a jugar Hades", "LaunchGameIntent", {"game": "hades"}),
    ("juega Hades", "LaunchGameIntent", {"game": "hades"}),
    ("a jugar Hades", "LaunchGameIntent", {"game": "hades"}),
    ("abre Zelda con Ryujinx", "LaunchGameIntent", {"game": "zelda con ryujinx"}),
    ("cierra el juego", "CloseGameIntent", {}),
    ("ciérralo", "CloseGameIntent", {}),
    ("qué estoy jugando", "WhatsPlayingIntent", {}),
    ("¿Qué estoy jugando?", "WhatsPlayingIntent", {}),
    # Episodios
    ("pon Los Simpson temporada 5 episodio 3", "WatchEpisodeIntent", {"series": "los simpson", "season": "5", "episode": "3"}),
    ("pon los simpson temporada cinco episodio tres", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon los simpson temporada 5 capítulo 3", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon el capítulo 3 de la temporada 5 de los simpson", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon los simpson, quinta temporada, episodio tres", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon los simpson T5 E3", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon los simpson s05e03", "WatchEpisodeIntent", {"season": "5", "episode": "3"}),
    ("pon la temporada 2", "PlayEpisodeIntent", {"season": "2"}),
    ("pon la segunda temporada", "PlayEpisodeIntent", {"season": "2"}),
    ("pon el capítulo 5", "PlayEpisodeIntent", {"episode": "5"}),
    ("pon el quinto capítulo", "PlayEpisodeIntent", {"episode": "5"}),
    ("siguiente episodio", "NextEpisodeIntent", {}),
    ("el que sigue", "NextEpisodeIntent", {}),
    ("pon el siguiente capítulo", "NextEpisodeIntent", {}),
    ("episodio anterior", "PreviousEpisodeIntent", {}),
    ("sigue viendo The Office", "ContinueWatchingIntent", {"show": "the office"}),
    ("continúa The Office", "ContinueWatchingIntent", {"show": "the office"}),
    ("sigue viendo", "ContinueWatchingIntent", {}),
    # Reproductor
    ("pausa", "PauseIntent", {}),
    ("Pausa.", "PauseIntent", {}),
    ("ponle pausa", "PauseIntent", {}),
    ("detén el video", "PauseIntent", {}),
    ("para", "PauseIntent", {}),
    ("dale play", "ResumeIntent", {}),
    ("reanuda", "ResumeIntent", {}),
    ("continúa", "ResumeIntent", {}),
    ("adelanta cinco minutos", "SeekIntent", {"amount": "5"}),
    ("adelanta 30 segundos", "SeekIntent", {"amount": "30"}),
    ("regresa diez segundos", "SeekIntent", {"amount": "10"}),
    ("adelanta un minuto", "SeekIntent", {}),
    ("regrésale tantito", "SeekIntent", {"seek": "regresa"}),
    ("salta la intro", "SkipIntroIntent", {}),
    ("sáltate el resumen", "SkipIntroIntent", {}),
    ("pon subtítulos en español", "SubtitlesIntent", {"language": "espanol"}),
    ("subtítulos en inglés", "SubtitlesIntent", {"language": "ingles"}),
    ("quita los subtítulos", "SubtitlesOffIntent", {}),
    ("pon el audio en inglés", "AudioLanguageIntent", {"language": "ingles"}),
    ("ponlo en inglés", "AudioLanguageIntent", {"language": "ingles"}),
    ("cuánto le falta", "TimeLeftIntent", {}),
    ("cuánto falta para que acabe", "TimeLeftIntent", {}),
    ("cierra el video", "CloseGameIntent", {}),
    # Volumen y brillo
    ("sube el volumen", "VolumeIntent", {"volume": "sube"}),
    ("súbele", "VolumeIntent", {"volume": "sube"}),
    ("súbele tantito", "VolumeIntent", {"volume": "sube"}),
    ("más alto", "VolumeIntent", {"volume": "sube"}),
    ("más fuerte", "VolumeIntent", {"volume": "sube"}),
    ("más bajo", "VolumeIntent", {"volume": "baja"}),
    ("pon el volumen al 30", "VolumeIntent", {"level": "30"}),
    ("pon el volumen en treinta", "VolumeIntent", {"level": "30"}),
    ("volumen al 30", "VolumeIntent", {"level": "30"}),
    ("silencio", "MuteIntent", {}),
    ("cállate", "MuteIntent", {}),
    ("quita el silencio", "UnmuteIntent", {}),
    ("sube el brillo", "BrightnessIntent", {"brightness": "sube"}),
    # TV en vivo
    ("pon la tele", "LiveTvIntent", {}),
    ("pon el canal ADN 40", "LiveTvIntent", {"channel": "adn 40"}),
    ("pon Azteca Uno en vivo", "LiveTvIntent", {"channel": "azteca 1"}),
    ("siguiente canal", "ChannelStepIntent", {"step": "next"}),
    ("cambia de canal", "ChannelStepIntent", {"step": "next"}),
    # Navegación y Para ti
    ("ve a juegos", "NavigateIntent", {"direction": "juegos"}),
    ("ve a inicio", "NavigateIntent", {}),
    ("ve a Para ti", "NavigateIntent", {"direction": "para ti"}),
    ("ve atrás", "NavigateIntent", {"direction": "atras"}),
    ("regresa", None, None),
    ("qué sale hoy", "UpcomingIntent", {}),
    ("qué me recomiendas", "RecommendIntent", {}),
    ("recomiéndame algo", "RecommendIntent", {}),
    ("busca Dune", "SearchMediaIntent", {"query": "dune"}),
    ("toma una captura", "CaptureIntent", {}),
    ("sal al escritorio", "ExitToDesktopIntent", {}),
    ("abre Steam", "OpenSteamIntent", {}),
]


@pytest.mark.parametrize("phrase, intent, slots", BANK)
def test_how_people_say_it(phrase, intent, slots):
    got = parse_text(phrase)
    got_intent, got_slots = got if got else (None, {})
    assert got_intent == intent, (phrase, got)
    for key, value in (slots or {}).items():
        assert got_slots.get(key) == value, (phrase, got)


def test_tidy_drops_what_is_said_on_top():
    assert tidy(normalize("dile a orbital que ponga dune por favor")) == "ponga dune"
    assert tidy(normalize("ponme Dune en la tele por favor")) == "ponme dune"
    assert tidy(normalize("pon los simpson, quinta temporada, episodio tres")) == "pon los simpson temporada 5 episodio 3"


def test_kind_words_become_a_hint():
    assert kind_hint("la película Dune") == ("dune", "movie")
    assert kind_hint("la serie The Office") == ("the office", "series")
    assert kind_hint("el juego Hades") == ("hades", "game")
    assert kind_hint("Dune") == ("Dune", None)
