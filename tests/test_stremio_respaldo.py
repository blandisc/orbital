"""Stremio solo como respaldo para ver torrents sin Real-Debrid (Fernando, 4 nov 2026: «En la TV deja Streamio como
respaldo, solamente para ver torrents, sin Real Debrit. Ya tampoco para traer complementos»)."""

from orbital import playback, watch
from orbital.library import streams


def torrent(index=0):
    stream = {"name": "Torrentio\n1080p", "title": "Inception.2010.1080p.Latino\n👤 50 💾 2 GB", "infoHash": "a" * 40, "fileIdx": 0}
    return streams.parse(stream, "Torrentio", "https://t/manifest.json", index)


def test_un_torrent_sin_real_debrid_solo_arranca_con_stremio_abierto(monkeypatch):
    src = torrent()
    assert playback.needs_stremio(src.stream) and not playback.needs_stremio({"url": "https://cdn/0.mkv"})
    monkeypatch.setattr(playback, "stremio_server_up", lambda now=None: False)
    assert not watch.ready_now(src)
    monkeypatch.setattr(playback, "stremio_server_up", lambda now=None: True)
    assert watch.ready_now(src)


def test_la_ficha_dice_que_necesita_stremio_abierto(library, monkeypatch):
    w = library.watch
    monkeypatch.setattr(playback, "stremio_server_up", lambda now=None: False)
    monkeypatch.setattr(w, "stream_sources", lambda kind, video_id, prefs=None: [torrent()])
    monkeypatch.setattr(w.rd, "client", lambda: None)
    monkeypatch.setattr(w.rd, "status", lambda video_id: None)
    monkeypatch.setattr(w, "_release_of", lambda kind, meta_id, video_id: None)
    got = w.availability("movie", "tt1375666", "tt1375666")
    assert (got["why"], got["message"]) == ("stremio", "Necesita Stremio abierto")
    monkeypatch.setattr(playback, "stremio_server_up", lambda now=None: True)
    assert w.availability("movie", "tt1375666", "tt1375666")["why"] == "ok"  # abierto: arranca con Stremio


def test_el_servidor_se_pregunta_poco(monkeypatch):
    calls = []

    def connect(address, timeout=0):
        calls.append(address)
        raise OSError("cerrado")

    monkeypatch.setattr(playback.socket, "create_connection", connect)
    monkeypatch.setattr(playback, "_STREMIO_UP", [0.0, 0.0])
    assert not playback.stremio_server_up(now=100.0) and not playback.stremio_server_up(now=105.0)
    assert calls == [("127.0.0.1", 11470)]  # dentro de 10 s no se vuelve a preguntar
