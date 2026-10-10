import os
import time

import pytest

from orbital.catalog import STREMIO_KEY, Catalog
from orbital.config import parse_config
from orbital.credentials import Credentials
from orbital.library import stremio_api
from orbital.voice import VoiceController

from conftest import FakeLauncher

# Formato real de LibraryItem (stremio-core/src/types/library/library_item.rs)
LIBRARY = [
    {"_id": "tt0944947", "name": "Game of Thrones", "type": "series", "poster": "https://p/got.jpg",
     "removed": False, "temp": False,
     "state": {"timeOffset": 1200000, "duration": 3600000, "video_id": "tt0944947:3:9",
               "lastWatched": "2026-10-08T20:00:00Z", "timeWatched": 0, "flaggedWatched": 0, "timesWatched": 0}},
    {"_id": "tt0816692", "name": "Interstellar", "type": "movie", "poster": "https://p/int.jpg",
     "removed": False, "temp": False,
     "state": {"timeOffset": 5400000, "duration": 10140000, "video_id": "tt0816692",
               "lastWatched": "2026-10-07T21:00:00Z"}},
    {"_id": "tt0386676", "name": "The Office", "type": "series", "removed": False, "temp": False,
     "state": {"timeOffset": 0, "duration": 0, "lastWatched": "2026-01-01T00:00:00Z"}},
    {"_id": "tt0111161", "name": "Borrada", "type": "movie", "removed": True, "temp": False,
     "state": {"timeOffset": 100, "duration": 1000}},
    {"_id": "kitsu:1", "name": "Anime temporal", "type": "series", "removed": True, "temp": True,
     "state": {"timeOffset": 10, "duration": 100, "video_id": "kitsu:1:7", "lastWatched": "2026-10-01T00:00:00Z"}},
    {"_id": "local:x", "name": "Otro", "type": "other", "removed": False, "temp": False, "state": {"timeOffset": 5}},
]


class FakeStremio:
    def __init__(self, items=LIBRARY):
        self.items = items
        self.fail = False
        self.calls = 0

    def library(self, auth_key):
        self.calls += 1
        if self.fail or auth_key != "clave-buena":
            raise stremio_api.StremioError("Session not found")
        return self.items

    def login(self, email, password):
        return "clave-buena"

    def library_item(self, auth_key, item_id):
        return next((i for i in self.items if i["_id"] == item_id), None)

    def save_library_item(self, auth_key, item):
        self.saved = getattr(self, "saved", []) + [item]


def test_parse_library_follows_stremio_rules():
    items = stremio_api.parse_library(LIBRARY)
    assert [w.name for w in items] == ["Game of Thrones", "Interstellar", "Anime temporal", "The Office", "Otro"]
    got, interstellar, anime, office, other = items
    assert got.in_continue and got.episode == (3, 9) and got.progress == pytest.approx(1 / 3)
    assert got.deep_link == "stremio:///detail/series/tt0944947/tt0944947:3:9?autoPlay=true"
    assert got.background == "https://images.metahub.space/background/medium/tt0944947/img"
    assert interstellar.deep_link == "stremio:///detail/movie/tt0816692/tt0816692?autoPlay=true" and interstellar.episode == (None, None)
    assert anime.in_continue and anime.episode == (None, 7) and anime.background is None
    assert not office.in_continue and not other.in_continue  # sin progreso / tipo "other"


@pytest.fixture
def linked(tmp_path):
    cfg = parse_config({"steam": {"enabled": False}, "esde": {"enabled": False}, "detect": {"enabled": False},
                        "stremio": {"executable": "stremio-test"}})
    creds = Credentials(tmp_path / "secrets.json")
    fake = FakeStremio()
    cat = Catalog(cfg, FakeLauncher(), credentials=creds, stremio_client=fake)
    cat.link_stremio("clave-buena")
    cat.refresh()
    for _ in range(50):  # refresh() relanza la descarga en segundo plano
        if fake.calls >= 3:
            break
        time.sleep(0.02)
    return cat


