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
