"""La letra, los números, el movimiento y las palabras del reproductor contra el sistema base de diseño (24 nov 2026):
B4 (pocos tamaños), B5 (la negrita solo en lo grande), B7 (cifras del mismo ancho), B12 (reducir movimiento), V1 (los
botones dicen qué obtienes) y V5 (palabras de quien ve, no códigos)."""

import re
import sys

import pytest

from orbital import player_ui

_GRID = [
    {"label": "Latino", "flag": "mx", "cells": [
        {"id": 1, "label": "4K HDR", "hint": "Al instante", "size": "14.2 GB", "doubt": "", "current": False},
        {"id": 2, "label": "1080p", "hint": "Hay que bajarla", "size": "2.1 GB", "doubt": "Idioma dudoso", "current": True}]},
    {"label": "Castellano", "flag": "es", "cells": [
        {"id": 3, "label": "720p", "hint": "Al instante", "size": "", "doubt": "Idioma dudoso", "current": False}]},
]
_EPISODES = [{"id": f"e{i}", "label": f"E{i} · Episodio {i}", "season": 1, "current": i == 2} for i in range(1, 9)]


@pytest.fixture
def canvas_back():
    yield
    player_ui.set_canvas(1920, 1080)
    player_ui.set_text_size("normal")
    player_ui.set_input("gamepad")


def _every_layer() -> dict[str, str]:
    """Todas las capas del reproductor, en sus estados de siempre (para revisar la letra de todas a la vez)."""
    base = dict(title="Los Expedientes Secretos X", detail="T1 E1 · Piloto", position=3725, duration=7894, audio="Inglés",
                subtitles="Español", source="1080p · Torrentio", series=True, now="9:50 p. m.", next="E2", facts="1993 · ★ 8.6",
                description="Fox Mulder y Dana Scully investigan casos sin explicación. El FBI no les cree.", pip=True,
                chapters=[0, 600], chapter_titles=["Intro", "El bosque"])
    tracks = [{"type": "audio", "id": 1, "lang": "spa", "selected": True, "codec": "eac3", "audio-channels": 6},
              {"type": "sub", "id": 2, "lang": "eng", "selected": True}]
    trial = player_ui.SubTrial(language="Español", number=2, total=5, origin="addon", delay=-.5, status="Bajando el subtítulo…",
                               badge="Hecho para tu copia", release="The.X-Files.S01E01.720p", downloads=12400, languages=2)
    episodes = player_ui.more_panel(episodes=_EPISODES, sources=_GRID, iphone=True)
    sources = player_ui.more_panel(episodes=_EPISODES, sources=_GRID, iphone=True)
    sources.col = next(i for i, c in enumerate(sources.columns) if c.key == "source")
    playback = player_ui.more_panel(sources=_GRID, iphone=True)
    playback.col = next(i for i, c in enumerate(playback.columns) if c.key == "playback")
    return {
        "barra": player_ui.hud_ass(player_ui.Hud(**base)),
        "pausa": player_ui.hud_ass(player_ui.Hud(**base, paused=True)),
        "adelantando": player_ui.hud_ass(player_ui.Hud(**base, seeking="+10 s")),
        "audio": player_ui.panel_ass(player_ui.tracks_panel(tracks, 1.0), muted=True),
        "episodios": player_ui.panel_ass(episodes),
        "versión": player_ui.panel_ass(sources),
        "reproducción": player_ui.panel_ass(playback),
        "siguiente": player_ui.upnext_ass("El bosque", "Siguiente episodio · T1 E2", seconds=8, progress=.6,
                                          actions=[("A", "Ver ahora"), ("B", "Ver créditos")], still=True),
        "sigues": player_ui.upnext_ass("¿Sigues viendo?", actions=[("A", "Seguir viendo"), ("B", "Mantén: salir")]),
        "saltar": player_ui.skip_ass("Saltar intro"),
        "aviso": player_ui.toast_ass("Subtítulos: Español"),
        "aviso largo": player_ui.toast_ass("No pude bajarlo · Prueba otra versión o vuelve a intentarlo en un rato"),
        "volumen": player_ui.volume_ass(150, touch=True),
        "salir": player_ui.quit_hold_ass(.4),
        "probar": player_ui.sub_trial_ass(trial),
        "canal": player_ui.live_hud_ass(player_ui.LiveHud(name="Canal 5", number=5, category="Noticias", quality="1080p", now="9:50")),
        "silencio": player_ui.muted_ass(),
    }


