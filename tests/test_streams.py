import base64
import json
import zlib
from urllib.parse import unquote

from orbital.library import streams
from orbital.library.streams import Preferences, parse, player_link, rank

TORRENTIO = "https://torrentio.strem.fun/manifest.json"


def s(name, title, url="https://x/resolve/abc"):
    return {"name": name, "title": title, "url": url}


# Fuentes reales de Torrentio (configurado con language=latino) para Interstellar.
INTERSTELLAR = [
    s("[RD+] Torrentio\n4k HDR", "Interstellar.2014.2160p.x265.hdr.5.1-dual-lat-cinecalidad.my.mkv\n👤 8 💾 11.69 GB ⚙️ Cinecalidad\nDual Audio / 🇲🇽"),
    s("[RD+] Torrentio\n1080p", "Interstellar.2014.1080p.dual-lat.cinecalidad.lol.mp4\n👤 3 💾 3.26 GB ⚙️ Cinecalidad\nDual Audio / 🇲🇽"),
    s("[RD+] Torrentio\n1080p", "Interestelar (2014) Imax 1080p WEBDL LAT - ZeiZ\n👤 2 💾 12.07 GB ⚙️ EXT\n🇲🇽"),
    s("[RD+] Torrentio\n1080p DV | HDR", "Interstellar.2014.PROPER.IMAX.1080p.UHD.BluRay.x265.HDR.DV.DD+5.1.Dual.YG⭐\n👤 530 💾 4.21 GB ⚙️ TorrentGalaxy\nDual Audio / 🇪🇸"),
    s("[RD+] Torrentio\n4k DV | HDR10+", "Interstellar 2014 2160p PROPER IMAX REMUX DV HDR10+ TrueHD 7.1 Atmos-jennaortegaUHD\n👤 271 💾 95.63 GB ⚙️ TorrentGalaxy"),
    s("[RD+] Torrentio\n4k HDR", "Interstellar.2014.2160p.UHD.BluRay.x265.10bit.HDR.DTS-HD.MA.5.1-TERMiNAL\n👤 182 💾 33.34 GB ⚙️ RARBG"),
    s("[RD+] Torrentio\n1080p", "Interstellar.2014.1080p.BluRay.x264.DTS-WiKi\n👤 120 💾 13.2 GB ⚙️ RARBG"),
    s("[RD+] Torrentio\n1080p", "Interstellar.2014.IMAX.1080p.BluRay.x265-RARBG\n👤 300 💾 3.1 GB ⚙️ RARBG"),
    s("[RD download] Torrentio\n4k DV", "Interstellar.2014.2160p.WEB-DL.DTS-HD.MA.5.1.DV.MKV.x265-NOSiViD\n👤 0 💾 33.58 GB ⚙️ RARBG"),
    s("[RD download] Torrentio\n4k", "Interstellar.Trailer.2014.4K.DCPrip.LAMPA\n👤 0 💾 1.5 GB ⚙️ MagnetDL"),
]


def parsed(items):
    return [parse(x, "Torrentio RD", TORRENTIO, i) for i, x in enumerate(items)]


def test_parse_reads_quality_size_seeders_languages():
    lat, _, _, dv, remux, *_ = parsed(INTERSTELLAR)
    assert lat.resolution == "4K" and lat.hdr == ["HDR"] and lat.cached and lat.size == 11_690_000_000
    assert lat.languages == ["es", "en"] and lat.seeders == 8 and lat.site == "Cinecalidad"
    assert dv.hdr == ["DV", "HDR"] and dv.resolution == "1080p"
    assert remux.hdr == ["DV", "HDR10+"] and "REMUX" in remux.tags and remux.languages == ["en"]
    assert "Tráiler" in parsed(INTERSTELLAR)[-1].tags and not parsed(INTERSTELLAR)[-1].cached


def test_rank_english_1080p_skips_latino_remux_dv_and_trailer():
    best = rank(parsed(INTERSTELLAR), Preferences(audio="en", quality="1080p"), "movie")
    assert best[0].release == "Interstellar.2014.IMAX.1080p.BluRay.x265-RARBG"  # inglés, 1080p, 3 GB, lista
    assert best[-1].tags == ["Tráiler"] or "Tráiler" in best[-1].tags
    top3 = [b.release for b in best[:3]]
    assert not any("lat" in r.lower() or "LAT" in r for r in top3)


def test_rank_4k_preference_for_the_tv():
    best = rank(parsed(INTERSTELLAR), Preferences(audio="en", quality="4K"), "movie")
    assert best[0].resolution == "4K" and best[0].release.endswith("TERMiNAL")  # 4K HDR, inglés, sin el REMUX de 95 GB


def test_public_view_never_includes_urls():
    src = parsed(INTERSTELLAR)[0]
    assert "url" not in json.dumps(src.public()) and "resolve" not in json.dumps(src.public())


def test_player_link_matches_stremio_core_format():
    src = parsed(INTERSTELLAR)[7]
    link = player_link(src, "https://v3-cinemeta.strem.io/manifest.json", "movie", "tt0816692", "tt0816692")
    assert link.startswith("stremio:///player/")
    encoded, stream_tp, meta_tp, kind, meta_id, video = link.removeprefix("stremio:///player/").split("/")
    assert json.loads(zlib.decompress(base64.b64decode(unquote(encoded)))) == src.stream  # Stream::decode
    assert unquote(stream_tp) == TORRENTIO and unquote(meta_tp).startswith("https://v3-cinemeta")
    assert (kind, meta_id, video) == ("movie", "tt0816692", "tt0816692")


def test_finder_asks_stream_addons_in_parallel_and_caches(monkeypatch):
    class Client:
        calls = 0

        def request(self, method, params):
            Client.calls += 1
            return {"addons": [
                {"transportUrl": TORRENTIO, "manifest": {"name": "Torrentio RD", "resources": ["stream"], "types": ["movie"]}},
                {"transportUrl": "https://cat/manifest.json", "manifest": {"name": "Cinemeta", "resources": ["catalog"]}},
            ]}

    fetched = []
    monkeypatch.setattr(streams.StreamFinder, "_fetch",
                        lambda self, addon, kind, vid: fetched.append(addon["name"]) or INTERSTELLAR)
    finder = streams.StreamFinder(Client())
    found = finder.find("key", "movie", "tt0816692", Preferences())
    assert fetched == ["Torrentio RD"] and len(found) == len(INTERSTELLAR)  # Cinemeta no da fuentes
    finder.find("key", "movie", "tt0816692", Preferences())
    assert fetched == ["Torrentio RD"] and Client.calls == 1  # en caché
    assert finder.get("movie", "tt0816692", Preferences(), found[0].index) is found[0]
