"""Lo que encontraron los agentes que intentaron romper Orbital: que no vuelva a pasar."""

import http.client
import json

import pytest

from orbital import capture, net, quick
from orbital.library import cinemeta, media, stremio_api
from orbital.state import State
from orbital.voice import VoiceController


def test_truncated_images_have_no_size(tmp_path):
    for name, data in [("a.png", b"\x89PNG\r\n\x1a\n"), ("b.jpg", b"\xff\xd8\xff\xc0\x00"), ("c.webp", b"RIFF\x00\x00\x00\x00WEBPVP8 ")]:
        path = tmp_path / name
        path.write_bytes(data)
        assert media.image_size(path) is None  # antes: struct.error y el escaneo entero se caía


def test_one_bad_stremio_item_is_skipped():
    good = {"_id": "tt1", "name": "Bien", "type": "movie", "state": {"timeOffset": 1000, "duration": 6000}}
    bad = [{"_id": "tt2", "name": "Mal", "type": "movie", "state": {"timeOffset": "abc"}},
           {"_id": "tt3", "name": "Fecha", "type": "movie", "state": {"lastWatched": "0001-01-01T00:00:00Z"}},
           "no es un objeto", None]
    items = stremio_api.parse_library([good, *bad])
    assert "tt1" in [w.id for w in items]  # el bueno sobrevive aunque haya basura alrededor


def test_cinemeta_odd_shapes_do_not_crash():
    meta = {"genres": 5, "videos": [None, "x", {"season": 1, "episode": 1, "id": "v1", "name": 7, "overview": 5}],
            "cast": 5, "links": "no", "logo": 3}
    assert cinemeta.describe_meta(meta)["genres"] == [] and cinemeta.describe_meta(meta)["logo"] is None
    assert cinemeta.seasons(meta)[0]["episodes"][0]["title"] == "7"
    assert cinemeta.credits(meta)["cast"] == []


def test_network_garbage_is_a_network_error():
    class Drip:
        def read(self, n=-1):
            return b"x" * 70_000

    with pytest.raises(ValueError):
        net.read_body(Drip(), timeout=5, limit=100_000)  # nunca termina: se corta por tamaño
    assert issubclass(http.client.IncompleteRead, net.NET_ERRORS)


def test_state_keeps_a_backup_of_what_it_could_not_read(tmp_path):
    path = tmp_path / "state.json"
    path.write_text("[]", encoding="utf-8")
    state = State(path)
    assert list(tmp_path.glob("state-*.bak")) and state.settings() == {}
    bom = tmp_path / "bom.json"
    bom.write_text(json.dumps({"prefs": {"a": {"favorite": True}}}), encoding="utf-8-sig")
    assert State(bom).prefs("a") == {"favorite": True}  # el BOM del Bloc de notas no lo invalida
    odd = tmp_path / "odd.json"
    odd.write_text(json.dumps({"history": {"x": {}}}), encoding="utf-8")
    State(odd).record_launch("x")  # antes: KeyError 'launches'


def test_state_save_never_breaks_a_launch(tmp_path, monkeypatch):
    state = State(tmp_path / "s.json")
    monkeypatch.setattr("pathlib.Path.replace", lambda self, target: (_ for _ in ()).throw(PermissionError("antivirus")))
    state.record_launch("juego")  # no lanza: se registra en el log y sigue


def test_voice_only_runs_intent_handlers(library):
    voice = VoiceController(library)
    for intent in ("Language", "ShowView", "SplitRunner", "__class__", ""):
        result = voice.handle_intent(intent, {})
        assert not result.ok  # antes: 500 con 'str' object has no attribute 'events'


def test_settings_are_all_or_nothing_and_typed(make_client):
    with make_client() as c:
        assert c.post("/api/settings", json={"audio": []}).status_code == 422
        assert c.post("/api/settings", json={"reduce_motion": 1}).status_code == 422
        assert c.post("/api/settings", json={"safe_area": False}).status_code == 422
        before = c.get("/api/settings").json()["audio"]
        other = "es" if before != "es" else "en"
        assert c.post("/api/settings", json={"audio": other, "quality": "malo"}).status_code == 422
        assert c.get("/api/settings").json()["audio"] == before  # nada a medias


