from orbital import supervisor


def test_closing_orbital_does_not_reopen_it():
    assert supervisor.decide(0, [], 100) == ("stop", 0.0)


def test_update_reopens_right_away():
    assert supervisor.decide(supervisor.RESTART, [], 100) == ("restart", 0.0)


def test_crash_reopens_with_growing_pauses_and_then_gives_up():
    crashes: list[float] = []
    waits = [supervisor.decide(1, crashes, 100 + i)[1] for i in range(supervisor.MAX_CRASHES)]
    assert waits == list(supervisor.BACKOFF[:supervisor.MAX_CRASHES])
    assert supervisor.decide(1, crashes, 110) == ("stop", 0.0)  # muchos seguidos: se rinde


def test_old_crashes_are_forgotten():
    crashes = [0.0, 1.0, 2.0, 3.0]
    assert supervisor.decide(1, crashes, supervisor.WINDOW + 10)[0] == "restart"
    assert len(crashes) == 1


def test_run_restarts_until_the_child_closes_normally():
    codes = iter([1, supervisor.RESTART, 0])
    seen, slept = [], []

    def spawn(cmd, env):
        seen.append((cmd[-1], env[supervisor.CHILD_ENV]))
        return next(codes)

    assert supervisor.run(["--ui", "browser"], spawn=spawn, sleep=slept.append, clock=lambda: 50.0) == 0
    assert seen == [("browser", "1")] * 3 and slept == [supervisor.BACKOFF[0], 0.0]


class Child:
    """Un Orbital de mentira: sigue vivo `alive` esperas y luego termina con `code`."""

    def __init__(self, alive=1000, code=0):
        self.alive, self.code, self.killed = alive, code, False

    def wait(self, timeout=None):
        if self.killed:
            return -9
        if self.alive <= 0:
            return self.code
        self.alive -= 1
        raise supervisor.subprocess.TimeoutExpired("orbital", timeout)

    def kill(self):
        self.killed = True


def clock_from(step=30.0):
    now = [0.0]

    def clock():
        now[0] += step
        return now[0]

    return clock


def test_a_hung_orbital_is_killed_after_three_missed_beats():
    child = Child()
    answers = iter([True] + [False] * 10)  # contestó una vez y luego se colgó
    code = supervisor.watch(child, lambda: next(answers), clock_from(), busy=lambda: False)
    assert code == supervisor.HUNG and child.killed
    assert supervisor.decide(code, [], 100)[0] == "restart"  # se reabre como un tropiezo más


def test_a_slow_start_is_not_a_hang():
    child = Child(alive=6, code=0)  # 6 latidos sin contestar (3 min) mientras escanea, y luego se cierra normal
    assert supervisor.watch(child, lambda: False, clock_from(), busy=lambda: False) == 0 and not child.killed


def test_never_restarts_while_updating():
    child = Child(alive=20, code=supervisor.RESTART)
    answers = iter([True] + [False] * 30)
    assert supervisor.watch(child, lambda: next(answers), clock_from(), busy=lambda: True) == supervisor.RESTART
    assert not child.killed


def test_a_sleeping_console_starts_counting_again():
    child = Child(alive=5, code=0)
    answers = iter([True, False, False, False, True])
    steps = iter([30, 30, 30, 30, 400, 30])  # entre el 3.er y el 4.º latido la consola durmió
    now = [0.0]

    def clock():
        now[0] += next(steps)
        return now[0]

    # sin el salto, el 4.º sería el tercer fallo seguido y lo mataría; con el salto se cuenta de nuevo
    assert supervisor.watch(child, lambda: next(answers), clock, busy=lambda: False) == 0 and not child.killed


def test_the_updating_flag_counts_only_while_fresh(tmp_path):
    flag = supervisor.updating_flag()
    assert not supervisor.updating()
    flag.parent.mkdir(parents=True, exist_ok=True)
    flag.write_text("x")
    assert supervisor.updating() and not supervisor.updating(now=flag.stat().st_mtime + supervisor.UPDATING_STALE + 1)


def test_the_probe_reads_a_real_health_answer():
    import http.server
    import threading

    class Ok(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200 if self.path == "/api/health" else 404)
            self.end_headers()

        def log_message(self, *a):
            pass

    httpd = http.server.HTTPServer(("127.0.0.1", 0), Ok)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        assert supervisor.health_probe(httpd.server_address[1])()
    finally:
        httpd.shutdown()
        httpd.server_close()
    assert not supervisor.health_probe(httpd.server_address[1], timeout=.5)()  # ya no hay nadie


