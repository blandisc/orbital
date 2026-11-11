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
    assert remote_art.snap(100) == 160 and remote_art.snap(700) == 960 and remote_art.snap(5000) == 1920


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


def test_a_metahub_poster_goes_first_with_the_tmdb_one(make_client, library, monkeypatch):
    """P1 (Fernando, 8 nov): el póster de metahub de «Star Wars: Clone Wars» era de un programa coreano; con TMDB, el suyo."""
    asked: list[str] = []
    monkeypatch.setattr(remote_art, "fetch", lambda url, timeout=10: asked.append(url) or jpeg((1000, 1500)))
    monkeypatch.setattr(library.foryou, "tmdb_poster", lambda imdb: "https://image.tmdb.org/t/p/w500/cw.jpg" if imdb == "tt0361243" else None)
    c = make_client()
    assert c.get("/api/img", params={"u": "https://images.metahub.space/poster/small/tt0361243/img", "w": 240}).status_code == 200
    assert asked == ["https://image.tmdb.org/t/p/w500/cw.jpg"]
    assert c.get("/api/img", params={"u": "https://images.metahub.space/poster/medium/tt9/img", "w": 240}).status_code == 200
    assert asked[-1] == "https://images.metahub.space/poster/medium/tt9/img"  # TMDB no lo tiene: el de siempre


def test_tmdb_poster_needs_a_key_and_waits_after_a_failure(library, monkeypatch):
    from orbital.library.tmdb import TmdbError

    foryou = library.foryou
    monkeypatch.setattr(foryou.tmdb, "key", "")
    assert foryou.tmdb_poster("tt0361243") is None
    monkeypatch.setattr(foryou.tmdb, "key", "k")
    calls: list[str] = []
    monkeypatch.setattr(foryou.tmdb, "poster", lambda imdb: calls.append(imdb) or (_ for _ in ()).throw(TmdbError("x")))
    assert foryou.tmdb_poster("tt0361243") is None and foryou.tmdb_poster("tt1") is None
    assert calls == ["tt0361243"]  # sin TMDB, no se espera por cada póster


def _file(path, size, mtime):
    import os

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    os.utime(path, (mtime, mtime))


def test_prune_keeps_the_newest_by_count_and_by_size(tmp_path):
    import time

    now = time.time()
    for i in range(6):
        _file(tmp_path / "raw" / f"{i}.img", 100, now - 1000 + i)
        _file(tmp_path / "sized" / f"{i}.webp", 10, now - 1000 + i)
    _file(tmp_path / "raw" / "cut.part", 5, now - 7200)  # una bajada que se cortó hace dos horas
    _file(tmp_path / "sized" / "new.tmp", 5, now)  # otra que va a la mitad: no se toca
    removed = remote_art.prune(tmp_path, keep=4, max_bytes=10_000)
    raw = sorted(p.name for p in (tmp_path / "raw").iterdir())
    assert raw == ["2.img", "3.img", "4.img", "5.img"]  # por cantidad: los dos más viejos
    assert len(list((tmp_path / "sized").glob("*.webp"))) == 6  # las copias tienen su propio tope (4 x 3)
    assert (tmp_path / "sized" / "new.tmp").exists() and removed == 3
    remote_art.prune(tmp_path, keep=100, max_bytes=250)  # por tamaño: de lo más viejo a lo más nuevo hasta caber
    left = sorted((p for p in tmp_path.rglob("*") if p.is_file() and p.suffix != ".tmp"), key=lambda p: p.stat().st_mtime)
    assert sum(p.stat().st_size for p in left) <= 250 and (tmp_path / "raw" / "5.img").exists()


def test_prune_without_a_cache_does_nothing(tmp_path):
    assert remote_art.prune(tmp_path / "nada") == 0
