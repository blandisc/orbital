"""Descargas para ver sin internet: qué fuente se baja, retomar, el nombre del archivo y quitar solo lo suyo."""

from __future__ import annotations

import io

from orbital import downloads
from orbital.library.streams import Source


def src(i, url="https://rd.example/f.mkv", res="1080p", langs=("es",), tags=(), cached=True, onedrive=None):
    stream = {"onedrive": onedrive} if onedrive else {"url": url} if url else {"infoHash": "a" * 40}
    return Source(index=i, addon="x", stream=stream, transport_url="", resolution=res, languages=list(langs),
                  tags=list(tags), cached=cached)


def test_onedrive_first_then_a_direct_1080p_in_your_language():
    assert downloads.pick_source([src(1, res="4K"), src(2, onedrive="abc")]).index == 2
    picks = [src(1, res="4K"), src(2, res="1080p", langs=("en",)), src(3, res="1080p"), src(4, res="720p")]
    assert downloads.pick_source(picks, "es").index == 3
    assert downloads.pick_source([src(1, url=None), src(2, tags=("CAM",))]) is None  # torrent sin RD o grabación de cine: no


def test_safe_names_and_extensions():
    assert downloads.safe_name("Dune: Parte dos") == "Dune - Parte dos"
    assert downloads.safe_name('A/B?*"') == "AB"
    assert downloads.extension_for("https://x/y/Movie.2024.mp4?t=1") == ".mp4"
    assert downloads.extension_for("https://x/dl/123", "Show.S01E02.1080p.mkv") == ".mkv"
    assert downloads.extension_for("https://x/dl/123") == ".mkv"


class FakeResponse(io.BytesIO):
    def __init__(self, data, status=200, total=None):
        super().__init__(data)
        self.status = status
        self.headers = {"Content-Length": str(len(data)), "Content-Type": "video/x-matroska"}
        self.url = "https://rd.example/Dune.mkv"


def make(tmp_path, body=b"0123456789", fail_first=False):
    calls = []

    def opener(request, timeout=0):
        calls.append(dict(request.header_items()))
        if fail_first and len(calls) == 1:
            raise OSError("corte")
        rng = request.get_header("Range")
        if rng:
            start = int(rng.split("=")[1].rstrip("-"))
            return FakeResponse(body[start:], status=206)
        return FakeResponse(body)
    events = []
    dl = downloads.Downloads(tmp_path, resolve=lambda job: ("https://rd.example/Dune.mkv", "Dune.mkv"),
                             publish=events.append, opener=opener, autostart=False)
    return dl, calls, events


def test_a_movie_is_downloaded_to_its_folder_and_plays_from_disk(tmp_path, monkeypatch):
    monkeypatch.setattr(downloads.time, "sleep", lambda s: None)
    dl, calls, events = make(tmp_path)
    job = dl.add("movie", "tt15239678", "tt15239678", "Dune: Parte dos")
    assert job["status"] == "queued"
    dl.run(dl._next())
    done = dl.list()[0]
    assert (done["status"], done["progress"]) == ("done", 1.0)
    assert dl.file_for("tt15239678") == tmp_path / "Dune - Parte dos.mkv"
    assert (tmp_path / "Dune - Parte dos.mkv").read_bytes() == b"0123456789"
    assert (tmp_path / downloads.INDEX_NAME).exists()
    assert any(e.get("type") == "toast" for e in events)
    # Otra vez el mismo: no se duplica.
    assert dl.add("movie", "tt15239678", "tt15239678", "Dune: Parte dos")["status"] == "done"


def test_a_cut_download_resumes_where_it_was(tmp_path, monkeypatch):
    monkeypatch.setattr(downloads.time, "sleep", lambda s: None)
    dl, calls, _ = make(tmp_path)
    dl.add("series", "tt11280740", "tt11280740:1:2", "Severance", season=1, episode=2)
    (tmp_path / "Severance - T1E02.part").write_bytes(b"01234")
    job = dl._next()
    job["partial"] = str(tmp_path / "Severance - T1E02.part")
    dl.run(job)
    assert calls[-1].get("Range") == "bytes=5-"
    assert (tmp_path / "Severance - T1E02.mkv").read_bytes() == b"0123456789"


def test_failures_say_so_and_can_be_retried(tmp_path, monkeypatch):
    monkeypatch.setattr(downloads.time, "sleep", lambda s: None)
    dl, _, _ = make(tmp_path)
    dl.resolve = lambda job: ("", "")
    dl.add("movie", "tt1", "tt1", "Nada")
    dl.run(dl._next())
    failed = dl.list()[0]
    assert failed["status"] == "failed" and "fuente directa" in failed["error"]
    assert dl.retry(failed["id"]) and dl.list()[0]["status"] == "queued"


def test_removing_deletes_only_its_own_file(tmp_path, monkeypatch):
    monkeypatch.setattr(downloads.time, "sleep", lambda s: None)
    dl, _, _ = make(tmp_path)
    dl.add("movie", "tt15239678", "tt15239678", "Dune")
    dl.run(dl._next())
    other = tmp_path.parent / "no-tocar.mkv"
    other.write_bytes(b"x")
    dl._jobs["tt15239678"]["partial"] = str(other)  # aunque el índice apunte fuera de la carpeta, eso no se borra
    assert dl.remove("tt15239678")
    assert not (tmp_path / "Dune.mkv").exists() and other.exists()
    assert dl.list() == []


def test_an_interrupted_download_is_queued_again_on_restart(tmp_path):
    dl, _, _ = make(tmp_path)
    dl.add("movie", "tt1", "tt1", "Uno")
    dl._jobs["tt1"]["status"] = "downloading"
    dl._save()
    again = downloads.Downloads(tmp_path, resolve=lambda j: ("", ""), publish=lambda e: None, autostart=False)
    assert again.list()[0]["status"] == "queued"