# --------------------------------------------------- nunca le quita la pantalla a un juego o a un video
def test_a_hang_is_tolerated_for_six_beats_not_three():
    child = Child()
    answers = iter([True] + [False] * 5 + [True] + [False] * 20)  # un pico de 5 latidos (2,5 min) no basta
    seen = []

    def probe():
        seen.append(1)
        return next(answers)

    assert supervisor.watch(child, probe, clock_from(), busy=lambda: False) == supervisor.HUNG
    assert len(seen) == 1 + 5 + 1 + supervisor.HEARTBEAT_MISSES == 13 and supervisor.HEARTBEAT_MISSES == 6


def test_never_kills_while_a_game_or_video_is_open():
    child = Child(alive=40, code=0)
    answers = iter([True] + [False] * 60)
    reasons = []

    def away():
        reasons.append("Mario Kart sigue abierto")
        return reasons[-1]

    assert supervisor.watch(child, lambda: next(answers), clock_from(), busy=lambda: False, away=away) == 0
    assert not child.killed and len(reasons) > supervisor.HEARTBEAT_MISSES


def test_waits_for_you_to_come_back_and_then_counts_from_zero():
    child = Child()
    answers = iter([True] + [False] * 40)
    away = iter(["hay otra ventana al frente"] * 10 + [""] * 40)  # 10 latidos en el juego y luego regresas
    asked = []

    def probe():
        asked.append(1)
        return next(answers)

    assert supervisor.watch(child, probe, clock_from(), busy=lambda: False, away=lambda: next(away)) == supervisor.HUNG
    assert child.killed and len(asked) == 1 + 10 + supervisor.HEARTBEAT_MISSES  # los del juego no contaron


def test_a_fresh_answer_ends_the_wait_without_killing():
    child = Child(alive=8, code=0)
    answers = iter([True, False, False, True, True, True, True, True, True])
    assert supervisor.watch(child, lambda: next(answers), clock_from(), busy=lambda: False,
                            away=lambda: "Video sigue abierto") == 0 and not child.killed


def test_the_busy_mark_counts_only_while_its_processes_live(tmp_path):
    mark = tmp_path / "busy.json"
    assert supervisor.game_open(mark, table={}) == ""  # sin marca
    supervisor.write_busy({"title": "Zelda", "pids": {"40": "eden.exe"}, "exe": ""}, mark)
    assert supervisor.game_open(mark, table={40: ("eden.exe", 1)}) == "Zelda"
    assert supervisor.game_open(mark, table={40: ("notepad.exe", 1)}) == ""  # Windows reusó el pid: ya no es el juego
    assert supervisor.game_open(mark, table={}) == ""  # cerraste el juego con Orbital colgado: la marca ya no cuenta
    supervisor.write_busy({"title": "Stremio", "pids": {}, "exe": "stremio.exe"}, mark)
    stremio_in_front = lambda: {"pid": 7, "exe": "stremio.exe", "fullscreen": True, "orbital": False, "idle": 0}  # noqa: E731
    assert supervisor.game_open(mark, table={7: ("stremio.exe", 1)}, front=stremio_in_front) == "Stremio"
    mark.write_text("{roto")
    assert supervisor.game_open(mark, table={}) == ""
    supervisor.write_busy(None, mark)
    assert not mark.exists()
    supervisor.write_busy(None, mark)  # quitar una marca que no existe no falla


def test_the_busy_mark_off_windows_asks_the_process_itself(tmp_path):
    import os
    import sys
    if sys.platform == "win32":
        return  # en Windows os.kill(pid, 0) cerraría el proceso: allá se usa la foto de procesos
    mark = tmp_path / "busy.json"
    supervisor.write_busy({"title": "Video", "pids": {str(os.getpid()): ""}}, mark)
    assert supervisor.game_open(mark, table=None) == "Video"


class Win:
    def __init__(self, fg=10, pid=500, title="Orbital", exe="msedge.exe", tree=(1, 500)):
        self.fg, self.pid, self._title, self.exe, self.tree = fg, pid, title, exe, set(tree)

    def foreground(self):
        return self.fg

    def pid_of(self, hwnd):
        return self.pid

    def process_tree(self, root):
        return self.tree

    def title(self, hwnd):
        return self._title

    def exe_name(self, pid):
        return self.exe