def test_link_stores_key_privately(tmp_path):
    cfg = parse_config({"detect": {"enabled": False}})
    creds = Credentials(tmp_path / "secrets.json")
    cat = Catalog(cfg, FakeLauncher(), credentials=creds, stremio_client=FakeStremio())
    with pytest.raises(stremio_api.StremioError):
        cat.link_stremio("clave-mala")
    assert not cat.stremio_linked
    cat.link_stremio("clave-buena")
    assert Credentials(tmp_path / "secrets.json").get(STREMIO_KEY) == "clave-buena"
    if os.name != "nt":
        assert oct((tmp_path / "secrets.json").stat().st_mode & 0o777) == "0o600"
    cat.unlink_stremio()
    assert not cat.stremio_linked and cat.stremio_library() == []


def test_continue_row(linked):
    rows = {r["id"]: r for r in linked.grouped()}
    row = rows["continue"]
    assert row["title"] == "Seguir viendo"
    assert [i["title"] for i in row["items"]] == ["Game of Thrones", "Interstellar", "Anime temporal"]
    got = row["items"][0]
    assert got["subtitle"] == "Stremio · T3 E9" and got["progress"] == pytest.approx(1 / 3)
    assert got["hero"].startswith("https://images.metahub.space") and got["last_played"] > 0
    assert "The Office" not in [i["title"] for r in rows.values() for i in r["items"]]  # sin fila propia
    assert "recent" not in rows  # abrir algo de Stremio no ensucia "Jugado recientemente"
    linked.launch("stremio:tt0816692")
    # Con Stremio instalado se le pasa el enlace como argumento; sin él, se abre el URI.
    assert sent(linked) == "stremio:///detail/movie/tt0816692/tt0816692?autoPlay=true"
    assert "recent" not in {r["id"] for r in linked.grouped()}


def test_failure_keeps_last_list_and_notifies_changes(linked):
    events = []
    linked.listeners.append(events.append)
    linked.stremio_client.fail = True
    assert linked.refresh_stremio() is False and linked.stremio_error == "Session not found"
    assert len(linked.grouped_items("continue")) == 3
    linked.stremio_client.fail = False
    linked.stremio_client.items = LIBRARY[:1]
    assert linked.refresh_stremio() is True
    assert events == [{"type": "library-changed"}]
    assert [i.title for i in linked.grouped_items("continue")] == ["Game of Thrones"]


def sent(catalog) -> str:
    """Último enlace que se mandó a Stremio: como argumento del ejecutable o como URI."""
    ran = [argv[-1] for argv in catalog.launcher.ran if argv and str(argv[-1]).startswith("stremio:")]
    return ran[-1] if ran else catalog.launcher.opened[-1]


def test_voice_continue_and_search(linked):
    voice = VoiceController(linked)
    r = voice.handle_text("sigue viendo")
    assert r.ok and r.speech == "Continuando Game of Thrones, T3 E9."
    assert sent(linked).endswith("tt0944947:3:9?autoPlay=true")
    assert voice.handle_text("continua interstellar").speech == "Continuando Interstellar, Película."
    # Buscar algo que ya está en tu biblioteca lo abre (una serie sin episodio pendiente: sus episodios).
    office = voice.handle_text("busca the office en stremio")
    assert office.speech == "Abriendo The Office. Elige el episodio."
    assert office.events == [{"type": "reload", "view": {"serie": "tt0386676"}}]
    # Sin coincidencia exacta: la búsqueda de Orbital ya escrita, para elegir con el mando.
    result = voice.handle_text("busca dune en stremio")
    assert result.speech == "Buscando dune. Elige con el control."
    assert result.events == [{"type": "reload", "view": {"buscar": "dune"}}]
    # "abre X" sirve también para series, pero los juegos tienen prioridad.
    assert voice.handle_text("abre the office").speech == "Abriendo The Office. Elige el episodio."


def test_voice_without_stremio_account(library):
    assert "orbital stremio login" in VoiceController(library).handle_text("sigue viendo").speech


