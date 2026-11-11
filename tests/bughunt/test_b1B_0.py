import threading
import time

from orbital import downloads


def test_a_concurrent_save_cannot_lose_a_download(tmp_path, monkeypatch):
    dl = downloads.Downloads(tmp_path, resolve=lambda j: ('', ''), publish=lambda e: None, autostart=False)
    dl.add('movie', 'tt1', 'tt1', 'Uno')
    real_write = downloads.atomic_write
    gate, blocked, release = {'block': True}, threading.Event(), threading.Event()

    def write(path, data, **kw):
        if gate['block'] and path == dl.index_path:
            gate['block'] = False
            blocked.set()
            release.wait(5)
        return real_write(path, data, **kw)

    monkeypatch.setattr(downloads, 'atomic_write', write)
    saver = threading.Thread(target=dl._save, daemon=True)
    saver.start()
    assert blocked.wait(5)
    threading.Thread(target=lambda: (time.sleep(1.0), release.set()), daemon=True).start()
    dl._jobs['tt2'] = {'id': 'tt2', 'status': 'queued', 'done': 0, 'size': 0}
    dl._save()
    saver.join(5)
    again = downloads.Downloads(tmp_path, resolve=lambda j: ('', ''), publish=lambda e: None, autostart=False)
    assert {j['id'] for j in again.list()} == {'tt1', 'tt2'}