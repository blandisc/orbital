import shutil
import zipfile

import pytest

from orbital import emulator_updates as eu


def test_a_failed_install_removes_a_half_written_new_file(tmp_path, monkeypatch):
    folder = tmp_path / 'xemu'
    folder.mkdir()
    exe = folder / 'xemu.exe'
    exe.write_bytes(b'viejo')
    zip_path = tmp_path / 'up.zip'
    with zipfile.ZipFile(zip_path, 'w') as zf:
        zf.writestr('xemu.exe', b'nuevo')
        zf.writestr('nuevo.bin', b'datos')
    calls = {'n': 0}
    real = shutil.copyfileobj

    def boom(src, dst, *a, **k):
        calls['n'] += 1
        if calls['n'] == 2:
            dst.write(b'a medias')
            raise OSError('disco lleno')
        return real(src, dst, *a, **k)

    monkeypatch.setattr(eu.shutil, 'copyfileobj', boom)
    with pytest.raises(eu.InstallError):
        eu.install_zip(zip_path, exe, 'v2')
    assert not (folder / 'nuevo.bin').exists()