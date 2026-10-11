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
