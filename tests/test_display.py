"""Resolución al jugar: ~1080p con la misma forma de la pantalla; las películas y Orbital, a la de siempre."""

from orbital import display

TV = {(3840, 2160, 60), (3840, 2160, 30), (2560, 1440, 60), (1920, 1080, 60), (1920, 1080, 120), (1280, 720, 60),
      (1920, 1200, 60)}
LEGION = {(2560, 1600, 144), (2560, 1600, 60), (1920, 1200, 144), (1920, 1200, 60), (1920, 1080, 144), (1280, 800, 144)}


def test_the_tv_at_4k_plays_at_1080p_with_its_refresh():
    assert display.game_mode_for((3840, 2160, 60), TV) == (1920, 1080, 60)
    assert display.game_mode_for((3840, 2160, 120), TV | {(3840, 2160, 120)}) == (1920, 1080, 120)


def test_the_legion_screen_keeps_its_shape_instead_of_stretching_to_16_9():
    assert display.game_mode_for((2560, 1600, 144), LEGION) == (1920, 1200, 144)


def test_a_screen_already_small_is_left_alone():
    assert display.game_mode_for((1920, 1080, 60), TV) is None
    assert display.game_mode_for((3840, 2160, 60), {(3840, 2160, 60)}) is None  # nada con su forma: no se toca


def test_lowers_once_and_restores_once():
    applied = []
    res = display.GameResolution(read=lambda: (3840, 2160, 60), modes=lambda: TV, apply=lambda m: applied.append(m) or True)
    assert res.for_game() and not res.for_game()  # dos juegos seguidos: un solo cambio
    assert res.restore() and not res.restore()
    assert applied == [(1920, 1080, 60), None]  # None: la de siempre (la que Windows tiene guardada)


def test_if_windows_refuses_nothing_is_remembered():
    res = display.GameResolution(read=lambda: (3840, 2160, 60), modes=lambda: TV, apply=lambda m: False)
    assert not res.for_game() and res.lowered is None and not res.restore()
