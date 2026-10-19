"""El clic en el ícono de Orbital: traer la que ya está, esperar a la que arranca o reemplazar a la colgada."""

from __future__ import annotations

from orbital import launch_click


def run(answers, lock, stuck=(11, 12)):
    calls = {"shown": 0, "killed": None, "notes": [], "waits": []}
    lock = list(lock)

    def answers_fn(seconds):
        calls["waits"].append(seconds)
        return answers.pop(0) if answers else False

    def lock_fn(seconds):
        return lock.pop(0) if lock else False

    out = launch_click.resolve(answers=answers_fn, take_lock=lock_fn, show=lambda: calls.__setitem__("shown", calls["shown"] + 1),
                               stuck=lambda: list(stuck), kill=lambda pids: calls.__setitem__("killed", pids),
                               note=calls["notes"].append)
    return out, calls


def test_already_open_brings_its_window():
    out, calls = run(answers=[True], lock=[])
    assert out == "shown" and calls["shown"] == 1 and calls["killed"] is None


def test_not_open_starts_a_new_one():
    out, calls = run(answers=[False], lock=[True])
    assert out == "start" and calls["shown"] == 0


def test_starting_up_waits_and_brings_it_instead_of_closing_silently():
    out, calls = run(answers=[False, True], lock=[False])
    assert out == "shown" and calls["killed"] is None and calls["waits"] == [launch_click.ANSWER_WAIT, launch_click.STARTING_WAIT]


def test_a_hung_orbital_is_closed_and_a_new_one_opens():
    out, calls = run(answers=[False, False], lock=[False, True])
    assert out == "start" and calls["killed"] == [11, 12]
    assert any("colgada" in n for n in calls["notes"])


def test_only_orbital_processes_that_are_not_us_or_our_parents():
    procs = {100: ("pythonw.exe", 1), 101: ("pythonw.exe", 100),  # el vigilante colgado y su hijo
             200: ("pythonw.exe", 2), 201: ("pythonw.exe", 200),  # nosotros (el lanzador del .venv y el Python real)
             300: ("xemu.exe", 101), 400: ("python.exe", 3)}  # un juego que abrió Orbital y otro Python cualquiera
    cmd = {100: "pythonw.exe -m orbital", 101: "pythonw.exe -m orbital", 200: "pythonw.exe -m orbital", 201: "pythonw.exe -m orbital",
           300: "xemu.exe game.iso", 400: "python.exe -m http.server"}
    assert launch_click.stuck_orbital(201, lambda: procs, lambda pid: cmd.get(pid, "")) == [100, 101]


def test_every_click_leaves_a_line(tmp_path):
    log = tmp_path / "lanzador.log"
    launch_click.note("Clic: abro Orbital", log)
    assert "Clic: abro Orbital" in log.read_text(encoding="utf-8")