def test_orbital_in_front_knows_its_own_window():
    assert supervisor.orbital_in_front(1, Win()) is True  # su Edge, hijo del servidor
    assert supervisor.orbital_in_front(1, Win(tree=(1,), title="Orbital — Inicio")) is True  # Edge abierto por ti
    assert supervisor.orbital_in_front(1, Win(tree=(1,), title="Mario Kart 8", exe="ryujinx.exe")) is False
    assert supervisor.orbital_in_front(1, Win(fg=0)) is None  # nada al frente: no se sabe


def test_away_reason_puts_the_game_first_then_the_window():
    assert supervisor.away_reason(1, game=lambda: "Halo", front=lambda pid: True) == "Halo sigue abierto"
    assert supervisor.away_reason(1, game=lambda: "", front=lambda pid: False) == "hay otra ventana al frente"
    assert supervisor.away_reason(1, game=lambda: "", front=lambda pid: True) == ""
    assert supervisor.away_reason(1, game=lambda: "", front=lambda pid: None) == ""  # fuera de Windows: solo la marca


def test_off_windows_the_front_window_is_unknown():
    import sys
    if sys.platform != "win32":
        assert supervisor.orbital_in_front(1) is None


def test_after_a_crash_it_does_not_reopen_over_an_open_game():
    codes = iter([1, 0])
    open_for = iter(["Halo", "Halo", ""])
    slept = []
    assert supervisor.run(["--ui", "browser"], spawn=lambda cmd, env: next(codes), sleep=slept.append,
                          clock=lambda: 50.0, game=lambda: next(open_for)) == 0
    assert slept == [supervisor.BACKOFF[0], supervisor.HOLD_EVERY, supervisor.HOLD_EVERY]


def test_the_launcher_writes_and_clears_the_mark(tmp_path):
    import subprocess
    import sys

    from orbital.launcher import Launcher, Running
    mark = tmp_path / "busy.json"
    mark.write_text('{"title": "de un Orbital anterior"}')
    launcher = Launcher(marker=mark)
    assert not mark.exists()  # al arrancar, la marca vieja se borra
    proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        launcher.current = Running("game:1", "Zelda", proc)
        import json
        exe = json.loads(mark.read_text(encoding="utf-8"))["pids"][str(proc.pid)] or "python.exe"
        table = {proc.pid: (exe.lower(), 0)} if sys.platform == "win32" else None  # la foto de procesos de Windows
        assert supervisor.game_open(mark, table=table) == "Zelda"
        launcher.current = None
        assert not mark.exists()
    finally:
        proc.kill()
        proc.wait()


def test_the_launcher_writes_no_mark_outside_the_supervisor(tmp_path, monkeypatch):
    from orbital.launcher import Launcher
    monkeypatch.delenv(supervisor.CHILD_ENV, raising=False)
    assert Launcher()._marker is None
    monkeypatch.setenv(supervisor.CHILD_ENV, "1")
    assert Launcher()._marker == supervisor.busy_flag()  # junto a la de «actualizando» (en pruebas, en tmp_path)
    assert supervisor.busy_flag().name == supervisor.BUSY_FILE


# --------------------------------------------------- lo de enfrente manda, no el nombre del proceso (11 nov 2026)
def front(pid=0, exe="", fullscreen=False, orbital=False, idle=0.0):
    return lambda: {"pid": pid, "exe": exe, "fullscreen": fullscreen, "orbital": orbital, "idle": idle}


def mark(tmp_path, title, pids, exe="", at=None):
    path = tmp_path / "busy.json"
    supervisor.write_busy({"id": title, "title": title, "pids": pids, "exe": exe, **({"at": at} if at else {})}, path)
    return path


def test_a_launcher_left_in_the_tray_does_not_count(tmp_path):
    path = mark(tmp_path, "Stremio", {}, exe="stremio.exe")
    table = {7: ("stremio.exe", 1), 9: ("explorer.exe", 1)}
    assert supervisor.game_open(path, table, front=front(9, "explorer.exe")) == ""  # en la bandeja, el escritorio al frente
    assert supervisor.game_open(path, table, front=front(5, "msedge.exe", fullscreen=True, orbital=True)) == ""  # Orbital


