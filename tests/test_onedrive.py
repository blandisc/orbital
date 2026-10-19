"""Tus videos de OneDrive en Orbital (library/onedrive.py y onedrive_library.py): sin internet ni cuenta de verdad."""

import json

import pytest

from orbital import onedrive_library
from orbital.library import onedrive


class Creds:
    def __init__(self, **values):
        self.values = dict(values)

    def get(self, key):
        return self.values.get(key)

    def set(self, key, value):
        self.values[key] = value


class State:
    def __init__(self):
        self.data = {}

    def settings(self):
        return dict(self.data)

    def set_setting(self, key, value):
        self.data[key] = value


@pytest.mark.parametrize(("name", "expected"), [
    ("Dune Part Two (2024) 2160p.mkv", ("movie", "Dune Part Two", 2024, None, None)),
    ("The.Matrix.1999.1080p.BluRay.x264.mkv", ("movie", "The Matrix", 1999, None, None)),
    ("Blade Runner 2049 (2017).mp4", ("movie", "Blade Runner 2049", 2017, None, None)),  # el año es el último real
    ("2012.mkv", ("movie", "2012", None, None, None)),  # un título, no un año
    ("Severance.S01E03.1080p.WEB-DL.mkv", ("series", "Severance", None, 1, 3)),
    ("Adventure Time 5x12.mp4", ("series", "Adventure Time", None, 5, 12)),
    ("El Chavo [Latino] S02E10.avi", ("series", "El Chavo", None, 2, 10)),
])
def test_a_video_is_recognized_by_its_name(name, expected):
    info = onedrive.parse_name(name)
    assert (info["kind"], info["title"], info["year"], info["season"], info["episode"]) == expected


def test_not_a_video_is_ignored():
    assert onedrive.parse_name("notas.txt") is None and onedrive.parse_name("portada.jpg") is None


class FakeCinemeta:
    def __init__(self):
        self.calls = []

    def search(self, kind, title):
        self.calls.append((kind, title))
        if title == "Dune Part Two":
            return [{"id": "tt0000009", "name": "Dune (otra)", "releaseInfo": "1984"},
                    {"id": "tt15239678", "name": "Dune: Parte dos", "releaseInfo": "2024"}]
        if title == "Severance":
            return [{"id": "tt11280740", "name": "Severance", "releaseInfo": "2022–"}]
        return []


class FakeClient:
    linked = True
    configured = True

    def videos(self, folder):
        return [{"id": "A1", "name": "Dune Part Two (2024) 2160p.mkv", "path": f"{folder}/Dune Part Two (2024) 2160p.mkv", "size": 9,
                 **onedrive.parse_name("Dune Part Two (2024) 2160p.mkv")},
                {"id": "B3", "name": "Severance.S01E03.mkv", "path": f"{folder}/Severance.S01E03.mkv", "size": 5,
                 **onedrive.parse_name("Severance.S01E03.mkv")},
                {"id": "C1", "name": "Video casero.mp4", "path": f"{folder}/Video casero.mp4", "size": 1,
                 **onedrive.parse_name("Video casero.mp4")}]

    def stream_url(self, item_id):
        return f"https://descarga.example/{item_id}"


def test_your_onedrive_videos_get_their_title_and_become_the_recommended_source(tmp_path):
    cine = FakeCinemeta()
    events = []
    lib = onedrive_library.OneDriveLibrary(FakeClient(), cine, State(), tmp_path / "onedrive-library.json", publish=events.append)
    lib.state.data["onedrive_folder"] = "Películas"
    assert lib.scan() == 3
    assert {(t["kind"], t["imdb"]) for t in lib.titles()} == {("movie", "tt15239678"), ("series", "tt11280740")}  # con su año: no la de 1984
    assert {"type": "onedrive-changed"} in events
    movie = lib.source("movie", "tt15239678")
    assert movie.addon == "Tu OneDrive" and movie.index == onedrive_library.INDEX and movie.resolution == "4K" and movie.cached
    assert lib.stream_url(movie) == "https://descarga.example/A1"
    assert lib.source("series", "tt11280740:1:3").stream == {"onedrive": "B3"}
    assert lib.source("series", "tt11280740:1:4") is None  # ese episodio no está en tu OneDrive
    searched = len(cine.calls)
    again = onedrive_library.OneDriveLibrary(FakeClient(), cine, State(), tmp_path / "onedrive-library.json")
    again.state.data["onedrive_folder"] = "Películas"
    assert again.titles() and again.scan() == 3 and len(cine.calls) == searched  # lo ya reconocido no se vuelve a buscar


def test_onedrive_is_not_a_source_anymore_it_plays_from_mi_media(library, monkeypatch):
    """Como el iPhone: tu copia ya no sale en «Fuente»; se ve desde Mi media (play_own), con el respaldo de siempre."""
    import pytest as _pytest

    from orbital import player
    from orbital.library import stremio_api

    lib = onedrive_library.OneDriveLibrary(FakeClient(), FakeCinemeta(), State())
    lib.state.data["onedrive_folder"] = "Películas"
    lib.scan()
    library.watch.onedrive = lib
    with _pytest.raises(stremio_api.StremioError):
        library.watch.stream_sources("movie", "tt15239678")  # sin complementos de Stremio: nada (ya no la tuya)
    played = []
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    monkeypatch.setattr(library.watch, "play_native", lambda *a, **k: played.append((a, k)))
    res = library.watch.play_own("movie", "tt15239678", "tt15239678", "Dune")
    (args, kwargs), = played
    assert args[1] == "https://descarga.example/A1" and kwargs["own"] is True and res["label"] == "Tu copia · 4K"


