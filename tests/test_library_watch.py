"""Juegos nuevos con Orbital abierto: el vigilante de carpetas (library_watch.py) y el reescaneo que avisa a la tele."""

from pathlib import Path

from orbital.library_watch import NAMES_ONLY, LibraryWatcher, folder_signature


def test_the_signature_sees_new_files_and_files_still_growing(tmp_path):
    roms = tmp_path / "roms"
    (roms / "sub").mkdir(parents=True)
    (roms / "a.iso").write_bytes(b"1")
    before = folder_signature([(roms, True)])
    (roms / "sub" / "b.iso").write_bytes(b"12")
    assert folder_signature([(roms, True)]) != before  # uno nuevo, también en una subcarpeta
    grown = folder_signature([(roms, True)])
    (roms / "sub" / "b.iso").write_bytes(b"12345")  # una copia que sigue creciendo
    assert folder_signature([(roms, True)]) != grown
    assert folder_signature([(tmp_path / "no-existe", True)]) == frozenset()  # una carpeta que falta no truena


def test_the_watcher_waits_until_the_copy_finishes_then_rescans_once(tmp_path):
    roms = tmp_path / "roms"
    roms.mkdir()
    calls = []
    watcher = LibraryWatcher(lambda: [(roms, False)], lambda: calls.append(1))
    watcher._known = watcher._signature()
    assert watcher.check() is False and calls == []  # nada cambió
    game = roms / "Dante's Inferno.iso"
    game.write_bytes(b"x" * 10)
    assert watcher.check() is False  # cambió: se espera una vuelta (puede seguir copiándose)
    game.write_bytes(b"x" * 20)
    assert watcher.check() is False  # siguió creciendo: aún no
    assert watcher.check() is True and calls == [1]  # ya no cambia: se reescanea, una sola vez
    assert watcher.check() is False and calls == [1]


def test_a_scan_from_elsewhere_is_not_repeated(tmp_path):
    roms = tmp_path / "roms"
    roms.mkdir()
    calls = []
    watcher = LibraryWatcher(lambda: [(roms, False)], lambda: calls.append(1))
    watcher._known = watcher._signature()
    (roms / "nuevo.iso").write_bytes(b"x")
    watcher.accept()  # «Buscar juegos nuevos» ya lo encontró
    assert not watcher.check() and not watcher.check() and calls == []


def test_a_game_copied_with_orbital_open_appears_and_the_tv_is_told(library):
    events = []
    library.events.publish = events.append
    roms = Path(library.config.emulators[0].rom_dirs[0])
    assert (roms, True) in library.watched_folders()
    assert any(str(f).endswith("steamapps") and mode == NAMES_ONLY for f, mode in library.watched_folders())  # también Steam (solo nombres)
    (roms / "Earthbound (USA).sfc").write_bytes(b"")
    new = library.rescan_for_new()
    assert [i.title for i in new] == ["Earthbound"]
    assert {"type": "library-changed"} in events
    assert any(e.get("type") == "toast" and "Earthbound" in e.get("message", "") for e in events)
    assert library.rescan_for_new() == []  # sin cambios: no avisa otra vez


def test_steam_rewriting_its_own_files_is_not_a_new_game(tmp_path):
    apps = tmp_path / "steamapps"
    apps.mkdir()
    (apps / "appmanifest_1.acf").write_text("a")
    before = folder_signature([(apps, NAMES_ONLY)])
    (apps / "appmanifest_1.acf").write_text("reescrito por Steam")
    assert folder_signature([(apps, NAMES_ONLY)]) == before
    (apps / "appmanifest_2.acf").write_text("b")  # un juego recién instalado
    assert folder_signature([(apps, NAMES_ONLY)]) != before
