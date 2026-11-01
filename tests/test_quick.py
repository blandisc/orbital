"""Panel rápido y capturas, sin tocar el volumen ni el brillo de verdad."""

import pytest

from orbital import capture, quick


@pytest.fixture
def fake_quick(monkeypatch):
    state = {"volume": {"level": 40, "muted": False}, "brightness": 50, "power_mode": "balanced", "battery": None}
    monkeypatch.setattr(quick, "snapshot", lambda: dict(state))
    monkeypatch.setattr(quick, "set_volume", lambda level=None, muted=None: state["volume"].update(
        {k: v for k, v in (("level", level), ("muted", muted)) if v is not None}))
    monkeypatch.setattr(quick, "set_brightness", lambda level: state.update(brightness=level))
    monkeypatch.setattr(quick, "set_power_mode", lambda mode: state.update(power_mode=mode))
    return state


def test_quick_panel_api(make_client, fake_quick):
    with make_client() as c:
        assert c.get("/api/quick").json()["volume"]["level"] == 40
        after = c.post("/api/quick", json={"volume": 70, "brightness": 30, "power_mode": "performance"}).json()
        assert after["volume"]["level"] == 70 and after["brightness"] == 30 and after["power_mode"] == "performance"
        assert c.post("/api/quick", json={"power_mode": "turbo"}).status_code == 422


def test_gallery_only_serves_files_from_the_capture_folders(make_client, monkeypatch, tmp_path):
    shots = tmp_path / "Captures"
    shots.mkdir()
    (shots / "Zelda.png").write_bytes(capture.png(1, 1, bytes(4)))
    secret = tmp_path / "secreto.txt"
    secret.write_text("no")
    monkeypatch.setattr(capture, "folders", lambda: [shots])
    with make_client() as c:
        items = c.get("/api/captures").json()["items"]
        assert [i["name"] for i in items] == ["Zelda"]
        assert c.get("/api/captures/file", params={"path": items[0]["path"]}).status_code == 200
        assert c.get("/api/captures/file", params={"path": str(secret)}).status_code == 404
        assert c.get("/api/captures/file", params={"path": str(shots / ".." / "secreto.txt")}).status_code == 404


def test_png_encoder_makes_a_valid_header():
    data = capture.png(2, 1, bytes([0, 0, 255, 0, 0, 255, 0, 0]))  # rojo, verde (BGRA)
    assert data.startswith(bytes([137, 80, 78, 71])) and b"IHDR" in data and data.endswith(b"IEND" + data[-4:])


def test_music_api(make_client, monkeypatch):
    from orbital import music

    state = {"playing": True}
    monkeypatch.setattr(music, "now_playing", lambda: {"app": "Apple Music", "title": "Pedro Navaja", "artist": "Rubén Blades",
                                                       "album": "", "playing": state["playing"], "has_art": False})
    monkeypatch.setattr(music, "command", lambda action: state.update(playing=not state["playing"]) or True)
    monkeypatch.setattr(music, "apple_music_installed", lambda: True)
    with make_client() as c:
        assert c.get("/api/music").json()["now"]["title"] == "Pedro Navaja"
        assert c.post("/api/music", json={"action": "toggle"}).json()["now"]["playing"] is False
        assert c.post("/api/music", json={"action": "borrar"}).status_code == 422


def test_voice_pause_goes_to_music_when_no_movie(library, monkeypatch):
    from orbital import music
    from orbital.voice import VoiceController

    done = []
    monkeypatch.setattr(music, "now_playing", lambda: {"title": "x", "playing": True})
    monkeypatch.setattr(music, "command", lambda action: done.append(action) or True)
    voice = VoiceController(library)
    assert voice.handle_text("pausa la música").speech == "Música en pausa."
    assert voice.handle_text("siguiente canción").speech == "Siguiente canción."
    assert done == ["pause", "next"]


def test_brightness_falls_back_to_wmi_when_the_ioctl_does_nothing(monkeypatch):
    """En la Legion Go el IOCTL dice «listo» y el brillo no cambia: entonces va por WMI (como el deslizador de Windows)."""
    import importlib

    quick = importlib.reload(importlib.import_module("orbital.quick"))  # el de verdad, sin el doble de conftest
    level = {"now": 26}
    calls = []
    monkeypatch.setattr(quick, "WIN", True)
    monkeypatch.setattr(quick, "battery", lambda: {"plugged": True})

    def lcd(code, inp=None, out=None):
        if out is not None:
            out.ac = out.dc = level["now"]
        return True  # el IOCTL siempre «funciona»… y no cambia nada

    monkeypatch.setattr(quick, "_lcd", lcd)
    monkeypatch.setattr(quick, "_wmi_brightness", lambda value: calls.append(value) or level.update(now=value) or True)
    assert quick.set_brightness(56) == 56 and calls == [56]
    level["now"] = 30
    monkeypatch.setattr(quick, "_lcd", lambda code, inp=None, out=None: (level.update(now=inp.ac) if inp else
                                                                        (setattr(out, "ac", level["now"]), setattr(out, "dc", 0))) or True)
    assert quick.set_brightness(40) == 40 and calls == [56]  # si el IOCTL sí sirve, no se llama a PowerShell
