from orbital.gamepad import BACK, GUIDE, START, ComboDetector


def run(detector, frames):
    """frames: [(segundos, botones)] -> eventos en orden."""
    return [e for t, b in frames for e in detector.update(b, t)]


def test_home_fires_on_release_once_per_press():
    d = ComboDetector()
    assert run(d, [(0, GUIDE), (0.1, GUIDE)]) == []  # aún presionado
    assert run(d, [(0.2, 0), (0.3, GUIDE), (0.4, 0)]) == ["home", "home"]


def test_home_chords_belong_to_the_emulator():
    # Home+X (Eden: modo dock), Home+B (pantalla completa)... no mueven a Orbital.
    d = ComboDetector()
    X = 0x4000
    assert run(d, [(0, GUIDE), (0.1, GUIDE | X), (0.2, GUIDE), (0.3, 0)]) == []
    assert run(d, [(0.5, GUIDE), (0.6, 0)]) == ["home"]  # el siguiente Home solo sí


def test_hold_start_select_home_arms_then_completes_once():
    d = ComboDetector(arm=.25, total=1.5)
    both = BACK | START | GUIDE
    assert run(d, [(0, both), (0.2, both)]) == []  # un toque no hace nada
    assert run(d, [(0.3, both)]) == ["hold-start"]  # reacciona rápido (anillo en pantalla)
    assert run(d, [(1.0, both), (1.6, both), (2.5, both)]) == ["hold-complete"]  # una sola vez
    assert run(d, [(2.6, 0)]) == []  # soltar después de completar no cancela


def test_releasing_early_cancels():
    d = ComboDetector(arm=.25, total=1.5)
    both = BACK | START | GUIDE
    assert run(d, [(0, both), (0.5, both), (0.9, START | GUIDE)]) == ["hold-start", "hold-cancel"]
    assert run(d, [(1.0, both), (1.1, both)]) == []  # vuelve a empezar desde cero


def test_only_select_or_only_start_do_nothing():
    d = ComboDetector()
    assert run(d, [(0, BACK), (2, BACK), (3, START), (5, START)]) == []


def test_gamesir_mode_switch_never_closes_the_game():
    # El GameSir cambia de modo con Start+Select sostenidos, o con Home sostenido: nada de eso cierra.
    d = ComboDetector()
    assert run(d, [(0, BACK | START), (3, BACK | START), (4, 0)]) == []
    assert run(d, [(5, GUIDE), (8, GUIDE)]) == []
    assert run(d, [(8.5, 0)]) == ["home"]  # soltar Home solo = ir a Orbital (como siempre)
    assert run(d, [(9, GUIDE | START), (9.1, GUIDE | START | BACK), (9.2, 0)]) == []  # combo: Home no cuenta


def test_remote_maps_buttons_to_keys_with_repeat_on_dpad():
    from orbital.gamepad import A_BUTTON, DPAD_RIGHT, VK_RIGHT, VK_SPACE, KeyRemote

    r = KeyRemote(delay=.35, rate=.1)
    assert r.update(A_BUTTON, 0) == [VK_SPACE]
    assert r.update(A_BUTTON, 1) == []  # A no se repite
    assert r.update(DPAD_RIGHT, 2) == [VK_RIGHT]
    assert r.update(DPAD_RIGHT, 2.2) == []
    assert r.update(DPAD_RIGHT, 2.4) == [VK_RIGHT]  # mantener: sigue adelantando
    assert r.update(DPAD_RIGHT, 2.51) == [VK_RIGHT]


def test_remote_ignores_orbital_shortcuts():
    from orbital.gamepad import A_BUTTON, KeyRemote

    r = KeyRemote()
    assert r.update(GUIDE | A_BUTTON, 0) == []  # Home+algo: de Orbital o del emulador
    assert r.update(BACK | START, 1) == []  # Select+Start: cerrar
    assert r.update(A_BUTTON, 2) == [0x20]
