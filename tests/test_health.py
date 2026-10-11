from orbital import health


def test_samples_go_to_csv_and_warning_is_rate_limited(tmp_path):
    notes = []
    readings = iter([(900, (54000, 1300)), (900, (54000, 1300)), (6000, (300, 200))])
    mon = health.HealthMonitor(notes.append, lambda: "Zelda", path=tmp_path / "memoria.csv",
                               measure=lambda: next(readings))
    assert mon.check(now=1000)  # memoria casi llena: avisa
    assert not mon.check(now=1500)  # dentro de la hora: no repite
    assert not mon.check(now=9000)  # ya hay memoria
    lines = (tmp_path / "memoria.csv").read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("hora,ram_libre_mb") and len(lines) == 4 and lines[1].endswith(",900,54000,1300,Zelda")
    assert len(notes) == 1 and "reinicia" in notes[0]["message"]


def test_needs_warning():
    assert health.needs_warning(1000, None)
    assert health.needs_warning(5000, (9000, 0))
    assert not health.needs_warning(5000, (500, 300))
    assert not health.needs_warning(None, None)


def test_real_measurement_does_not_crash():
    free = health.free_ram_mb()
    assert free is None or free > 0