def test_endpoints_reject_wrong_types(make_client, monkeypatch, tmp_path):
    shots = tmp_path / "Captures"
    shots.mkdir()
    (shots / "malo.bat").write_text("echo")
    monkeypatch.setattr(capture, "folders", lambda: [shots])
    monkeypatch.setattr(quick, "snapshot", dict)
    with make_client() as c:
        assert c.post("/api/windows/focus", json={"id": "x"}).status_code == 422
        assert c.post("/api/ui/reload", json={"view": 5}).status_code == 200
        assert c.post("/api/captures/open", json={"path": "\\\\10.255.255.1\\share\\x.png"}).status_code == 404
        assert c.post("/api/captures/open", json={"path": str(shots / "malo.bat")}).status_code == 404
        assert c.get("/api/captures/file", params={"path": "a\x00b"}).status_code == 404
        assert c.post("/api/quick", json={"muted": "false"}).status_code == 422
        assert c.get("/docs").status_code in (401, 404) and c.get("/openapi.json").status_code in (401, 404)
        for sneaky in ("/\\10.255.255.1\\share\\x.png", "\\/10.255.255.1/share/x.png", "C:x.png", "\\\\?\\C:\\x.png"):
            assert c.post("/api/captures/open", json={"path": sneaky}).status_code == 404
        assert c.post("/api/stremio/library", json={"kind": "movie", "id": "tt1", "add": "false"}).status_code == 422
        assert c.post("/api/stremio/library", json={"kind": "movie", "id": ["tt1"], "add": True}).status_code == 400


def test_odd_streams_and_addons_are_skipped():
    from orbital.library import streams

    good = {"name": "[RD+] Torrentio\n1080p", "title": "Peli 1080p\n💾 2.1 GB", "url": "https://x/y.mkv"}
    for bad in [{"name": ["x"], "behaviorHints": "no", "url": "https://x"}, {"title": "💾 1e999 GB", "url": "https://x"},
                {"behaviorHints": {"filename": 5, "bingeGroup": ["a"]}, "url": "https://x"}]:
        streams.parse(bad, "Addon", "https://a/manifest.json", 0)  # no lanza
    assert streams.parse(good, "Torrentio", "https://a/manifest.json", 0).resolution == "1080p"

    class Client:
        def request(self, *_a):
            return {"addons": [None, "x", {"manifest": "x"}, {"manifest": {"resources": [["stream"]]}, "transportUrl": "https://b"},
                               {"manifest": {"name": "Bueno", "resources": ["stream"], "types": ["movie", 5]},
                                "transportUrl": "https://a/manifest.json"},
                               {"manifest": {"resources": ["stream"]}, "transportUrl": "file:///C:/x"}]}

    found = streams.StreamFinder(Client()).addons("k")
    assert [a["name"] for a in found] == ["Bueno"] and found[0]["types"] == ["movie"]


def test_failed_tokens_slow_down_rotating_forwarded_headers():
    from orbital.server import FailedTokens

    guard = FailedTokens(clock=lambda: 100.0)
    delays = [guard.failed(f"10.0.0.{i}") for i in range(80)]  # cada intento con otra X-Forwarded-For
    assert delays[0] == 0 and delays[-1] > 0
    for i in range(2000):
        guard.failed(f"h{i}")
    assert len(guard._fails) <= 501 and len(guard._all) <= 1000


def test_emulator_paths_with_brackets_and_args_with_braces(tmp_path):
    from orbital.config import EmulatorConfig
    from orbital.library import emulators

    exe = tmp_path / "Emus [2024]" / "emu.exe"
    exe.parent.mkdir()
    exe.write_text("")
    emu = EmulatorConfig(id="e", name="E", executable=str(exe), args=['--cfg={"a":1}', "{rom}"])
    assert emulators.resolve_executable(emu) == exe
    rom = tmp_path / "juego {x}.iso"
    assert emulators.build_argv(emu, exe, rom) == [str(exe), '--cfg={"a":1}', str(rom)]


def test_state_that_cannot_be_read_is_not_overwritten(tmp_path, monkeypatch):
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"history": {"a": {"playtime": 500, "launches": 2}}}), encoding="utf-8")
    original = path.read_text(encoding="utf-8")
    monkeypatch.setattr(State, "_read", lambda self, p: (_ for _ in ()).throw(PermissionError("bloqueado")))
    state = State(path)
    state.record_launch("b")
    assert path.read_text(encoding="utf-8") == original


def test_state_numbers_are_numbers(tmp_path):
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"history": {"a": {"playtime": "abc", "last_played": None, "launches": -3}},
                                "seen": {"x": "ayer"}}), encoding="utf-8")
    state = State(path)
    state.record_session("a", 60)
    assert state._data["history"]["a"]["playtime"] == 60 and state._data["seen"]["x"] == 0