def _letters(monkeypatch) -> list[tuple[int, str, str]]:
    """(tamaño, grosor, texto) de cada texto que se pinta, salvo la letra de un glifo del mando (es parte del ícono)."""
    from orbital.player_ui import draw, hud, overlays, panels

    seen: list[tuple[int, str, str]] = []
    real = draw.text

    def spy(x, y, value, size, color=player_ui.TEXT, *, weight="regular", align=7, alpha="00"):
        if sys._getframe(1).f_code.co_name != "glyph":
            seen.append((size, weight, str(value)))
        return real(x, y, value, size, color, weight=weight, align=align, alpha=alpha)

    for module in (draw, hud, overlays, panels):
        monkeypatch.setattr(module, "text", spy)
    return seen


@pytest.mark.parametrize("size", ["normal", "xlarge"])
@pytest.mark.parametrize("canvas", [(1920, 1080), (2560, 1600), (1440, 1080)])
@pytest.mark.parametrize("mode", ["gamepad", "keyboard", "touch"])
def test_the_player_uses_only_the_type_scale(mode, canvas, size, monkeypatch, canvas_back):
    """TB-04 (B4): cuatro tamaños de interfaz (21 · 26 · 32 · 40, con saltos de 1,2× o más) y dos grandes (52 · 64), los de
    `canvas.TYPE_SCALE`; antes eran catorce (19, 20, 21, 22, 24, 26, 28, 30, 34, 36, 44, 52, 56, 64) y la cuadrícula de
    Versión achicaba de uno en uno hasta 16. TB-06 (B5): la negrita solo en los grandes (antes también los botones de 24 de
    «Saltar intro», los títulos de 28 y 30 y la ✓)."""
    player_ui.set_input(mode)
    player_ui.set_canvas(*canvas)
    player_ui.set_text_size(size)
    seen = _letters(monkeypatch)
    _every_layer()
    sizes = sorted({s for s, _, _ in seen})
    assert set(sizes) <= set(player_ui.TYPE_SCALE), sizes
    interface = [s for s in player_ui.TYPE_SCALE if s not in player_ui.TYPE_BOLD]
    assert len(interface) <= 4 and len(player_ui.TYPE_BOLD) <= 2
    assert all(b / a >= 1.2 for a, b in zip(interface, interface[1:], strict=False))
    assert min(player_ui.TYPE_SCALE) >= 12
    bold = {(s, value) for s, weight, value in seen if weight == "bold"}
    assert bold and all(s in player_ui.TYPE_BOLD for s, _ in bold), bold
    assert {weight for _, weight, _ in seen} <= {"regular", "semi", "bold"}


def test_the_player_scale_is_the_interface_scale():
    """Los mismos números que la interfaz (≈ 21 · 26 · 32 · 40 a 1080p): en el reproductor se escriben «como en CSS»."""
    assert player_ui.TYPE_SCALE[:4] == (21, 26, 32, 40)


def test_numbers_that_change_use_tabular_figures(monkeypatch):
    """TB-08 (B7): libass no pide cifras tabulares y Segoe UI Semibold las trae proporcionales (su «1» es angosto): el tiempo
    bailaba con cada segundo. Lo que cambia (el tiempo, la hora, la cuenta atrás, el volumen, la sincronía) va en `figures`:
    Segoe UI normal, cuyas cifras miden lo mismo."""
    seen = _letters(monkeypatch)
    _every_layer()
    changing = {"1:02:05", "−1:09:29", "9:50 p. m.", "8", "150", "Sincronía: 0,5 s antes"}
    drawn = {value: weight for _, weight, value in seen if value in changing}
    assert set(drawn) == changing, drawn
    assert all(weight == "regular" for weight in drawn.values()), drawn


