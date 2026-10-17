from __future__ import annotations

import json
import os
import zipfile

import pytest

from orbital import emulator_updates as eu


def release(tag, assets=(), published="2026-10-16T19:27:01Z"):
    return {"tag_name": tag, "published_at": published, "html_url": "https://x",
            "assets": [{"name": n, "browser_download_url": f"https://dl/{n}", "size": 10, "updated_at": published} for n in assets]}


def emulator(tmp_path, folder="xemu", exe="xemu.exe", files=None):
    root = tmp_path / folder
    root.mkdir(parents=True, exist_ok=True)
    (root / exe).write_bytes(b"viejo")
    for name, data in (files or {}).items():
        (root / name).write_bytes(data)
    return root / exe


def make_zip(path, entries):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return path


def service(tmp_path, exes, answers, versions=None, busy=False, mode="avisar", notes=None):
    def get_json(url):
        for key, value in answers.items():
            if key in url:
                return value
        raise OSError("404")

    def fetch(url, dest):
        return make_zip(dest, {"xemu.exe": b"nuevo", "data/x.bin": b"datos"})

    return eu.EmulatorUpdates(lambda: exes, mode=lambda: mode, busy=lambda: busy, notify=notes.append if notes is not None else (lambda text: None),
                              cache_dir=tmp_path / "cache", get_json=get_json, fetch=fetch,
                              version_of=lambda exe: (versions or {}).get(exe.name))


def test_versions_compare_by_their_numbers():
    assert eu.version_tuple("v.0.20.0") == (0, 20) and eu.version_tuple("0.10.5.0") == (0, 10, 5)
    assert eu.version_tuple("1.3.3+e2143d4") == (1, 3, 3) and eu.version_tuple("mgba") == ()
    assert eu.version_tuple("v0.8.137") > eu.version_tuple("0.8.136")


def test_says_which_emulators_have_a_new_version(tmp_path):
    xemu = emulator(tmp_path)
    ppsspp = emulator(tmp_path, "PPSSPP", "PPSSPPWindows64.exe")
    s = service(tmp_path, [xemu, ppsspp], {
        "xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip", "xemu-0.8.138-windows-arm64.zip"]),
        "hrydgard": release("v1.20.4", ["PPSSPP-v1.20.4-Windows-x64.zip"])},
        versions={"xemu.exe": "0.8.137", "PPSSPPWindows64.exe": "v1.20.4"})
    items = {i["id"]: i for i in s.summary()["items"]}
    assert items["xemu"] | {"folder": None} == {"id": "xemu", "name": "xemu", "installed": "0.8.137", "latest": "v0.8.138",
                                                 "update": True, "likely": False, "can_install": True,
                                                 "page": "https://xemu.app/#download", "error": None, "folder": None}
    assert items["ppsspp"]["update"] is False


def test_without_a_version_number_the_date_decides(tmp_path):
    dolphin = emulator(tmp_path, "Dolphin-x64", "Dolphin.exe")
    os.utime(dolphin, (1_700_000_000, 1_700_000_000))  # 2023
    s = service(tmp_path, [dolphin], {"dolphin-emu.org": {"shortrev": "2609a", "date": "2026-10-08T00:57:28.587Z"}})
    item = s.summary()["items"][0]
    assert item["update"] is True and item["likely"] is True and item["can_install"] is False  # Dolphin viene en .7z


def test_offline_is_an_error_per_emulator_not_a_crash(tmp_path):
    s = service(tmp_path, [emulator(tmp_path)], {})
    item = s.summary()["items"][0]
    assert item["update"] is False and item["error"]


def test_install_backs_up_what_it_replaces_and_records_the_version(tmp_path):
    xemu = emulator(tmp_path, files={"xemu.toml": b"mis ajustes"})
    s = service(tmp_path, [xemu], {"xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip"])},
                versions={"xemu.exe": "0.8.137"})
    assert s.install("xemu") == "xemu actualizado a v0.8.138."
    assert xemu.read_bytes() == b"nuevo" and (xemu.parent / "data" / "x.bin").read_bytes() == b"datos"
    assert (xemu.parent / "xemu.toml").read_bytes() == b"mis ajustes"  # lo que no trae el .zip no se toca
    assert (xemu.parent / eu.BACKUP / "xemu.exe").read_bytes() == b"viejo"
    assert json.loads((xemu.parent / eu.MANIFEST).read_text())["version"] == "v0.8.138"


def test_never_installs_with_a_game_open_or_what_must_be_done_by_hand(tmp_path):
    xemu = emulator(tmp_path)
    answers = {"xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip"]), "mgba-emu": release("0.10.6", ["mGBA-0.10.6-win64.7z"])}
    with pytest.raises(eu.InstallError, match="Cierra el juego"):
        service(tmp_path, [xemu], answers, versions={"xemu.exe": "0.8.137"}, busy=True).install("xemu")
    mgba = emulator(tmp_path, "mGBA", "mGBA.exe")
    with pytest.raises(eu.InstallError, match="a mano"):
        service(tmp_path, [mgba], answers, versions={"mGBA.exe": "0.10.5"}).install("mgba")


def test_a_bad_zip_leaves_everything_as_it_was(tmp_path):
    xemu = emulator(tmp_path)
    bad = make_zip(tmp_path / "bad.zip", {"otro.exe": b"x"})
    with pytest.raises(eu.InstallError, match="no trae"):
        eu.install_zip(bad, xemu, "v1")
    evil = make_zip(tmp_path / "evil.zip", {"xemu.exe": b"x", "../fuera.txt": b"x"})
    with pytest.raises(eu.InstallError, match="rutas raras"):
        eu.install_zip(evil, xemu, "v1")
    assert xemu.read_bytes() == b"viejo" and not (tmp_path / "fuera.txt").exists()


def test_auto_mode_installs_what_it_can_and_warn_mode_only_tells(tmp_path):
    answers = {"xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip"])}
    notes: list[str] = []
    xemu = emulator(tmp_path)
    assert service(tmp_path, [xemu], answers, versions={"xemu.exe": "0.8.137"}, mode="avisar", notes=notes).run_auto() == []
    assert notes and "xemu" in notes[0] and xemu.read_bytes() == b"viejo"
    done = service(tmp_path, [xemu], answers, versions={"xemu.exe": "0.8.137"}, mode="auto").run_auto()
    assert done == ["xemu actualizado a v0.8.138."] and xemu.read_bytes() == b"nuevo"
    assert service(tmp_path, [xemu], answers, mode="nunca").run_auto() == []


def test_a_launcher_cmd_points_to_its_emulator(tmp_path):
    eden = emulator(tmp_path, "eden", "eden.exe")
    cmd = eden.parent / "launch-eden.cmd"
    cmd.write_text("@echo off")
    assert eu.real_exe(cmd) == eden


def test_api_lists_updates_and_the_setting_is_saved(make_client):
    c = make_client()
    data = c.get("/api/emulators/updates").json()
    assert data["mode"] == "avisar" and isinstance(data["items"], list)
    assert c.post("/api/settings", json={"emulator_updates": "auto"}).json()["emulator_updates"] == "auto"
    assert c.post("/api/settings", json={"emulator_updates": "siempre"}).status_code == 422


def test_screensaver_setting_is_saved(make_client):
    c = make_client()
    assert c.get("/api/settings").json()["screensaver_minutes"] == 10
    assert c.post("/api/settings", json={"screensaver_minutes": 0}).json()["screensaver_minutes"] == 0
    assert c.post("/api/settings", json={"screensaver_minutes": 7}).status_code == 422