def test_voice_launch_with_runner(tmp_path):
    from test_esde import GAMELIST  # noqa: F401  (misma estructura de ES-DE)
    from orbital.library.models import LibraryItem, Runner
    cfg = parse_config({"detect": {"enabled": False}, "steam": {"enabled": False}, "esde": {"enabled": False}})
    cat = Catalog(cfg, FakeLauncher())
    zelda = LibraryItem(id="emu:switch:1", title="The Legend of Zelda: Tears of the Kingdom", category="emulators",
                        source="switch", runners=[Runner("switch", "Ryujinx", ["ryujinx", "z"]),
                                                  Runner("switch-eden", "Eden", ["eden", "z"])],
                        default_runner="switch")
    cat._items = {zelda.id: zelda}
    voice = VoiceController(cat)
    assert voice.handle_text("abre zelda con eden").speech == f"Abriendo {zelda.title} con eden."
    assert cat.launcher.ran[-1][0] == "eden"
    assert voice.handle_text("abre zelda").speech == f"Abriendo {zelda.title}."
    assert cat.launcher.ran[-1][0] == "ryujinx"
    assert not voice.handle_text("abre zelda con dolphin").ok


def test_cinemeta_search_keeps_relevance_and_promotes_exact():
    from orbital.library import cinemeta

    # "ofice": Cinemeta ya pone The Office primero; "Oficer" empieza igual pero no debe ganarle.
    series = [{"id": "tt3", "name": "The Office", "releaseInfo": "2005"}, {"id": "tt9", "name": "Oficer"},
              {"id": "tt3", "name": "The Office"}]
    movies = [{"id": "tt1", "name": "Bad Day at the Office"}]
    results = cinemeta.search_results("ofice", movies, series)
    assert [r["title"] for r in results] == ["The Office", "Bad Day at the Office", "Oficer"]  # sin duplicados
    exact = cinemeta.search_results("oficer", movies, series)
    assert exact[0]["title"] == "Oficer"  # coincidencia exacta: primero
    office = results[0]
    assert office["kind"] == "series" and office["meta_id"] == "tt3" and office["subtitle"] == "Serie · 2005"


def test_seasons_put_specials_last_and_play_links():
    from orbital.library import cinemeta

    meta = {"videos": [
        {"id": "tt3:2:1", "season": 2, "episode": 1, "name": "B"},
        {"id": "tt3:0:1", "season": 0, "episode": 1, "name": "Especial"},
        {"id": "tt3:1:2", "season": 1, "episode": 2, "name": "A2"},
        {"id": "tt3:1:1", "season": 1, "episode": 1, "name": "A1"},
    ]}
    s = cinemeta.seasons(meta)
    assert [x["label"] for x in s] == ["Temporada 1", "Temporada 2", "Especiales"]
    assert [e["title"] for e in s[0]["episodes"]] == ["A1", "A2"]
    assert cinemeta.play_link("series", "tt3", "tt3:1:2") == "stremio:///detail/series/tt3/tt3:1:2?autoPlay=true"
    assert cinemeta.play_link("movie", "tt1") == "stremio:///detail/movie/tt1/tt1?autoPlay=true"


def test_voice_exact_title_plays_movie_or_opens_episodes(linked, monkeypatch):
    from orbital.library import cinemeta

    catalog = {"movie": [{"id": "tt15239678", "name": "Dune: Part Two"}],
               "series": [{"id": "tt0386676", "name": "The Office", "releaseInfo": "2005"}]}
    monkeypatch.setattr(cinemeta.Cinemeta, "search", lambda self, kind, q: catalog[kind])
    voice = VoiceController(linked)
    assert voice.handle_text("busca dune part two en stremio").speech == "Poniendo Dune: Part Two."
    assert sent(linked) == "stremio:///detail/movie/tt15239678/tt15239678?autoPlay=true"
    # "abre X" que no es juego ni está en tu biblioteca: si es una serie, sus episodios en Orbital.
    linked.unlink_stremio()
    result = voice.handle_text("abre the office")
    assert result.speech == "Abriendo The Office. Elige el episodio."
    assert result.events == [{"type": "reload", "view": {"serie": "tt0386676"}}]


