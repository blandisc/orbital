"""Actualizar Orbital: con repositorios git de verdad en una carpeta temporal (sin red)."""

import subprocess
from types import SimpleNamespace

import pytest

from orbital.updater import Updater


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def repos(tmp_path):
    origin, work, other = tmp_path / "origin.git", tmp_path / "orbital", tmp_path / "otra"
    subprocess.run(["git", "init", "--bare", "-b", "main", str(origin)], check=True, capture_output=True)
    for repo in (work, other):
        subprocess.run(["git", "clone", "-q", str(origin), str(repo)], check=True, capture_output=True)
        git(repo, "config", "user.email", "t@t")
        git(repo, "config", "user.name", "t")
        git(repo, "checkout", "-q", "-B", "main")
    (other / "a.txt").write_text("1")
    git(other, "add", ".")
    git(other, "commit", "-qm", "Primera")
    git(other, "push", "-q", "origin", "main")
    git(work, "pull", "-q", "origin", "main")
    (other / "a.txt").write_text("2")
    git(other, "commit", "-qam", "Algo nuevo")
    git(other, "push", "-q", "origin", "main")
    return work


def fake_run(code):
    calls = []

    def run(cmd, **kwargs):
        calls.append(cmd)
        return SimpleNamespace(returncode=code, stdout="", stderr="")
    return run, calls


def test_finds_new_changes(repos):
    info = Updater(repos).check()
    assert info.available == 1 and info.changes == ["Algo nuevo"] and not info.error


def test_update_applies_when_tests_pass(repos):
    run, calls = fake_run(0)
    ok, _ = Updater(repos, run=run).apply()
    assert ok and (repos / "a.txt").read_text() == "2"
    assert any("pytest" in c for c in calls)
    tests = next(c for c in calls if "pytest" in c)
    assert tests[len(tests) - 1 - tests[::-1].index("-m") + 1] == "not reloj"  # lo que depende del reloj no rechaza una versión buena


def test_update_rolls_back_when_tests_fail(repos):
    before = git(repos, "rev-parse", "HEAD")
    run, _ = fake_run(1)
    ok, message = Updater(repos, run=run).apply()
    assert not ok and "versión que tenías" in message
    assert git(repos, "rev-parse", "HEAD") == before and (repos / "a.txt").read_text() == "1"


def test_never_updates_over_unsaved_changes(repos):
    (repos / "a.txt").write_text("a medio editar")
    run, calls = fake_run(0)
    ok, message = Updater(repos, run=run).apply()
    assert not ok and "sin guardar" in message and (repos / "a.txt").read_text() == "a medio editar"
    assert calls == []


