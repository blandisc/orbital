"""La hora de los emuladores de Switch, la de la computadora (Ryujinx traía «UTC»; los de yuzu pueden traer un reloj propio)."""

from __future__ import annotations

import json

from orbital import emulator_clock


def test_la_zona_de_windows_en_nombre_iana():
    assert emulator_clock.local_zone("Central Standard Time (Mexico)") == "America/Mexico_City"
    assert emulator_clock.local_zone("Zona Inventada").startswith(("Etc/GMT", "UTC"))


def test_ryujinx_queda_en_la_zona_de_la_computadora_y_sin_desfase(tmp_path, monkeypatch):
    folder = tmp_path / "Ryujinx"
    (folder / "games" / "0100").mkdir(parents=True)
    for path in (folder / "Config.json", folder / "games" / "0100" / "Config.json"):
        path.write_text(json.dumps({"system_time_zone": "UTC", "system_time_offset": -196, "match_system_time": True,
                                    "graphics_shaders_dump_path": ""}), encoding="utf-8")
    exe = tmp_path / "Emulators" / "ryujinx" / "Ryujinx.exe"
    exe.parent.mkdir(parents=True)
    exe.write_bytes(b"")
    monkeypatch.setenv("APPDATA", str(tmp_path))
    assert emulator_clock.sync_for([str(exe), "juego.nsp"]) == 2
    data = json.loads((folder / "Config.json").read_text(encoding="utf-8"))
    assert data["system_time_zone"] == emulator_clock.local_zone() and data["system_time_offset"] == 0
    assert data["graphics_shaders_dump_path"] == ""  # lo demás, intacto
    assert emulator_clock.sync_for([str(exe)]) == 0  # ya estaba bien: no se reescribe


def test_eden_sin_reloj_propio_y_con_zona_automatica(tmp_path):
    config = tmp_path / "eden" / "user" / "config"
    config.mkdir(parents=True)
    ini = config / "qt-config.ini"
    ini.write_text("[System]\ncustom_rtc_enabled\default=false\ncustom_rtc_enabled=true\ntime_zone_index\default=false\n"
                   "time_zone_index=12\nlanguage_index=2\n", encoding="utf-8")
    exe = tmp_path / "eden" / "launch-eden.cmd"
    exe.write_text("@echo off", encoding="utf-8")
    assert emulator_clock.sync_for([str(exe), "juego.nsp"]) == 1
    text = ini.read_text(encoding="utf-8")
    assert "custom_rtc_enabled=false" in text and "custom_rtc_enabled\default=true" in text
    assert "time_zone_index=0" in text and "language_index=2" in text
    assert emulator_clock.sync_for([str(tmp_path / "dolphin" / "Dolphin.exe")]) == 0  # los demás ya usan la de la PC
