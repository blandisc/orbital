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
