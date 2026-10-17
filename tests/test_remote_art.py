from __future__ import annotations

import io

from PIL import Image

from orbital import remote_art


def jpeg(size=(1920, 1080)) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", size, (200, 40, 40)).save(out, "JPEG", quality=95)
    return out.getvalue()


def test_web_art_is_downloaded_once_and_shrunk_to_the_card(tmp_path):
    calls: list[str] = []

    def download(url):
        calls.append(url)
        return jpeg()

    url = "https://images.metahub.space/background/medium/tt1/img"
    path = remote_art.sized(url, 240, tmp_path, download)
    assert Image.open(path).size == (240, 135)
    assert remote_art.sized(url, 300, tmp_path, download).name != path.name  # otro ancho fijo (320)
    assert len(calls) == 1  # el original ya estaba en disco


def test_only_known_art_sites_and_failures_fall_back():
    assert remote_art.allowed("https://image.tmdb.org/t/p/w500/x.jpg")
    assert not remote_art.allowed("https://evil.example/x.jpg") and not remote_art.allowed("http://images.metahub.space/x")
    assert remote_art.snap(100) == 160 and remote_art.snap(700) == 960 and remote_art.snap(5000) == 1280


def test_api_serves_the_small_copy_or_sends_to_the_original(make_client, monkeypatch):
    monkeypatch.setattr(remote_art, "fetch", lambda url, timeout=10: jpeg((1000, 1500)))
    c = make_client()
    ok = c.get("/api/img", params={"u": "https://images.metahub.space/poster/medium/tt2/img", "w": 240})
    assert ok.status_code == 200 and ok.headers["content-type"] == "image/webp"
    assert Image.open(io.BytesIO(ok.content)).size == (240, 360)
    assert c.get("/api/img", params={"u": "https://evil.example/a.jpg"}).status_code == 404
    monkeypatch.setattr(remote_art, "fetch", lambda url, timeout=10: (_ for _ in ()).throw(OSError("x")))
    gone = c.get("/api/img", params={"u": "https://image.tmdb.org/t/p/original/z.jpg"}, follow_redirects=False)
    assert gone.status_code == 307 and gone.headers["location"] == "https://image.tmdb.org/t/p/original/z.jpg"
