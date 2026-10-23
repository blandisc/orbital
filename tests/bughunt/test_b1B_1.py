import io
import shutil

from orbital import downloads


def _ok(request, timeout=0):
    res = io.BytesIO(b'video')
    res.status, res.url = 200, 'https://x/Dune.mkv'
    res.headers = {'Content-Length': '5', 'Content-Type': 'video/x-matroska'}
    return res

def test_downloads_survive_moving_their_folder(tmp_path):
    first = tmp_path / 'A'
    dl = downloads.Downloads(first, resolve=lambda j: ('https://x/Dune.mkv', 'Dune.mkv'),
                             publish=lambda e: None, opener=_ok, autostart=False)
    dl.add('movie', 'tt1', 'tt1', 'Dune')
    dl.run(dl._next())
    assert (first / 'Dune.mkv').read_bytes() == b'video'
    moved = tmp_path / 'B'
    shutil.move(str(first), str(moved))
    again = downloads.Downloads(moved, resolve=lambda j: ('', ''), publish=lambda e: None, autostart=False)
    assert again.file_for('tt1') == moved / 'Dune.mkv'