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
    assert (tmp_path / "state.bak").exists() and state.settings() == {}
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