def test_home_chord_counts_again_after_releasing_the_button():
    from orbital.gamepad import GUIDE, RB_BUTTON, ComboDetector

    d = ComboDetector()
    events = []
    for buttons in (GUIDE, GUIDE | RB_BUTTON, GUIDE, GUIDE | RB_BUTTON, 0):
        events += d.update(buttons, 0)
    assert events.count("capture") == 2 and "home" not in events


def test_odd_saved_library_items_are_rejected():
    from orbital.library.models import LibraryItem

    for bad in [{"id": 5, "title": "x"}, {"id": "a", "title": None}, {"id": "a", "title": "x", "extra": []},
                {"id": "a", "title": "x", "runners": "eden"}]:
        with pytest.raises(TypeError):
            LibraryItem.from_dict(bad)


# --- ronda 3 -------------------------------------------------------------------------------------
@pytest.mark.parametrize("data", ['{"history": {"a": {"playtime": 9}}}'.encode("utf-16"), "{\"á\": 1}".encode("cp1252"),
                                  bytes(range(256))])
def test_state_that_is_not_utf8_starts_clean_and_keeps_a_backup(tmp_path, data):
    path = tmp_path / "state.json"
    path.write_bytes(data)
    state = State(path)  # antes: UnicodeDecodeError y Orbital no arrancaba
    assert state.settings() == {} and list(tmp_path.glob("state-*.bak"))


def test_no_500_with_nan_or_lone_surrogates(make_client):
    lone = '"' + chr(92) + 'ud800"'
    bodies = ['{"id": NaN}', '{"id": Infinity}', '{"id": ' + lone + '}', '{"text": ' + lone + ', "volume": NaN}',
              '{"kind": "movie", "id": ' + lone + '}', '{"id": ' + lone + ', "kind": "cover"}']
    with make_client() as c:
        for route in ["/api/prefs", "/api/art-replace", "/api/launch", "/api/stremio/play"]:
            for body in bodies:
                r = c.post(route, content=body.encode(), headers={"content-type": "application/json"})
                assert r.status_code < 500, (route, body, r.text)


def test_stream_sizes_with_commas():
    from orbital.library import streams

    size = lambda text: streams.parse({"title": f"x\n💾 {text}", "url": "https://x"}, "A", "https://a", 0).size  # noqa: E731
    assert size("1,5 GB") == 1_500_000_000 and size("1.5 GB") == 1_500_000_000
    assert size("1,234.5 MB") == 1_234_500_000 and size("1.234,5 MB") == 1_234_500_000


def test_odd_rejected_art_file_does_not_break_change_image(tmp_path):
    lib = media.MediaStore(tmp_path)
    lib._rejected_file().parent.mkdir(parents=True, exist_ok=True)
    lib._rejected_file().write_text("[]", encoding="utf-8")
    lib.reject("snes", "zelda", "cover", "https://x/a.png")
    assert lib.is_rejected("snes", "zelda", "cover", "https://x/a.png")


# --- ronda 4 -------------------------------------------------------------------------------------
def test_next_episode_keeps_the_language_of_the_series(library, monkeypatch):
    from orbital.library import streams

    info = {"id": "tt1", "name": "Serie", "videos": [{"id": f"tt1:1:{i}", "season": 1, "episode": i} for i in (1, 2)]}
    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path: {"meta": info})
    library.credentials.set("stremio_auth_key", "k")
    sources = [streams.Source(index=i, addon="A", stream={"url": f"https://cdn/{i}.mkv"}, transport_url="https://a",
                              resolution="1080p", languages=[lang], binge=f"grupo-{lang}", cached=True)
               for i, lang in enumerate(("es", "en"))]
    monkeypatch.setattr(library.watch, "stream_sources",
                        lambda kind, vid, prefs=None: streams.rank(list(sources), prefs or library.watch.stream_prefs, kind))
    library.state.set_pref("stremio:tt1", "audio", "es")  # esta serie, en español (Ajustes: inglés)
    loaded = []
    monkeypatch.setattr(library.watch.player, "load", lambda url, title, meta, **kw: loaded.append(url) or True)
    library.watch._play_episode("tt1", "tt1:1:2", "Serie · T1 E2", binge="grupo-es")
    assert loaded == ["https://cdn/0.mkv"]


