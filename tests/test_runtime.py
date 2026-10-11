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
