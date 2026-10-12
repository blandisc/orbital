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
    assert len(notes) == 1 and notes[0]["type"] == "health" and "suspender no lo arregla" in notes[0]["message"]


def test_needs_warning():
    assert health.needs_warning(400, None)  # RAM disponible casi en cero
    assert not health.needs_warning(1200, None)  # poca RAM libre sola no: Windows pagina
    assert health.needs_warning(5000, None, commit_room=1500)  # sin margen hasta el límite: sí
    assert health.needs_warning(5000, (9000, 0))
    assert not health.needs_warning(5000, (500, 300), commit_room=8000)
    assert not health.needs_warning(None, None)


def test_real_measurement_does_not_crash():
    free = health.free_ram_mb()
    assert free is None or free > 0


def test_warning_message_explains_the_dwm_leak():
    assert "53 GB" in health.warning_message(900, (54000, 1300))  # 54000 MB
    full = health.warning_message(900, (300, 100), [("Eden", 6880), ("la app de Claude", 4700)])
    assert "Eden 6,7 GB" in full and "Cierra" in full and "Reinicia" not in full


def test_full_memory_from_open_programs_does_not_offer_restart(tmp_path, monkeypatch):
    notes = []
    mon = health.HealthMonitor(notes.append, lambda: "Mario Party", path=tmp_path / "m.csv",
                               measure=lambda: (1200, (2000, 500), 900))

    monkeypatch.setattr(health, "top_memory", lambda limit=3: [("Eden", 6700)])
    assert mon.check(now=10)
    assert notes[0]["restart"] is False and "Eden" in notes[0]["message"]

def test_commit_room_reads():
    room = health.commit_room_mb()
    assert room is None or room >= 0


def test_warning_waits_while_you_are_in_a_game_and_comes_out_when_you_return(tmp_path):
    """En pleno juego o video el aviso no llega a la interfaz (nada debe asomarse sobre el juego):
    se guarda y sale al volver a Orbital."""
    notes = []
    away = {"value": True}
    mon = health.HealthMonitor(notes.append, lambda: "Futurama", path=tmp_path / "m.csv",
                               measure=lambda: (530, (9918, 777), 2434), busy=lambda: away["value"])
    assert mon.check(now=1000)  # memoria baja: avisaría…
    assert notes == [] and mon.pending is not None and "10 GB" in mon.pending["message"]
    assert not mon.flush(now=1010)  # sigues en el video: sigue esperando
    assert notes == []
    away["value"] = False
    assert mon.flush(now=1020)  # volviste a Orbital: ahora sí
    assert len(notes) == 1 and notes[0]["type"] == "health" and notes[0]["restart"] is True
    assert mon.pending is None and not mon.flush(now=1030)  # no se repite
    assert not mon.check(now=1500)  # la hora sin repetir cuenta desde que lo viste
    assert len(notes) == 1


def test_pending_warning_is_dropped_when_memory_is_fine_again(tmp_path):
    notes = []
    readings = iter([(400, (300, 100), 5000), (6000, (300, 100), 9000)])
    mon = health.HealthMonitor(notes.append, lambda: "Zelda", path=tmp_path / "m.csv",
                               measure=lambda: next(readings), busy=lambda: True)
    assert mon.check(now=10) and mon.pending is not None
    assert not mon.check(now=400)  # se liberó memoria mientras jugabas: el aviso ya no aplica
    assert mon.pending is None and notes == []


def test_pending_warning_keeps_the_latest(tmp_path):
    notes = []
    readings = iter([(400, (300, 100), 5000), (300, (9000, 100), 1500)])
    mon = health.HealthMonitor(notes.append, lambda: "", path=tmp_path / "m.csv",
                               measure=lambda: next(readings), busy=lambda: True)
    mon.check(now=10)
    mon._last_warning = float("-inf")  # como si hubiera pasado la hora
    mon.check(now=20)
    assert mon.pending["restart"] is True  # la medición más reciente (la fuga de DWM) manda