def test_connecting_onedrive_with_a_code_like_trakt(monkeypatch):
    calls = []

    def fake_http(url, **kwargs):
        calls.append((url, kwargs.get("form")))
        if url.endswith("/devicecode"):
            return 200, {"device_code": "dev", "user_code": "ABCD-EFGH", "verification_uri": "https://www.microsoft.com/link",
                         "interval": 5, "expires_in": 900}
        if kwargs.get("form", {}).get("device_code") == "dev" and len([c for c in calls if c[0].endswith("/token")]) == 1:
            return 400, {"error": "authorization_pending"}
        return 200, {"access_token": "acceso", "refresh_token": "renovar", "expires_in": 3600}

    monkeypatch.setattr(onedrive, "http_json", fake_http)
    creds = Creds(onedrive_client="1a2b3c4d-0000-1111-2222-333344445555")
    client = onedrive.OneDrive(creds)
    code = client.device_code()
    assert code.public()["code"] == "ABCD-EFGH" and code.public()["url"] == "www.microsoft.com/link"
    assert calls[0][1] == {"client_id": "1a2b3c4d-0000-1111-2222-333344445555", "scope": "Files.Read offline_access"}
    assert client.poll_device(code) == "pending"
    assert client.poll_device(code) == "linked" and client.linked
    assert json.loads(creds.values[onedrive.TOKENS_KEY])["refresh_token"] == "renovar"


def test_without_the_app_id_it_says_where_to_add_it():
    with pytest.raises(onedrive.OneDriveError, match="Ajustes › Cuentas"):
        onedrive.OneDrive(Creds()).device_code()


def test_the_folder_you_choose_is_kept_clean():
    class Offline(FakeClient):
        linked = False  # sin cuenta: no se busca en segundo plano
    lib = onedrive_library.OneDriveLibrary(Offline(), FakeCinemeta(), State())
    lib.set_folder("\Películas/../Series/./Drama/")
    assert lib.folder == "Películas/Series/Drama"  # sin «..» ni «.»: solo lo que tú elegiste


def test_mi_media_newest_first_with_what_was_not_recognized(tmp_path):
    class Dated(FakeClient):
        def videos(self, folder):
            found = super().videos(folder)
            for f, added in zip(found, (100.0, 300.0, 200.0), strict=True):
                f["added"] = added
            return found
    lib = onedrive_library.OneDriveLibrary(Dated(), FakeCinemeta(), State())
    lib.state.data["onedrive_folder"] = "Películas"
    lib.scan()
    mine = lib.library()
    assert [t["title"] for t in mine["titles"]] == ["Severance", "Dune: Parte dos"]  # lo último que subiste primero
    assert mine["titles"][0]["episodes"] == 1 and mine["titles"][1]["files"] == 1
    assert [f["id"] for f in mine["unmatched"]] == ["C1"]  # «Sin ficha»: se puede ver tal cual
    assert lib.file_url("C1") == "https://descarga.example/C1"
    assert lib.file_url("ZZ") == "https://descarga.example/ZZ"  # Ver carpetas: cualquier video de tu OneDrive


def test_the_upload_date_comes_from_onedrive():
    assert onedrive.added_at("2026-10-12T03:04:05Z") == 1791774245.0
    assert onedrive.added_at(None) is None and onedrive.added_at("nada") is None


def test_versions_best_first_and_fixing_a_title_by_its_name():
    class Two(FakeClient):
        def videos(self, folder):
            found = super().videos(folder)
            extra = "Dune Part Two (2024) 1080p WEB-DL Atmos Latino.mkv"
            found.append({"id": "A2", "name": extra, "path": extra, "size": 3, **onedrive.parse_name(extra)})
            return found
    lib = onedrive_library.OneDriveLibrary(Two(), FakeCinemeta(), State())
    lib.state.data["onedrive_folder"] = "Películas"
    lib.scan()
    versions = lib.versions("movie", "tt15239678")
    assert [v["id"] for v in versions] == ["A1", "A2"]  # la 4K primero
    assert (versions[1]["resolution"], versions[1]["audio"], versions[1]["languages"]) == ("1080p", "Atmos", ["es"])
    assert lib.source("movie", "tt15239678", "A2").stream == {"onedrive": "A2"}
    assert lib.have("series", "tt11280740") == ["tt11280740:1:3"]
    # «Corregir ficha» de lo que no se reconoció: vale por el nombre (y para la siguiente revisión).
    assert lib.fix(kind="movie", imdb="tt0000777", name="Cumpleaños", year=2019, file_id="C1") == 1
    assert any(t["imdb"] == "tt0000777" for t in lib.library()["titles"]) and not lib.library()["unmatched"]
    lib.scan()
    assert any(t["imdb"] == "tt0000777" for t in lib.library()["titles"])
    with pytest.raises(ValueError):
        lib.fix(kind="movie", imdb="tt1", name="X", file_id="nada")


def test_see_folders_shows_your_onedrive_as_it_is():
    class Folders(FakeClient):
        def children(self, path):
            return [{"name": "Series", "folder": {"childCount": 4}}, {"id": "V1", "name": "Viaje.mp4", "file": {}, "size": 9},
                    {"id": "T1", "name": "notas.txt", "file": {}}]
    lib = onedrive_library.OneDriveLibrary(Folders(), FakeCinemeta(), State())
    lib.state.data["onedrive_folder"] = "Películas"
    out = lib.listing()
    assert out["path"] == "Películas" and out["folders"][0]["path"] == "Películas/Series"
    assert [v["id"] for v in out["videos"]] == ["V1"]  # solo videos
    assert lib.listing("Películas/../Series")["path"] == "Películas/Series"
