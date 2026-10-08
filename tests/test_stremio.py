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


def test_parse_library_follows_stremio_rules():
    items = stremio_api.parse_library(LIBRARY)
    assert [w.name for w in items] == ["Game of Thrones", "Interstellar", "Anime temporal", "The Office", "Otro"]
    got, interstellar, anime, office, other = items
    assert got.in_continue and got.episode == (3, 9) and got.progress == pytest.approx(1 / 3)
    assert got.deep_link == "stremio:///detail/series/tt0944947/tt0944947:3:9"
    assert got.background == "https://images.metahub.space/background/medium/tt0944947/img"
    assert interstellar.deep_link == "stremio:///detail/movie/tt0816692" and interstellar.episode == (None, None)
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
    assert linked.launcher.opened[-1] == "stremio:///detail/movie/tt0816692"
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


def test_voice_continue_and_search(linked):
    voice = VoiceController(linked)
    r = voice.handle_text("sigue viendo")
    assert r.ok and r.speech == "Continuando Game of Thrones, T3 E9."
    assert linked.launcher.opened[-1].endswith("tt0944947:3:9")
    assert voice.handle_text("continua interstellar").speech == "Continuando Interstellar, Película."
    # Buscar algo que ya está en tu biblioteca abre su ficha, no la búsqueda.
    assert voice.handle_text("busca the office en stremio").speech == "Abriendo The Office en Stremio."
    assert voice.handle_text("busca dune en stremio").speech == "Buscando dune en Stremio."
    assert linked.launcher.opened[-1] == "stremio:///search?search=dune"
    # "abre X" sirve también para series, pero los juegos tienen prioridad.
    assert voice.handle_text("abre the office").speech == "Abriendo The Office en Stremio."


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
