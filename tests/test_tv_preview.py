from __future__ import annotations

from orbital.library import iptv_preview as ip
from orbital.library.iptv import Channel

MASTER = """#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
hd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=480x270
sd/index.m3u8
"""
MEDIA = """#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:6.0,
seg1.ts
#EXTINF:6.0,
https://cdn.example/seg2.ts
"""


def test_the_lowest_quality_is_picked_and_every_piece_goes_through_orbital(monkeypatch):
    asked: list[str] = []

    def fake(channel, url, limit):
        asked.append(url)
        if url.endswith("master.m3u8"):
            return MASTER.encode(), url, "application/vnd.apple.mpegurl", True
        return MEDIA.encode(), url, "application/vnd.apple.mpegurl", True

    monkeypatch.setattr(ip, "fetch", fake)
    channel = Channel("X.mx@SD", "X", "https://tv.example/live/master.m3u8", user_agent="UA")
    text = ip.Previews().playlist(channel)
    assert asked == ["https://tv.example/live/master.m3u8", "https://tv.example/live/sd/index.m3u8"]
    assert "tv.example/live/sd/seg1.ts" not in text.replace("%3A", ":").replace("%2F", "/").split("u=")[0]
    lines = [line for line in text.splitlines() if line and not line.startswith("#")]
    assert all(line.startswith("preview-seg?c=X.mx%40SD&u=") for line in lines)
    assert 'URI="preview-seg?' in text
    # Las firmas sirven solo para esa dirección y ese canal.
    url = "https://tv.example/live/sd/seg1.ts"
    assert ip.valid("X.mx@SD", url, ip.sign("X.mx@SD", url))
    assert not ip.valid("Otro", url, ip.sign("X.mx@SD", url))
    assert not ip.valid("X.mx@SD", "https://evil/", ip.sign("X.mx@SD", url))


def test_api_refuses_unsigned_pieces_and_unknown_channels(make_client):
    c = make_client()
    assert c.get("/api/tv/preview-seg", params={"c": "X", "u": "https://evil/", "s": "nada"}).status_code == 403
    assert c.get("/api/tv/preview.m3u8", params={"id": "no-existe"}).status_code == 404


def test_a_channel_that_allows_it_is_read_directly_by_the_tv(monkeypatch):
    monkeypatch.setattr(ip, "fetch", lambda channel, url, limit: (MEDIA.encode(), url, "application/vnd.apple.mpegurl", True))
    try:
        ip.Previews().playlist(Channel("Y.mx@SD", "Y", "https://tv.example/live/index.m3u8"))
        raise AssertionError("debía mandarla directo")
    except ip.PreviewRedirect as go:
        assert go.url == "https://tv.example/live/index.m3u8"
    # Con cabeceras propias (la página no puede mandarlas), aunque dé permiso, pasa por Orbital.
    text = ip.Previews().playlist(Channel("Z.mx@SD", "Z", "https://tv.example/live/index.m3u8", referrer="https://tv.example/"))
    assert "preview-seg" in text
