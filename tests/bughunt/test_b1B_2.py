import pytest
from orbital import emulator_updates as eu
from orbital.emulator_updates import download as real_download

class _Cut:
    _sent = False
    def __enter__(self):
        return self
    def __exit__(self, *exc):
        return False
    def read(self, n=-1):
        if not self._sent:
            self._sent = True
            return b'mitad'
        raise OSError('se corto')

def test_a_failed_download_leaves_no_partial(tmp_path, monkeypatch):
    monkeypatch.setattr(eu.urllib.request, 'urlopen', lambda req, timeout=None: _Cut())
    dest = tmp_path / 'xemu-1.0.zip'
    with pytest.raises(OSError):
        real_download('https://x/y.zip', dest)
    assert not dest.with_suffix('.zip.part').exists()