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
