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


def test_gamesir_closes_with_lb_rb_select_and_its_own_combos_never_do():
    """Home + Start + Select chocaba con el GameSir: Start + Select le cambian el modo, Home + Start le reinician los
    ajustes y, desde la actualización de Windows del 2026-10-18, mantener Home abre la Vista de tareas."""
    from orbital.gamepad import CLOSE_LABELS, GAMESIR_CLOSE_COMBO, LB_BUTTON, RB_BUTTON, close_combo_for
    assert close_combo_for(0x3537) == GAMESIR_CLOSE_COMBO == LB_BUTTON | RB_BUTTON | BACK
    assert CLOSE_LABELS[GAMESIR_CLOSE_COMBO] == "LB + RB + Select"
    d = ComboDetector(arm=.25, total=1.5, combo=GAMESIR_CLOSE_COMBO)
    assert run(d, [(0, GUIDE | BACK | START), (2, GUIDE | BACK | START), (2.1, 0)]) == []  # el atajo viejo ya no
    assert run(d, [(3, BACK | START), (6, BACK | START), (6.1, 0)]) == []  # cambiar de modo
    assert run(d, [(7, LB_BUTTON | RB_BUTTON | BACK), (7.3, LB_BUTTON | RB_BUTTON | BACK),
                   (8.6, LB_BUTTON | RB_BUTTON | BACK)]) == ["hold-start", "hold-complete"]


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



def test_legion_go_controllers_close_with_start_select():
    from orbital.gamepad import LEGION_CLOSE_COMBO, close_combo_for
    assert close_combo_for(0x17EF) == LEGION_CLOSE_COMBO  # controles de la Legion Go
    assert close_combo_for(0x045E) == BACK | START | GUIDE  # los demás: los tres
    assert close_combo_for(None) == BACK | START | GUIDE
    d = ComboDetector(arm=.25, total=1.5, combo=LEGION_CLOSE_COMBO)
    assert run(d, [(0, BACK | START), (0.3, BACK | START), (1.6, BACK | START)]) == ["hold-start", "hold-complete"]


def test_home_plus_lb_opens_the_quick_panel_and_home_plus_rb_captures():
    from orbital.gamepad import GUIDE, LB_BUTTON, RB_BUTTON, ComboDetector

    d = ComboDetector()
    assert d.update(GUIDE, 0) == []
    assert d.update(GUIDE | LB_BUTTON, .1) == ["quick"]
    assert d.update(GUIDE | LB_BUTTON, .2) == []  # mantener LB no repite
    assert d.update(GUIDE, .3) == []
    assert d.update(GUIDE | RB_BUTTON, .4) == ["capture"]
    assert d.update(0, .5) == []  # soltar Home tras el acorde: no es "ir a Orbital"


def test_others_are_the_joysticks_xinput_does_not_read():
    from orbital.gamepad import others
    legion, ds4, xbox = (0x17EF, 0x61EB), (0x054C, 0x05C4), (0x045E, 0x028E)
    assert others([legion], [legion]) == []
    assert others([legion, ds4], [legion]) == [ds4]
    assert others([xbox, xbox], [xbox]) == [xbox]  # dos iguales, uno sin XInput (p. ej. en modo DInput)
    assert others([], [legion]) == []


def test_watcher_wakes_the_ui_once_when_a_controller_it_cannot_read_shows_up():
    from orbital.gamepad import GamepadWatcher
    woke = []
    w = GamepadWatcher(lambda event: None)
    w._joysticks = lambda: [(0x054C, 0x05C4)]
    w.on_others = lambda: woke.append(1)
    w._check_others(100.0)
    assert woke == []  # la interfaz lee el mando ella misma: no se busca nada
    w.watch_others = True
    w._check_others(100.0)
    assert woke == [1] and w.watch_others is False  # una vez; la interfaz vuelve a decir si suelta
    w.watch_others = True
    w._check_others(101.0)
    assert woke == [1]  # cada OTHERS_EVERY, no en cada vuelta
    w._check_others(100.0 + w.OTHERS_EVERY)
    assert woke == [1, 1]


def test_watcher_without_other_controllers_never_wakes_the_ui():
    from orbital.gamepad import GamepadWatcher
    woke = []
    w = GamepadWatcher(lambda event: None)
    w._joysticks = lambda: [(0x17EF, 0x61EB)]
    w.devices = {0: (0x17EF, 0x61EB)}
    w.on_others = lambda: woke.append(1)
    w.watch_others = True
    w._check_others(50.0)
    assert woke == [] and w.watch_others is True
