"""atomic_write: el archivo queda viejo completo o nuevo completo, y state/secrets recuperan su copia anterior."""

from __future__ import annotations

import json
import os

import pytest

from orbital import atomic
from orbital.atomic import atomic_write, backup_path
from orbital.credentials import Credentials
from orbital.state import State


def test_writes_text_and_bytes_and_leaves_no_temp(tmp_path):
    path = tmp_path / "sub" / "a.json"
    atomic_write(path, '{"á": 1}')
    assert json.loads(path.read_text(encoding="utf-8")) == {"á": 1}
    atomic_write(path, b"\x89PNG", durable=False)
    assert path.read_bytes() == b"\x89PNG"
    assert sorted(p.name for p in path.parent.iterdir()) == ["a.json"]


def test_fsyncs_before_replacing(tmp_path, monkeypatch):
    order = []
    real_fsync, real_replace = os.fsync, os.replace
    monkeypatch.setattr(atomic.os, "fsync", lambda fd: (order.append("fsync"), real_fsync(fd))[1])
    monkeypatch.setattr(atomic.os, "replace", lambda a, b: (order.append("replace"), real_replace(a, b))[1])
    atomic_write(tmp_path / "x.json", "{}")
    assert order[:2] == ["fsync", "replace"]


def test_a_failed_write_keeps_the_old_file_and_cleans_up(tmp_path, monkeypatch):
    path = tmp_path / "x.json"
    path.write_text("viejo", encoding="utf-8")

    def boom(fd):
        raise OSError("disco lleno")

    monkeypatch.setattr(atomic.os, "fsync", boom)
    with pytest.raises(OSError):
        atomic_write(path, "nuevo")
    assert path.read_text(encoding="utf-8") == "viejo"
    assert not atomic.tmp_path(path).exists()


def test_backup_keeps_the_previous_version(tmp_path):
    path = tmp_path / "x.json"
    atomic_write(path, "uno", backup=True)
    assert not backup_path(path).exists()  # la primera vez no hay nada que respaldar
    atomic_write(path, "dos", backup=True)
    assert path.read_text(encoding="utf-8") == "dos" and backup_path(path).read_text(encoding="utf-8") == "uno"


def test_state_recovers_from_the_backup_when_damaged(tmp_path):
    path = tmp_path / "state.json"
    state = State(path)
    state.set_setting("audio", "en")
    state.set_setting("audio", "es")  # ahora state.json.bak tiene «en» y state.json tiene «es»
    assert backup_path(path).exists()
    path.write_text('{"history": {', encoding="utf-8")  # se cortó la luz a la mitad (o alguien lo editó mal)
    again = State(path)
    assert again.settings().get("audio") == "en"  # la copia anterior, no de cero
    assert list(tmp_path.glob("state-*.bak"))  # el dañado queda a salvo como siempre


def test_state_without_a_good_backup_starts_clean(tmp_path):
    path = tmp_path / "state.json"
    path.write_text("[]", encoding="utf-8")
    backup_path(path).write_text("tampoco", encoding="utf-8")
    assert State(path).settings() == {}


def test_credentials_recover_from_the_backup(tmp_path):
    path = tmp_path / "secrets.json"
    creds = Credentials(path)
    creds.set("trakt", "uno")
    creds.set("trakt", "dos")
    path.write_text("{roto", encoding="utf-8")
    again = Credentials(path)
    assert again.get("trakt") == "uno"
    assert list(tmp_path.glob("secrets.ilegible-*"))  # el dañado no se pierde
    assert json.loads(path.read_text(encoding="utf-8"))  # y el principal vuelve a ser legible


@pytest.mark.skipif(os.name == "nt", reason="permisos de Unix")
def test_credentials_stay_private(tmp_path):
    path = tmp_path / "secrets.json"
    creds = Credentials(path)
    creds.set("a", "1")
    creds.set("a", "2")
    assert path.stat().st_mode & 0o777 == 0o600 and backup_path(path).stat().st_mode & 0o777 == 0o600
