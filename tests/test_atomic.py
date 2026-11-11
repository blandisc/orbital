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


def test_atomic_text_writes_the_same_bytes_as_write_text(tmp_path, monkeypatch):
    """Las configuraciones de los emuladores pasan a atómico sin cambiar ni un byte (en Windows, «\\r\\n» como antes)."""
    text = "[Settings]\nBorderlessFullscreen = True\n\n[Core]\nSIDevice0 = 6\n"
    plain, safe = tmp_path / "a.ini", tmp_path / "b.ini"
    plain.write_text(text, encoding="utf-8")
    atomic.atomic_write_text(safe, text)
    assert safe.read_bytes() == plain.read_bytes()
    monkeypatch.setattr(atomic.os, "linesep", "\r\n")
    atomic.atomic_write_text(safe, text)
    assert safe.read_bytes() == text.replace("\n", "\r\n").encode("utf-8")
    assert not atomic.tmp_path(safe).exists()


def test_threads_writing_and_reading_the_same_file_never_see_half_a_file(tmp_path):
    """Revisión del 11 nov 2026: con el temporal fijo, 2 hilos × 300 escrituras daban 165 FileNotFoundError y 188 lecturas
    de JSON roto. Ahora: 3 escritores, 3 lectores; nadie falla, nadie lee a medias y queda la última escritura."""
    import threading

    path = tmp_path / "foryou-cache.json"
    atomic_write(path, json.dumps({"writer": -1, "n": -1, "pad": ""}), durable=False)
    errors: list = []
    stop = threading.Event()
    pad = "x" * 20_000  # lo bastante grande para que una lectura a medias se note

    def writer(w):
        try:
            for n in range(300):
                atomic_write(path, json.dumps({"writer": w, "n": n, "pad": pad}), durable=n % 50 == 0)
        except Exception as exc:  # noqa: BLE001
            errors.append(("write", repr(exc)))

    def reader():
        while not stop.is_set():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                assert data["pad"] in ("", pad)
            except PermissionError:  # Windows: abrir justo mientras se cambia; el lector real reintenta
                continue
            except Exception as exc:  # noqa: BLE001
                errors.append(("read", repr(exc)))

    readers = [threading.Thread(target=reader) for _ in range(3)]
    writers = [threading.Thread(target=writer, args=(w,)) for w in range(3)]
    for t in readers + writers:
        t.start()
    for t in writers:
        t.join()
    stop.set()
    for t in readers:
        t.join()
    assert errors == []
    final = json.loads(path.read_text(encoding="utf-8"))
    assert final["n"] == 299  # la última de algún escritor, completa
    atomic_write(path, '{"ultima": true}')
    assert json.loads(path.read_text(encoding="utf-8")) == {"ultima": True}  # nunca se pierde la última
    assert sorted(p.name for p in tmp_path.iterdir()) == ["foryou-cache.json"]  # ningún temporal tirado


def test_backups_are_made_safely_from_several_threads(tmp_path):
    import threading

    path = tmp_path / "state.json"
    atomic_write(path, json.dumps({"n": 0}), backup=True)
    errors: list = []

    def writer(w):
        try:
            for n in range(100):
                atomic_write(path, json.dumps({"n": n, "w": w}), backup=True)
        except Exception as exc:  # noqa: BLE001
            errors.append(repr(exc))

    threads = [threading.Thread(target=writer, args=(w,)) for w in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []
    assert json.loads(backup_path(path).read_text(encoding="utf-8"))["n"] in range(100)  # el .bak, completo
    assert sorted(p.name for p in tmp_path.iterdir()) == ["state.json", "state.json.bak"]


def test_the_backup_is_pushed_to_disk_too(tmp_path, monkeypatch):
    synced = []
    real = os.fsync
    monkeypatch.setattr(atomic.os, "fsync", lambda fd: (synced.append(fd), real(fd))[1])
    path = tmp_path / "x.json"
    atomic_write(path, "uno")
    synced.clear()
    atomic_write(path, "dos", backup=True)
    assert len(synced) >= 2  # el nuevo y su .bak


def test_a_busy_file_on_windows_is_retried_briefly(tmp_path, monkeypatch):
    path = tmp_path / "x.json"
    path.write_text("viejo", encoding="utf-8")
    real = os.replace
    tries = []

    def busy_then_ok(a, b):
        tries.append(1)
        if len(tries) < 3:
            raise PermissionError(13, "El proceso no tiene acceso al archivo porque está siendo utilizado")
        real(a, b)

    monkeypatch.setattr(atomic, "WINDOWS", True)
    monkeypatch.setattr(atomic.os, "replace", busy_then_ok)
    monkeypatch.setattr(atomic.time, "sleep", lambda s: None)
    atomic_write(path, "nuevo", durable=False)
    assert path.read_text(encoding="utf-8") == "nuevo" and len(tries) == 3


def test_saving_does_not_change_who_can_read_the_file(tmp_path):
    if os.name == "nt":
        pytest.skip("permisos de Unix")
    path = tmp_path / "x.json"
    path.write_text("viejo", encoding="utf-8")
    path.chmod(0o644)
    atomic_write(path, "nuevo")
    assert path.stat().st_mode & 0o777 == 0o644  # mkstemp crea 0600: se respetan los de antes