def test_update_api_reports_and_applies(library, repos):
    import time

    from fastapi.testclient import TestClient

    from orbital.server import create_app

    run, _ = fake_run(0)
    app = create_app(library.config, library, updater=Updater(repos, run=run))
    with TestClient(app, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        assert c.get("/api/update").json()["available"] == 1
        queue = app.state.bus.subscribe()
        assert c.post("/api/update").json() == {"ok": True}
        deadline = time.monotonic() + 20
        event = {}
        while event.get("type") != "update-done" and time.monotonic() < deadline:
            event = c.portal.call(queue.get)
    assert event["ok"] and (repos / "a.txt").read_text() == "2"


def _stable(other, *, at="HEAD"):
    git(other, "tag", "-f", "tv-estable", at)
    git(other, "push", "-q", "--force", "origin", "refs/tags/tv-estable")


def test_with_the_stable_tag_it_updates_only_to_the_tag(repos):
    other = repos.parent / "otra"
    _stable(other)  # la CI aprobó «Algo nuevo»
    (other / "a.txt").write_text("3")
    git(other, "commit", "-qam", "Sin aprobar todavía")
    git(other, "push", "-q", "origin", "main")
    info = Updater(repos).check()
    assert info.available == 1 and info.changes == ["Algo nuevo"] and info.ref == "refs/tags/tv-estable"
    run, _ = fake_run(0)
    ok, _ = Updater(repos, run=run).apply()
    assert ok and (repos / "a.txt").read_text() == "2"  # lo aprobado, no la punta de main
    _stable(other)  # la CI aprobó también lo nuevo: la etiqueta se movió
    assert Updater(repos).check().changes == ["Sin aprobar todavía"]


def test_a_tag_that_is_behind_means_nothing_new(repos):
    other = repos.parent / "otra"
    _stable(other, at="HEAD~1")  # la etiqueta en lo que la TV ya tiene
    assert Updater(repos).check().available == 0


def test_without_the_tag_it_updates_from_the_branch_as_before(repos):
    info = Updater(repos).check()
    assert info.ref == "origin/main" and info.available == 1


def recording_run(code, seen):
    """Como fake_run, pero anota dónde corrieron las pruebas y qué había ahí en ese momento."""
    def run(cmd, **kwargs):
        from pathlib import Path
        where = Path(kwargs["cwd"])
        seen.append({"cwd": where, "a": (where / "a.txt").read_text(), "pythonpath": kwargs["env"]["PYTHONPATH"]})
        return SimpleNamespace(returncode=code, stdout="", stderr="")
    return run


def test_f9_the_new_version_is_tested_aside_and_the_folder_moves_only_after(repos):
    seen = []
    ok, _ = Updater(repos, run=recording_run(0, seen)).apply()
    assert ok and (repos / "a.txt").read_text() == "2"
    (test,) = seen
    assert test["cwd"] != repos and test["a"] == "2"  # la copia aparte ya tenía la versión nueva
    assert test["pythonpath"].split(__import__("os").pathsep)[0] == str(test["cwd"])  # importa SU orbital
    assert not test["cwd"].exists()  # y se borró
    assert git(repos, "worktree", "list").count("\n") == 0  # git ya no la recuerda


def test_f9_if_the_copy_fails_the_folder_was_never_touched(repos):
    before = git(repos, "rev-parse", "HEAD")
    seen = []
    ok, message = Updater(repos, run=recording_run(1, seen)).apply()
    assert not ok and "versión que tenías" in message
    assert git(repos, "rev-parse", "HEAD") == before and (repos / "a.txt").read_text() == "1"
    assert seen[0]["a"] == "2" and not seen[0]["cwd"].exists()
    assert git(repos, "worktree", "list").count("\n") == 0


def test_f9_with_new_dependencies_it_tests_in_place_as_before(repos, tmp_path):
    other = tmp_path / "otra"
    (other / "requirements.lock").write_text("fastapi==1\n")
    git(other, "add", ".")
    git(other, "commit", "-qm", "Dependencias nuevas")
    git(other, "push", "-q", "origin", "main")
    seen = []
    run = recording_run(0, seen)

    def run_or_pip(cmd, **kwargs):
        if "pytest" in cmd:
            return run(cmd, **kwargs)
        return SimpleNamespace(returncode=0, stdout="", stderr="")
    ok, _ = Updater(repos, run=run_or_pip).apply()
    assert ok and seen[0]["cwd"] == repos  # el .venv es uno solo: se prueba en la carpeta, con rollback si falla


def test_once_the_tv_saw_the_tag_it_never_falls_back_to_the_tip_of_main(repos):
    """Revisión del 11 nov 2026: si la etiqueta tv-estable desaparece de GitHub, una tele que ya la usaba no se pone a
    actualizarse desde la punta de main (sin pasar por la CI): no actualiza y lo dice."""
    other = repos.parent / "otra"
    _stable(other)
    assert Updater(repos).check().ref == "refs/tags/tv-estable"  # la vio: queda anotado en su repositorio
    git(other, "push", "-q", "origin", ":refs/tags/tv-estable")  # alguien la borró
    (other / "a.txt").write_text("3")
    git(other, "commit", "-qam", "Sin aprobar")
    git(other, "push", "-q", "origin", "main")
    info = Updater(repos).check()
    assert info.available == 0 and "tv-estable" in info.error  # «Actualizar ahora» lo dice
    run, calls = fake_run(0)
    ok, message = Updater(repos, run=run).apply()
    assert not ok and "tv-estable" in message and calls == []
    assert (repos / "a.txt").read_text() == "1"  # ni se tocó
    _stable(other)  # la etiqueta regresa: todo sigue como antes
    assert Updater(repos).check().ref == "refs/tags/tv-estable" and not Updater(repos).check().error