def test_a_launcher_in_front_counts_if_full_screen_or_being_used(tmp_path):
    path = mark(tmp_path, "GeForce NOW", {"40": "geforcenow.exe"})
    table = {40: ("geforcenow.exe", 1)}
    assert supervisor.game_open(path, table, front=front(40, "geforcenow.exe", fullscreen=True, idle=7200)) == "GeForce NOW"
    assert supervisor.game_open(path, table, front=front(40, "geforcenow.exe", idle=60)) == "GeForce NOW"  # la usas
    assert supervisor.game_open(path, table, front=front(40, "geforcenow.exe", idle=supervisor.IDLE_LIMIT + 1)) == ""


def test_a_real_game_always_counts_until_the_time_limit(tmp_path):
    path = mark(tmp_path, "Zelda", {"40": "eden.exe"}, at=1000.0)
    table = {40: ("eden.exe", 1)}
    desk = front(9, "explorer.exe")
    assert supervisor.game_open(path, table, front=desk, now=1000.0 + 3600) == "Zelda"  # aunque no esté al frente
    late = 1000.0 + supervisor.HOLD_LIMIT + 1
    assert supervisor.game_open(path, table, front=desk, now=late) == ""  # pasado el tope y sin usarlo: sí se reabre
    assert supervisor.game_open(path, table, front=front(40, "eden.exe", idle=99999), now=late) == "Zelda"  # al frente
    assert supervisor.game_open(path, table, front=front(3, "mpv.exe", fullscreen=True), now=late) == "Zelda"  # un video


def test_when_the_front_cannot_be_known_it_never_steals_the_screen(tmp_path):
    path = mark(tmp_path, "Stremio", {"7": "stremio.exe"}, at=1.0)
    assert supervisor.game_open(path, {7: ("stremio.exe", 1)}, front=lambda: None, now=1e9) == "Stremio"


def test_rewriting_the_mark_keeps_when_it_was_opened(tmp_path):
    path = mark(tmp_path, "Zelda", {"40": "eden.exe"}, at=1000.0)
    supervisor.write_busy({"id": "Zelda", "title": "Zelda", "pids": {"40": "eden.exe", "41": "eden.exe"}, "exe": ""}, path)
    import json
    assert json.loads(path.read_text(encoding="utf-8"))["at"] == 1000.0  # se conoció otro proceso: no reinicia el tope
    supervisor.write_busy({"id": "Halo", "title": "Halo", "pids": {"50": "halo.exe"}, "exe": ""}, path)
    assert json.loads(path.read_text(encoding="utf-8"))["at"] > 1000.0  # otra cosa: hora nueva


def test_after_a_crash_a_launcher_in_the_tray_does_not_hold_orbital_forever(tmp_path):
    path = mark(tmp_path, "Stremio", {"7": "stremio.exe"})
    table = {7: ("stremio.exe", 1)}
    slept = []
    supervisor.hold_while_open(lambda: supervisor.game_open(path, table, front=front(9, "explorer.exe")), slept.append)
    assert slept == []  # reabre de inmediato


def test_the_hung_orbital_is_reopened_when_only_a_tray_launcher_remains(tmp_path):
    path = mark(tmp_path, "GeForce NOW", {"40": "geforcenow.exe"})
    table = {40: ("geforcenow.exe", 1)}
    child = Child()
    answers = iter([True] + [False] * 20)
    away = lambda: supervisor.away_reason(  # noqa: E731
        1, game=lambda: supervisor.game_open(path, table, front=front(5, "msedge.exe", orbital=True)), front=lambda pid: True)
    assert supervisor.watch(child, lambda: next(answers), clock_from(), busy=lambda: False, away=away) == supervisor.HUNG


def test_foreground_info_reads_the_window():
    class Full(Win):
        def is_fullscreen(self, hwnd):
            return True

        def input_idle_seconds(self):
            return 12.0

    got = supervisor.foreground_info(1, Full(pid=40, exe="Ryujinx.exe", title="Mario Kart", tree=(1,)))
    assert got == {"pid": 40, "exe": "ryujinx.exe", "fullscreen": True, "orbital": False, "idle": 12.0}
    assert supervisor.foreground_info(1, Win())["orbital"] is True
    assert supervisor.foreground_info(1, Win(fg=0)) is None
