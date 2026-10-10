from orbital.gamepad import BACK, GUIDE, START, ComboDetector


def run(detector, frames):
    """frames: [(segundos, botones)] -> eventos en orden."""
    return [e for t, b in frames for e in detector.update(b, t)]


def test_home_fires_once_per_press():
    d = ComboDetector()
    assert run(d, [(0, GUIDE), (0.1, GUIDE), (0.2, 0), (0.3, GUIDE)]) == ["home", "home"]


def test_hold_select_start_arms_then_completes_once():
    d = ComboDetector(arm=.25, total=1.5)
    both = BACK | START
    assert run(d, [(0, both), (0.2, both)]) == []  # un toque no hace nada
    assert run(d, [(0.3, both)]) == ["hold-start"]  # reacciona rápido (anillo en pantalla)
    assert run(d, [(1.0, both), (1.6, both), (2.5, both)]) == ["hold-complete"]  # una sola vez
    assert run(d, [(2.6, 0)]) == []  # soltar después de completar no cancela


def test_releasing_early_cancels():
    d = ComboDetector(arm=.25, total=1.5)
    both = BACK | START
    assert run(d, [(0, both), (0.5, both), (0.9, START)]) == ["hold-start", "hold-cancel"]
    assert run(d, [(1.0, both), (1.1, both)]) == []  # vuelve a empezar desde cero


def test_only_select_or_only_start_do_nothing():
    d = ComboDetector()
    assert run(d, [(0, BACK), (2, BACK), (3, START), (5, START)]) == []
