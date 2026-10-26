"""Subtítulos de internet como los ve el iPhone (orbital/library/subtitles.py)."""

import struct

from orbital.library import subtitles as subs


def test_language_tags_become_iso_codes():
    assert [subs.language(x) for x in ("spa", "es-419", "pob", "English", "fre", "", None, "xx-yy", "klingon")] == \
        ["es", "es", "pt", "en", "fr", None, None, "xx", None]


def test_release_traits_and_match():
    mine = subs.ReleaseTraits.parse("The.Office.S02E05.720p.WEB-DL.DD5.1-NTb.mkv")
    assert mine == subs.ReleaseTraits("WEB-DL", "ntb")
    assert mine.match(subs.ReleaseTraits.parse("The.Office.S02E05.1080p.WEB-DL-NTb")) == 3
    assert mine.match(subs.ReleaseTraits.parse("The.Office.S02E05.WEB-DL-FLUX")) == 1
    assert mine.match(subs.ReleaseTraits.parse("The.Office.S02E05.BluRay-DEMAND")) == 0
    assert subs.ReleaseTraits.parse(None) == subs.ReleaseTraits()
    assert [subs.badge(m) for m in (3, 2, 1, 0)] == ["Hecho para tu copia", "Hecho para tu copia", "Misma versión", ""]


def test_ranked_hides_sdh_and_forced_and_puts_your_copy_first():
    options = subs.parse_options([
        {"url": "https://a/1", "lang": "spa", "release": "X.BluRay-AAA", "downloads": 900},
        {"url": "https://a/2", "lang": "spa", "release": "X.WEB-DL-NTb", "downloads": 5},
        {"url": "https://a/3", "lang": "spa", "release": "X.WEB-DL-NTb", "hearing_impaired": True},
        {"url": "https://a/4", "lang": "spa", "release": "X.Forced.WEB-DL-NTb"},
        {"url": "https://a/5", "lang": "eng", "release": "X.WEB-DL-NTb"},
        {"url": "ftp://a/6", "lang": "spa"}, {"lang": "spa"}, "basura",
    ], "OpenSubtitles")
    assert len(options) == 5 and options[0]["source"] == "OpenSubtitles"
    assert [o["url"] for o in subs.ranked(options, "es", "X.2160p.WEB-DL-NTb.mkv")] == ["https://a/2", "https://a/1"]
    assert [o["url"] for o in subs.ranked(options, "es", None)] == ["https://a/1", "https://a/2"]  # sin copia: descargas


def test_opensubtitles_fingerprint():
    head = struct.pack("<Q", 1) * (subs.CHUNK // 8)
    tail = struct.pack("<Q", 2) * (subs.CHUNK // 8)
    size = 10 * subs.CHUNK
    assert subs.fingerprint(head, tail, size) == (f"{size + 3 * (subs.CHUNK // 8):016x}", size)
    assert subs.fingerprint(b"x", tail, size) is None


def test_other_edition_only_when_the_subtitle_outlasts_the_video():
    assert subs.last_cue("1\n00:00:01,000 --> 00:00:02,000\nHola\n\n2\n01:44:10,500 --> 01:44:12,250\nAdiós\n") == 6252.25
    assert subs.edition_speed(6000, 6252.25) == subs.PAL_SPEED
    assert subs.edition_speed(6000, 5900) is None  # termina antes: créditos largos, no se toca
    assert subs.edition_speed(300, 400) is None  # muy corto para saber


def test_finder_asks_your_addons_plus_opensubtitles_with_the_fingerprint(monkeypatch):
    from orbital.library import addons, streams

    class Client:
        def request(self, method, params):
            return {"addons": [{"transportUrl": "https://mysubs/manifest.json",
                                "manifest": {"name": "Subdivx", "resources": ["subtitles"]}}]}

    asked = []

    def fake_fetch(url, timeout=None):
        asked.append(url)
        if url.startswith("https://mysubs"):
            return {"subtitles": [{"url": "https://s/1.srt", "lang": "spa", "release": "X.WEB-DL-NTb"}]}
        return {"subtitles": [{"url": "https://s/1.srt", "lang": "spa"},
                              {"url": "https://s/2.srt", "lang": "eng", "downloads": 7}]}

    monkeypatch.setattr(addons, "fetch_json", fake_fetch)
    finder = streams.StreamFinder(addons.AddonRegistry(Client(), auth=lambda: "key"))
    found = finder.subtitle_options("movie", "tt1160419", ("00ff", 1234))
    assert sorted(asked) == ["https://mysubs/subtitles/movie/tt1160419/videoHash=00ff&videoSize=1234.json",
                             f"{subs.BUILTIN}/subtitles/movie/tt1160419/videoHash=00ff&videoSize=1234.json"]
    assert [o["url"] for o in found] == ["https://s/1.srt", "https://s/2.srt"]  # sin repetidos

    def offline(url, timeout=None):
        raise OSError("sin red")

    monkeypatch.setattr(addons, "fetch_json", offline)
    assert finder.subtitle_options("movie", "tt1160419") is None  # sin internet ≠ no hay