def test_odd_stremio_progress_is_zero_not_500():
    for state in [{"video_id": "v", "timeOffset": "abc"}, {"video_id": "v", "timeOffset": 1e999},
                  {"video_id": "v", "duration": "x", "timeOffset": 5000}, ["x"], "texto"]:
        assert stremio_api.resume_seconds({"state": state}, "v") in (0.0, 5.0)
    assert stremio_api.parse_watched(5, ["a"]) == set()
    item = stremio_api.parse_item({"_id": "tt1", "name": 1917, "type": "movie"})
    assert item is not None and item.name == "1917"
    assert stremio_api.parse_item({"_id": ["x"], "name": "Peli", "type": "movie"}) is None


def test_cinemeta_titles_must_be_text(monkeypatch):
    metas = [{"id": "tt1", "name": 1917}, {"id": ["tt2"], "name": "x"}, {"id": "tt3", "name": ["a"]}, {"id": "tt4", "name": "Bien"}]
    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path: {"metas": metas})
    assert [m["id"] for m in cinemeta.Cinemeta().search("movie", "x")] == ["tt4"]


def test_non_ascii_token_is_rejected_not_an_error():
    from types import SimpleNamespace

    from orbital.server import token_ok

    ask = lambda value: SimpleNamespace(headers={"authorization": value})  # noqa: E731
    assert not token_ok(ask("Bearer éé"), "secreto")  # antes: TypeError → 500
    assert not token_ok(ask("Bearer secreto"), "sécreto")
    assert token_ok(ask("Bearer " + "sécreto".encode().decode("latin-1")), "sécreto")


def test_more_sizes():
    from orbital.library import streams

    size = lambda text: streams.parse({"title": f"x\n💾 {text}", "url": "https://x"}, "A", "https://a", 0).size  # noqa: E731
    assert size("0,750 GB") == 750_000_000 and size("1,2,3 GB") == 0 and size("1.234.567 KB") == 1_234_567_000


def test_library_json_gets_a_copy_of_extra():
    from orbital.library.models import LibraryItem

    item = LibraryItem(id="a", title="A", category="games", source="x", extra={"year": "2020"})
    item.public()["extra"]["year"] = "otro"
    assert item.extra["year"] == "2020"


# --- ronda 5 -------------------------------------------------------------------------------------
def test_sources_listed_and_played_with_the_series_language(library, monkeypatch):
    from orbital.library import streams

    library.credentials.set("stremio_auth_key", "k")
    library.state.set_pref("stremio:tt1", "audio", "es")  # esta serie, en español (Ajustes: inglés)
    raw = [{"name": "A", "title": "Peli\n🇲🇽", "url": "https://cdn/0.mkv"}, {"name": "A", "title": "Peli", "url": "https://cdn/1.mkv"}]
    monkeypatch.setattr(streams.StreamFinder, "addons", lambda self, key: [{"name": "A", "url": "https://a/manifest.json", "types": [], "resources": ["stream"]}])
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, a, k, v: raw)
    listed = library.watch.stream_sources("movie", "tt1", library.watch.language_for("tt1")[0])
    played = []
    monkeypatch.setattr(library.watch, "play_native", lambda *a, **k: played.append(a[1]))
    monkeypatch.setattr("orbital.player.find_mpv", lambda: "mpv.exe")
    library.watch.play_source("movie", "tt1", "tt1", listed[0].index, "Peli")
    assert played == [listed[0].stream["url"]]


def test_failed_network_is_not_remembered_as_no_sources(monkeypatch):
    import urllib.error

    from orbital.library import streams

    calls = []

    def get_json(self, addon, path):
        calls.append(path)
        if len(calls) == 1:
            raise urllib.error.URLError("Wi-Fi al despertar")
        return {"streams": [{"name": "A", "url": "https://cdn/x.mkv"}]}

    monkeypatch.setattr(streams.StreamFinder, "addons", lambda self, key: [{"name": "A", "url": "https://a/manifest.json", "types": [], "resources": ["stream"]}])
    monkeypatch.setattr(streams.StreamFinder, "_get_json", get_json)
    finder = streams.StreamFinder(None)
    assert finder.find("k", "movie", "tt1", streams.Preferences()) == []
    assert len(finder.find("k", "movie", "tt1", streams.Preferences())) == 1


