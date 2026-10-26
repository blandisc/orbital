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
                                                 "page": "https://xemu.app/#download", "error": None, "folder": None,
                                                 "can_rollback": False, "previous": None}
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


def test_a_bad_new_version_can_go_back_to_the_previous_one(tmp_path):
    """La 0.8.138 sale mal: «Regresar a la versión anterior» pone la 0.8.137 de vuelta y quita lo que la nueva agregó."""
    xemu = emulator(tmp_path, files={"settings.toml": b"mis ajustes"})
    s = service(tmp_path, [xemu], {"xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip"])},
                versions={"xemu.exe": "0.8.137"})
    s.install("xemu")
    assert xemu.read_bytes() == b"nuevo" and (xemu.parent / "data" / "x.bin").exists()
    item = s.summary()["items"][0]
    assert item["can_rollback"] and item["previous"] == "0.8.137"
    assert s.rollback("xemu") == "xemu regresó a 0.8.137."
    assert xemu.read_bytes() == b"viejo" and not (xemu.parent / "data" / "x.bin").exists()
    assert (xemu.parent / "settings.toml").read_bytes() == b"mis ajustes"  # tus ajustes, intactos
    assert not s.summary()["items"][0]["can_rollback"]  # ya no hay a dónde regresar
    with pytest.raises(eu.InstallError):
        s.rollback("xemu")


def test_eden_from_forgejo_and_ryujinx_from_gitlab_now_install_on_their_own():
    eden = next(x for x in eu.SOURCES if x.id == "eden")
    data = [{"tag_name": "v0.2.1", "published_at": "2026-10-01T00:00:00Z", "assets": [
        {"name": "Eden-Windows-v0.2.1-arm64-clang-pgo.zip", "browser_download_url": "https://e/arm.zip"},
        {"name": "Eden-Windows-v0.2.1-amd64-msvc-standard.zip", "browser_download_url": "https://e/x64.zip"}]}]
    assert eu.latest_release(eden, lambda url: data).asset_url == "https://e/x64.zip"
    ryujinx = next(x for x in eu.SOURCES if x.id == "ryujinx")
    gitlab = [{"tag_name": "1.3.4", "released_at": "2026-10-20T00:00:00Z", "assets": {"links": [
        {"name": "ryujinx-1.3.4-macos_universal.app.tar.gz", "url": "https://r/mac"},
        {"name": "ryujinx-1.3.4-win_x64.zip", "url": "https://r/win.zip"}]}}]
    assert eu.latest_release(ryujinx, lambda url: gitlab).asset_url == "https://r/win.zip"


def test_games_without_their_emulator_offer_to_install_it(tmp_path):
    roms = tmp_path / "ROMs"
    for system, game in (("psp", "Patapon.iso"), ("switch", "Zelda.xci"), ("gba", "Pokemon.gba")):
        (roms / system).mkdir(parents=True)
        (roms / system / game).write_bytes(b"x")
    (roms / "xbox").mkdir()  # carpeta vacía: no hay juegos que abrir
    s = eu.EmulatorUpdates(list, mode=lambda: "avisar", busy=lambda: False, roms_root=lambda: roms,
                           have_systems=lambda: {"switch"}, install_root=lambda: tmp_path / "Emuladores")
    assert s.installable() == [{"system": "psp", "id": "ppsspp", "name": "PPSSPP", "system_name": "PSP"}]


def test_installing_a_missing_emulator_puts_it_in_your_emulators_folder(tmp_path):
    installed = []

    def fetch(url, dest):
        return make_zip(dest, {"PPSSPP-v1.20.4/PPSSPPWindows64.exe": b"ppsspp", "PPSSPP-v1.20.4/assets/a.bin": b"a"})

    s = eu.EmulatorUpdates(list, mode=lambda: "avisar", busy=lambda: False, cache_dir=tmp_path / "cache",
                           get_json=lambda url: release("v1.20.4", ["PPSSPP-v1.20.4-Windows-x64.zip"]), fetch=fetch,
                           install_root=lambda: tmp_path / "Emuladores", on_installed=lambda: installed.append(1))
    assert "PPSSPP instalado" in s.install_new("ppsspp")
    exe = tmp_path / "Emuladores" / "ppsspp" / "ppssppwindows64.exe"
    assert exe.read_bytes() == b"ppsspp" and (exe.parent / "assets" / "a.bin").exists() and installed == [1]
    assert eu.rollback_version(exe) is None  # recién instalado: no hay versión anterior
    with pytest.raises(eu.InstallError):
        s.install_new("ppsspp")  # ya está
    with pytest.raises(eu.InstallError):
        s.install_new("dolphin")  # viene en .7z: no se instala solo


def test_the_eden_build_you_chose_is_the_one_that_downloads(tmp_path):
    """Eden publica varias versiones para Windows: el actualizador baja la que elegiste (ROG Ally o estándar)."""
    eden = emulator(tmp_path, "eden", "eden.exe")
    data = [{"tag_name": "v0.2.2", "published_at": "2099-01-01T00:00:00Z", "assets": [
        {"name": "Eden-Windows-v0.2.2-amd64-msvc-standard.zip", "browser_download_url": "https://e/std.zip"},
        {"name": "Eden-Windows-v0.2.2-rog-ally-clang-pgo.zip", "browser_download_url": "https://e/rog.zip"}]}]
    asked = []

    def fetch(url, dest):
        asked.append(url)
        return make_zip(dest, {"eden.exe": b"nuevo"})

    choice = {"eden": "rog-ally"}
    s = eu.EmulatorUpdates(lambda: [eden], mode=lambda: "auto", busy=lambda: False, cache_dir=tmp_path / "cache",
                           get_json=lambda url: data, fetch=fetch, version_of=lambda exe: None,
                           variant=lambda sid: choice.get(sid))
    summary = s.summary()
    assert summary["variants"]["eden"] == {"value": "rog-ally", "options": [["standard", "Estándar"], ["rog-ally", "ROG Ally"]]}
    assert s.install("eden") == "Eden actualizado a v0.2.2-rog-ally."
    assert asked == ["https://e/rog.zip"]
    choice["eden"] = "standard"  # cambiaste a la estándar: «Instalarla ahora» la baja aunque ya estés al día
    s._last = None
    assert s.install("eden", force=True) == "Eden actualizado a v0.2.2-standard."
    assert asked[-1] == "https://e/std.zip"


def test_without_eden_there_is_no_build_to_choose(tmp_path):
    s = service(tmp_path, [emulator(tmp_path)], {"xemu-project": release("v0.8.138", ["xemu-0.8.138-windows-x86_64.zip"])})
    assert s.summary()["variants"] == {}
