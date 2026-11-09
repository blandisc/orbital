"""La API oficial de OpenSubtitles en la TV, con respuestas de su documentación (sin red ni cuenta de verdad)."""

import json

import pytest

from orbital.library import opensubtitles as osub

SEARCH = {"total_count": 3, "data": [
    {"id": "1", "attributes": {"language": "es", "download_count": 50, "release": "Show.S01E05.720p.WEB",
                               "moviehash_match": False, "files": [{"file_id": 111}]}},
    {"id": "2", "attributes": {"language": "es", "download_count": 9, "moviehash_match": True, "files": [{"file_id": 222}]}},
    {"id": "3", "attributes": {"language": "en", "download_count": 900, "files": []}},
]}


class Secrets:
    def __init__(self, **values):
        self.values = dict(values)

    def get(self, key):
        return self.values.get(key)

    def set(self, key, value):
        if value is None:
            self.values.pop(key, None)
        else:
            self.values[key] = value


class FakeHTTP:
    def __init__(self, replies):
        self.replies = replies
        self.calls = []

    def __call__(self, url, method="GET", headers=None, body=None, timeout=10):
        self.calls.append((method, url, headers or {}, body))
        for prefix, reply in self.replies.items():
            if url.startswith(prefix):
                return reply
        return 404, None


def client(replies, **secrets):
    http = FakeHTTP(replies)
    return osub.OpenSubtitles(Secrets(opensubtitles_api_key="app-key", **secrets), languages=lambda: ["es", "en"], http=http), http


def test_query_sorted_and_series_episode():
    items = osub.query("tt0096697:3:7", "abc", ["es-419", "en"])
    assert [k for k, _ in items] == ["episode_number", "languages", "moviehash", "order_by", "parent_imdb_id", "season_number"]
    assert dict(items)["parent_imdb_id"] == "96697"
    assert dict(items)["languages"] == "en,es"
    assert osub.query("kitsu:1", None, []) is None


def test_parse_exact_copy_first_and_skips_without_files():
    options = osub.parse(SEARCH)
    assert [o["file_id"] for o in options] == ["222", "111"]
    assert options[0]["url"] == "opensubtitles://file/222" and options[0]["exact"]


def test_search_sends_key_and_is_cached(monkeypatch):
    monkeypatch.delenv(osub.KEY_ENV, raising=False)
    api, http = client({f"{osub.HOST}/subtitles": (200, SEARCH)})
    assert len(api.search("tt1:1:5")) == 2
    api.search("tt1:1:5")
    assert len(http.calls) == 1
    assert http.calls[0][2]["Api-Key"] == "app-key"
    assert http.calls[0][2]["User-Agent"].startswith("Orbital v")


def test_without_key_api_is_off(monkeypatch):
    monkeypatch.delenv(osub.KEY_ENV, raising=False)
    api = osub.OpenSubtitles(Secrets(), http=FakeHTTP({}))
    assert not api.available and api.search("tt1") is None
    with pytest.raises(osub.OpenSubtitlesError):
        api.login("fer", "x")


def test_login_keeps_token_not_password_and_download_uses_it(monkeypatch):
    monkeypatch.delenv(osub.KEY_ENV, raising=False)
    api, http = client({f"{osub.HOST}/login": (200, {"token": "jwt", "base_url": "api.opensubtitles.com",
                                                       "user": {"allowed_downloads": 20}}),
                        f"{osub.HOST}/download": (200, {"link": "https://dl.opensubtitles.com/x.srt", "remaining": 19})})
    status = api.login(" fer ", "secreta")
    assert status["connected"] and status["username"] == "fer" and "token" not in status
    assert "secreta" not in api.credentials.get(osub.ACCOUNT_SECRET)
    assert api.resolve("opensubtitles://file/222") == "https://dl.opensubtitles.com/x.srt"
    assert http.calls[-1][2]["Authorization"] == "Bearer jwt" and http.calls[-1][3] == {"file_id": 222}
    assert api.status()["remaining"] == 19
    api.resolve("opensubtitles://file/222")
    assert sum(1 for c in http.calls if c[1].endswith("/download")) == 1  # no gasta cuota dos veces


def test_download_without_account_or_quota(monkeypatch):
    monkeypatch.delenv(osub.KEY_ENV, raising=False)
    api, _ = client({f"{osub.HOST}/download": (406, {"message": "quota"})})
    with pytest.raises(osub.OpenSubtitlesError) as exc:
        api.resolve("opensubtitles://file/1")
    assert exc.value.code == "not_connected"
    api.adopt({"username": "fer", "token": "jwt"})
    with pytest.raises(osub.OpenSubtitlesError) as exc:
        api.resolve("opensubtitles://file/1")
    assert exc.value.code == "quota"
    assert json.loads(api.credentials.get(osub.ACCOUNT_SECRET))["username"] == "fer"


def test_merge_drops_addon_copy_of_same_file():
    official = osub.parse(SEARCH)
    addon = [{"url": "https://os.strem.io/222.srt", "lang": "spa", "source": "OpenSubtitles", "file_id": "222"},
             {"url": "https://os.strem.io/333.srt", "lang": "spa", "source": "OpenSubtitles", "file_id": "333"}]
    assert [o.get("file_id") for o in osub.merge(official, addon)] == ["222", "111", "333"]


def test_resolve_passes_normal_urls():
    assert osub.resolve("https://s/1.srt") == "https://s/1.srt"
