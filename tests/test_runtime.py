import subprocess
import sys
import time
import uuid

import pytest

from orbital import runtime


def test_log_rotates_when_it_gets_big(tmp_path):
    path = tmp_path / "orbital.log"
    path.write_text("ejecución anterior", encoding="utf-8")
    stream = runtime.RotatingStream(path, max_bytes=100, backups=2)
    assert (tmp_path / "orbital.log.1").read_text(encoding="utf-8") == "ejecución anterior"
    for _ in range(30):
        stream.write("una línea de registro\n")
    stream.flush()
    assert path.stat().st_size <= 150 and (tmp_path / "orbital.log.2").exists()
    assert not (tmp_path / "orbital.log.3").exists()  # solo se guardan `backups` anteriores


@pytest.mark.skipif(sys.platform != "win32", reason="candado de Windows")
def test_only_one_orbital_at_a_time():
    name = f"Local\\OrbitalTest-{uuid.uuid4().hex}"
    holder = subprocess.Popen([sys.executable, "-c", (
        "import ctypes, time; k = ctypes.windll.kernel32; k.CreateMutexW.restype = ctypes.c_void_p; "
        f"h = k.CreateMutexW(None, True, {name!r}); print('ok', flush=True); time.sleep(1.5)")],
        stdout=subprocess.PIPE, text=True)
    assert holder.stdout.readline().strip() == "ok"
    assert not runtime.single_instance(name, wait=0)  # el otro sigue abierto
    started = time.monotonic()
    assert runtime.single_instance(name, wait=5)  # espera a que el otro cierre y se queda el candado
    assert time.monotonic() - started < 5
    holder.wait(5)


def test_packaged_app_detection_does_not_crash():
    assert runtime.packaged_app() is None or isinstance(runtime.packaged_app(), str)


def test_virtualization_check_runs(tmp_path):
    # En una carpeta normal no hay redirección (en la app de Claude, AppData sí la tendría).
    assert runtime.virtualized_appdata(tmp_path) is None


@pytest.mark.skipif(sys.platform != "win32", reason="procesos de Windows")
def test_reads_another_process_command_line():
    from orbital import windows

    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(5)", r"--user-data-dir=C:\Orbital Perfil"])
    try:
        deadline = time.monotonic() + 5
        line = ""
        while "--user-data-dir" not in line and time.monotonic() < deadline:
            line = windows.command_line(child.pid)
            time.sleep(.05)
        assert r"--user-data-dir=C:\Orbital Perfil" in line
    finally:
        child.kill()
        child.wait(5)


@pytest.mark.skipif(sys.platform != "win32", reason="DPAPI es de Windows")
def test_secrets_are_encrypted_and_old_plain_files_migrate(tmp_path):
    import json

    from orbital.credentials import Credentials

    path = tmp_path / "secrets.json"
    path.write_text(json.dumps({"stremio_auth": "clave-de-sesion"}), encoding="utf-8")
    assert Credentials(path).get("stremio_auth") == "clave-de-sesion"  # el archivo viejo se lee
    assert "clave-de-sesion" not in path.read_text(encoding="utf-8")  # y queda cifrado
    creds = Credentials(path)
    assert creds.get("stremio_auth") == "clave-de-sesion"
    creds.set("otra", "valor")
    assert Credentials(path).get("otra") == "valor" and "valor" not in path.read_text(encoding="utf-8")


def test_unreadable_secrets_do_not_crash(tmp_path):
    from orbital.credentials import Credentials

    path = tmp_path / "secrets.json"
    path.write_text('{"format": "orbital-dpapi-1", "data": "AAAA"}', encoding="utf-8")
    assert Credentials(path).get("stremio_auth") is None


def test_a_click_with_orbital_open_does_not_die_on_a_log_in_use(tmp_path, monkeypatch):
    """El clic en el ícono con Orbital abierta: Windows no deja mover vigilante.log (lo tiene abierto la que corre). Antes
    eso mataba al clic sin decir nada; ahora escribe al final del mismo archivo."""
    from pathlib import Path

    from orbital import runtime

    log = tmp_path / "vigilante.log"
    log.write_text("lo de la Orbital que ya corre\n", encoding="utf-8")

    def in_use(self, target):
        raise PermissionError(32, "El proceso no tiene acceso al archivo porque está siendo utilizado por otro proceso")
    monkeypatch.setattr(Path, "replace", in_use)
    stream = runtime.RotatingStream(log)
    stream.write("Clic: Orbital ya estaba abierta\n")
    stream.close()
    text = log.read_text(encoding="utf-8")
    assert "lo de la Orbital que ya corre" in text and "Clic: Orbital ya estaba abierta" in text
