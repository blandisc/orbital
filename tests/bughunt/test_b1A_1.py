from orbital import emulator_updates as eu


def test_a_manifest_that_is_not_an_object_does_not_crash(tmp_path):
    exe = tmp_path / "xemu.exe"
    exe.write_bytes(b"")
    (tmp_path / eu.MANIFEST).write_text("[]", encoding="utf-8")
    assert eu.manifest_version(exe) is None
