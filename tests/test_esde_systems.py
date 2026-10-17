from __future__ import annotations

from dataclasses import replace

from orbital.library import emulators, esde_systems

SYSTEMS = r"""<?xml version="1.0"?><systemList>
  <system><name>n64</name><fullname>Nintendo 64</fullname><extension>.n64 .N64 .z64 .lnk</extension>
    <command label="Mupen64Plus-Next">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%\mupen64plus_next_libretro.dll %ROM%</command>
    <command label="ares (Standalone)">%EMULATOR_ARES% --fullscreen --system "Nintendo 64" %ROM%</command>
    <command label="Shortcut">%HIDEWINDOW% %ESCAPESPECIALS% %EMULATOR_OS-SHELL% /C %ROM%</command></system>
  <system><name>snes</name><fullname>Nintendo SNES</fullname><extension>.sfc</extension>
    <command label="Snes9x - Current">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%\snes9x_libretro.dll %ROM%</command></system>
  <system><name>ps3</name><fullname>Sony PlayStation 3</fullname><extension>.ps3</extension>
    <command label="RPCS3 Game Serial (Standalone)">%EMULATOR_RPCS3% --no-gui %RPCS3_GAMEID%:%INJECT%=%BASENAME%.ps3</command></system>
  <system><name>gba</name><fullname>Game Boy Advance</fullname><extension>.gba</extension>
    <command label="mGBA (Standalone)">%EMULATOR_MGBA% -f %ROM%</command></system>
</systemList>"""

RULES = r"""<?xml version="1.0"?><ruleList>
  <emulator name="RETROARCH"><rule type="staticpath"><entry>%ESPATH%\Emulators\RetroArch\retroarch.exe</entry></rule></emulator>
  <emulator name="ARES"><rule type="staticpath"><entry>%ESPATH%\Emulators\ares*\ares.exe</entry></rule></emulator>
  <emulator name="RPCS3"><rule type="staticpath"><entry>%ESPATH%\Emulators\RPCS3\rpcs3.exe</entry></rule></emulator>
  <emulator name="MGBA"><rule type="staticpath"><entry>%ESPATH%\Emulators\mGBA\mGBA.exe</entry></rule></emulator>
  <core name="RETROARCH"><rule type="corepath"><entry>%EMUPATH%\cores</entry></rule></core>
</ruleList>"""


def esde(tmp_path, cores=("mupen64plus_next_libretro.dll",)):
    root = tmp_path / "ES-DE"
    (root / "resources" / "systems" / "windows").mkdir(parents=True)
    (root / "resources" / "systems" / "windows" / "es_systems.xml").write_text(SYSTEMS, encoding="utf-8")
    (root / "resources" / "systems" / "windows" / "es_find_rules.xml").write_text(RULES, encoding="utf-8")
    for exe in ("RetroArch/retroarch.exe", "ares-v140/ares.exe", "RPCS3/rpcs3.exe"):
        (root / "Emulators" / exe).parent.mkdir(parents=True, exist_ok=True)
        (root / "Emulators" / exe).write_bytes(b"")
    (root / "Emulators" / "RetroArch" / "cores").mkdir()
    for core in cores:
        (root / "Emulators" / "RetroArch" / "cores" / core).write_bytes(b"")
    for system, rom in (("n64", "Mario 64.z64"), ("snes", "Zelda.sfc"), ("ps3", "Juego.ps3"), ("gba", "Pokemon.gba")):
        (root / "ROMs" / system).mkdir(parents=True)
        (root / "ROMs" / system / rom).write_bytes(b"")
    return root


def test_systems_orbital_does_not_know_come_from_esde_rules(tmp_path):
    root = esde(tmp_path)
    found = esde_systems.configs(root, None, root / "ROMs", covered={"gba"})
    assert [(c.id, c.esde_label) for c in found] == [("esde-n64", "Mupen64Plus-Next"), ("esde-n64-1", "ares")]
    retro, ares = found
    cores = str(root / "Emulators" / "RetroArch" / "cores")
    assert retro.args == ["-L", cores + "\\mupen64plus_next_libretro.dll", "{rom}"]
    assert ares.args == ["--fullscreen", "--system", "Nintendo 64", "{rom}"] and ares.executable.endswith("ares.exe")
    assert retro.name == "Nintendo 64" and retro.extensions == [".n64", ".z64"]  # los .lnk los abre Orbital por su cuenta
    # snes: RetroArch sí, pero sin el núcleo de Snes9x no se puede; ps3: RPCS3 por serial no se sabe armar; gba: ya cubierto


def test_the_system_emulator_chosen_in_esde_goes_first(tmp_path):
    root = esde(tmp_path)
    found = esde_systems.configs(root, None, root / "ROMs", covered={"gba"}, preferred={"n64": "ares (Standalone)"})
    assert found[0].esde_label == "ares"


def test_custom_systems_win_and_the_game_opens_with_its_rom(tmp_path):
    root = esde(tmp_path)
    custom = root / "ES-DE" / "custom_systems"
    custom.mkdir(parents=True)
    (custom / "es_systems.xml").write_text("""<systemList><system><name>n64</name><fullname>N64 mío</fullname>
      <extension>.z64</extension><command label="ares (Standalone)">%EMULATOR_ARES% -f %ROM%</command></system></systemList>""",
                                            encoding="utf-8")
    [emu] = esde_systems.configs(root, custom, root / "ROMs", covered={"gba", "snes", "ps3"})
    assert emu.name == "N64 mío" and emu.args == ["-f", "{rom}"]
    [item] = emulators.scan(replace(emu, rom_dirs=[str(root / "ROMs" / "n64")]))
    assert item.title == "Mario 64" and item.runners[0].argv[-1].endswith("Mario 64.z64")


def test_without_esde_files_nothing_breaks(tmp_path):
    assert esde_systems.configs(tmp_path, None, tmp_path, set()) == []
    assert esde_systems.split_command('%EMULATOR_ARES% --system "Nintendo 64" %ROM%') == ["%EMULATOR_ARES%", "--system", "Nintendo 64", "%ROM%"]