def test_odd_settings_in_state_do_not_stop_orbital(tmp_path):
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"settings": {"video_idle_minutes": "abc", "sub_scale": [1], "sounds": "yes", "audio": "es",
                                             "game_idle_minutes": 1e308}}), encoding="utf-8")
    assert State(path).settings() == {"audio": "es"}


def test_dismiss_survives_odd_state():
    for state in ("xyz", [1, 2], 5):
        item = stremio_api.parse_item({"_id": "tt1", "name": "Serie", "type": "series", "state": state})
        assert item is not None
    assert stremio_api.parse_item({"_id": "tt1", "name": "Serie", "type": "series",
                                   "state": {"timeOffset": "abc", "duration": [1], "video_id": 5}}) is not None


def test_cinemeta_odd_metas_and_posters(monkeypatch):
    for metas in (5, True, "x", None):
        monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path, m=metas: {"metas": m})
        assert cinemeta.Cinemeta().search("movie", "x") == []
    assert cinemeta._medium(5) is None and cinemeta._medium(["a"]) is None


# --- ronda 6 -------------------------------------------------------------------------------------
def test_a_source_keeps_its_number_when_addons_answer_in_another_order(monkeypatch):
    from orbital.library import streams

    a = {"name": "A", "url": "https://a/manifest.json", "types": [], "resources": ["stream"]}
    b = {"name": "B", "url": "https://b/manifest.json", "types": [], "resources": ["stream"]}
    raw = {"https://a/manifest.json": [{"name": "A", "url": "https://cdn/small.mkv"}],
           "https://b/manifest.json": [{"name": "B", "url": "https://cdn/remux.mkv"}]}
    order = [[a, b]]
    monkeypatch.setattr(streams.StreamFinder, "addons", lambda self, key: order[0])
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, k, v: raw[addon["url"]])
    first = {s.stream["url"]: s.index for s in streams.StreamFinder(None).find("k", "movie", "tt1", streams.Preferences())}
    order[0] = [b, a]
    again = {s.stream["url"]: s.index for s in streams.StreamFinder(None).find("k", "movie", "tt1", streams.Preferences())}
    assert first == again


def test_logging_out_mid_download_does_not_bring_the_list_back(library, monkeypatch):
    import threading as th

    library.credentials.set("stremio_auth_key", "k")
    gate, started = th.Event(), th.Event()

    def slow_library(key):
        started.set()
        gate.wait(5)
        return [{"_id": "tt1", "name": "Serie", "type": "series", "state": {"timeOffset": 1000, "video_id": "tt1:1:1"}}]

    monkeypatch.setattr(library.watch.stremio_client, "library", slow_library)
    worker = th.Thread(target=library.watch.refresh_stremio)
    worker.start()
    started.wait(5)
    library.watch.unlink_stremio()
    gate.set()
    worker.join(5)
    assert library.watch.stremio_items == [] and not library.watch.stremio_linked


def test_odd_language_prefs_do_not_block_a_title(library):
    for value in (["x"], 5, {"a": 1}):
        library.state.set_pref("stremio:tt1", "audio", value)
        library.state.set_pref("stremio:tt1", "subtitles", value)
        prefs, subtitles = library.watch.language_for("tt1")
        assert isinstance(prefs.audio, str) and isinstance(subtitles, str)


def test_player_title_fits_on_a_4_3_screen():
    from orbital import player_ui

    try:
        player_ui.set_canvas(1440, 1080)
        hud = player_ui.Hud(title="Un título larguísimo " * 6, detail="T1 E1 · " + "nombre " * 20, position=10, duration=100)
        assert player_ui.fit(hud.title, 48, min(1500, player_ui.W - 2 * player_ui.MARGIN), "bold") != hud.title
        player_ui.hud_ass(hud)
    finally:
        player_ui.set_canvas(1920, 1080)


def test_a_frozen_mpv_does_not_freeze_orbital(monkeypatch):
    import threading as th
    import time as _t

    from orbital.mpv import Mpv

    stuck = th.Event()

    class Frozen:
        def write(self, data):
            return len(data)

        def readline(self):
            stuck.wait(5)  # mpv colgado: no contesta
            return b""

        def close(self):
            pass

    mpv = Mpv(pipe="no-existe")
    mpv.TIMEOUT = .3
    monkeypatch.setattr(mpv, "_connect", lambda: Frozen())
    start = _t.monotonic()
    assert mpv.command("quit") is None
    assert mpv.command("quit") is None  # la siguiente tampoco espera para siempre
    assert _t.monotonic() - start < 2
    stuck.set()