def test_sources_and_play_chosen_source_opens_player(linked, monkeypatch):
    from fastapi.testclient import TestClient

    from orbital.library import streams
    from orbital.server import create_app

    raw = [{"name": "[RD+] Torrentio\n1080p", "title": "Show.S01E01.1080p.WEB\n👤 50 💾 1.2 GB ⚙️ X",
            "url": "https://torrentio/resolve/realdebrid/SECRETKEY/abc"}]
    monkeypatch.setattr(streams.StreamFinder, "addons",
                        lambda self, key: [{"name": "Torrentio RD", "url": "https://torrentio/manifest.json", "types": ["series"]}])
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, kind, vid: raw)
    with TestClient(create_app(linked.config, linked), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)) as c:
        data = c.get("/api/stremio/sources", params={"kind": "series", "id": "tt1", "video": "tt1:1:1"}).json()
        assert data["sources"][0]["resolution"] == "1080p" and "SECRETKEY" not in str(data)  # nada de claves
        assert c.post("/api/stremio/play", json={"kind": "series", "id": "tt1", "video_id": "tt1:1:1",
                                                 "source": data["sources"][0]["id"], "title": "Show"}).json() == {"ok": True}
    assert sent(linked).startswith("stremio:///player/")  # directo al reproductor, sin la lista de Stremio


def test_chosen_source_plays_in_orbital_player_from_where_you_left(linked, monkeypatch):
    from orbital import player
    from orbital.library import streams

    raw = [{"name": "[RD+] Torrentio\n1080p", "title": "Interstellar.2014.1080p\n👤 50 💾 9 GB",
            "url": "https://torrentio/resolve/realdebrid/SECRETKEY/abc"}]
    monkeypatch.setattr(streams.StreamFinder, "addons",
                        lambda self, key: [{"name": "Torrentio RD", "url": "https://torrentio/manifest.json", "types": []}])
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, kind, vid: raw)
    monkeypatch.setattr(player, "find_mpv", lambda: "C:/mpv/mpv.exe")
    played = []

    class FakePlayer:
        def play(self, run, exe, url, title, meta, **options):
            played.append((exe, url, title, meta, options))
            return run([exe, url])

    linked.player = FakePlayer()
    src = linked.stream_sources("movie", "tt0816692")[0]
    assert linked.play_source("movie", "tt0816692", "tt0816692", src.index, "Interstellar") == "orbital"
    exe, url, title, meta, options = played[0]
    assert url.endswith("SECRETKEY/abc") and meta["video_id"] == "tt0816692"
    assert options["start"] == 5400 and options["audio"] == "en" and options["subtitles"] == "en"
    assert linked.launcher.current["id"] == "media:player" and linked.launcher.current["runner"] == "Reproductor"
    # Configurado para usar el reproductor de Stremio: como antes.
    linked.config.stremio.player = "stremio"
    linked.play_source("movie", "tt0816692", "tt0816692", src.index, "Interstellar")
    assert sent(linked).startswith("stremio:///player/")


def test_player_saves_progress_to_stremio(linked):
    linked._player_finished({"kind": "movie", "meta_id": "tt0816692", "video_id": "tt0816692", "title": "Interstellar"},
                            position=6000, duration=10140, watched=600)
    saved = linked.stremio_client.saved[-1]
    assert saved["_id"] == "tt0816692" and saved["state"]["timeOffset"] == 6_000_000
    assert saved["poster"] == "https://p/int.jpg"  # el resto del item, tal cual
    linked._player_finished({"kind": "movie", "meta_id": "tt0816692", "video_id": "tt0816692", "title": "x"},
                            position=30, duration=10140, watched=5)
    assert len(linked.stremio_client.saved) == 1  # abrir y cerrar sin ver nada no toca tu biblioteca