@pytest.mark.parametrize("reduce", [False, True])
def test_cards_only_fade_in_with_reduce_motion(reduce, monkeypatch):
    """TB-20 (B12): con «Reducir movimiento» (Ajustes o el de Windows) las tarjetas entran solo con un fundido; sin él, además
    suben CARD_RISE."""
    monkeypatch.setattr(player_ui.canvas, "REDUCE_MOTION", reduce)

    def top(ass: str) -> float:  # la orilla de arriba de la tarjeta (su primera figura)
        return float(re.search(r"\\p1}m [\d.]+ ([\d.]+)", ass).group(1))

    cards = (lambda a: player_ui.upnext_ass("¿Sigues viendo?", "T1 E2", appear=a),
             lambda a: player_ui.skip_ass("Saltar intro", appear=a))
    for card in cards:
        rise = top(card(0.0)) - top(card(1.0))
        assert rise == pytest.approx(0 if reduce else player_ui.CARD_RISE, abs=1)
        assert card(0.0) != card(1.0)  # el fundido sigue: al empezar, más transparente


def test_reduce_motion_follows_orbital_or_windows(monkeypatch):
    monkeypatch.setattr(player_ui.canvas, "REDUCE_MOTION", False)
    monkeypatch.setattr(player_ui.canvas, "system_reduces_motion", lambda: False)
    assert player_ui.set_reduce_motion(True) and player_ui.REDUCE_MOTION
    assert player_ui.set_reduce_motion(False) and not player_ui.REDUCE_MOTION
    monkeypatch.setattr(player_ui.canvas, "system_reduces_motion", lambda: True)
    assert player_ui.set_reduce_motion(False) and player_ui.REDUCE_MOTION


def test_windows_motion_setting_is_read_without_failing():
    assert isinstance(player_ui.canvas.system_reduces_motion(), bool)


def test_languages_and_audio_speak_like_people():
    """TB-51 (V5): un idioma fuera de la tabla ya no sale en código («HEB», o «ENG» en mayúsculas): su nombre, el del idioma
    sin la región, o «Otro idioma»; sin idioma («und»), nada. El audio, con el nombre que se conoce (no «E-AC3») o nada."""
    assert [player_ui.language(c) for c in ("ENG", "heb", "pt-BR", "en-US", "fr_CA", "tha", "xyz", "und", "")] == [
        "Inglés", "Hebreo", "Portugués de Brasil", "Inglés", "Francés", "Tailandés", "Otro idioma", "", ""]
    names = [player_ui.track_label({"type": "audio", "id": 1, "lang": "eng", "audio-channels": 6, "codec": c})
             for c in ("eac3", "truehd", "ac3", "dts", "aac", "opus", "flac")]
    assert names == ["Inglés · 5.1 · Dolby Digital Plus", "Inglés · 5.1 · Dolby TrueHD", "Inglés · 5.1 · Dolby Digital",
                     "Inglés · 5.1 · DTS", "Inglés · 5.1 · AAC", "Inglés · 5.1", "Inglés · 5.1"]
    assert player_ui.track_label({"type": "audio", "id": 3, "lang": "und"}) == "Pista 3"


def test_button_words_say_what_you_get():
    """TB-45 y TB-47 (V1): ni «Continuar» ni «Siguiente ›» a secas en el reproductor (TB-46, «Quedarme en este», en
    test_player · test_one_trigger_tap_changes_episode_with_a_notice_and_b_cancels)."""
    paused = player_ui.paused_ass(player_ui.Hud(title="Dune", position=60, duration=600, paused=True))
    assert "Seguir viendo" in paused and "Continuar" not in paused
    pills = player_ui.try_pills(player_ui.SubTrial(language="Español", number=1, total=3))
    assert ("Siguiente subtítulo ›", "right") in pills
    assert not {label for label, _ in pills} & {"Siguiente ›", "Siguiente", "Continuar", "Cancelar"}
