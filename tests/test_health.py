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
    assert lines[0].startswith("hora,ram_libre_mb") and len(lines) == 4 and lines[1].endswith(",900,54000,1300,,Zelda")
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


class FakeRelease:
    def __init__(self, ready=True):
        self.ready, self.runs = ready, 0

    def available(self):
        return self.ready

    def run(self):
        self.runs += 1
        return True


def monitor(tmp_path, dwm, **kwargs):
    readings = iter(dwm) if isinstance(dwm, list) else None
    measure = (lambda: (8000, (next(readings), 300), 9000)) if readings else (lambda: (8000, (dwm, 300), 9000))
    kwargs.setdefault("running", lambda: "")
    running = kwargs.pop("running")
    return health.HealthMonitor([].append, running, path=tmp_path / "m.csv", measure=measure, **kwargs)


def test_video_memory_is_released_only_when_nobody_is_using_the_console(tmp_path):
    # Cada juego de Switch le deja ~100 MB a DWM; con la consola sola, Orbital lo reinicia para que los suelte.
    release = FakeRelease()
    idle = {"s": 30.0}
    mon = monitor(tmp_path, 5000, idle=lambda: idle["s"], release=release)
    mon.check(now=1000)
    assert release.runs == 0  # alguien tocó el mando hace 30 s: la pantalla no parpadea
    idle["s"] = health.RELEASE_IDLE + 1
    mon.check(now=1100)
    assert release.runs == 1
    mon.check(now=1200)
    assert release.runs == 1  # como mucho una vez por hora


def test_video_memory_is_never_released_in_a_game_or_below_the_threshold(tmp_path):
    release = FakeRelease()
    monitor(tmp_path, 5000, idle=lambda: 9999, release=release, running=lambda: "Mario Kart 8").check(now=1)
    monitor(tmp_path, 5000, idle=lambda: health.RELEASE_IDLE_AWAY - 1, release=release, busy=lambda: True).check(now=1)
    monitor(tmp_path, health.RELEASE_MB - 1, idle=lambda: 9999, release=release).check(now=1)
    monitor(tmp_path, 5000, idle=lambda: 9999, release=FakeRelease(ready=False)).check(now=1)  # sin activar: nada
    assert release.runs == 0


def test_video_memory_is_released_with_another_window_in_front_after_a_long_while(tmp_path):
    """En esta consola casi siempre hay otra ventana al frente (la terminal, el navegador): antes eso bastaba para no
    liberar nunca, y DWM llegó a 15 GB (los videos se trababan). Con media hora sin que nadie toque nada, sí."""
    release = FakeRelease()
    monitor(tmp_path, 15000, idle=lambda: health.RELEASE_IDLE_AWAY + 1, release=release, busy=lambda: True).check(now=1)
    assert release.runs == 1


def test_before_a_video_dwm_is_released_only_when_it_holds_too_much():
    from orbital import dwm_release

    runs, waits = [], []
    real = dwm_release.available, dwm_release.run
    dwm_release.available, dwm_release.run = (lambda: True), (lambda: runs.append(1) or True)
    try:
        assert not dwm_release.fresh_for_video(measure=lambda: (1800, 300), sleep=waits.append)  # limpio: nada
        assert not dwm_release.fresh_for_video(measure=lambda: None, sleep=waits.append)  # no se pudo medir: nada
        assert dwm_release.fresh_for_video(measure=lambda: (12700, 300), sleep=waits.append)
        assert runs == [1] and waits == [dwm_release.BACK_AFTER]  # espera a que Windows vuelva a dibujar
        dwm_release.available = lambda: False
        assert not dwm_release.fresh_for_video(measure=lambda: (12700, 300), sleep=waits.append)  # sin activar
    finally:
        dwm_release.available, dwm_release.run = real


def test_sudden_dwm_growth_logs_who_was_in_front_and_measures_every_minute(tmp_path, caplog, monkeypatch):
    monkeypatch.setattr(health, "top_memory", lambda limit=3: [("Eden", 6000)])
    mon = monitor(tmp_path, [600, 700, 7400], foreground=lambda: "Ryujinx.exe — Kirby")
    mon.check(now=0)
    mon.check(now=300)
    assert mon.fast_until < 300  # +100 MB: normal
    with caplog.at_level("WARNING"):
        mon.check(now=600)
    assert mon.fast_until == 600 + health.FAST_FOR
    assert "Ryujinx.exe — Kirby" in caplog.text and "+6700 MB" in caplog.text


def test_leak_warning_offers_to_release_without_restarting(tmp_path):
    notes = []
    mon = health.HealthMonitor(notes.append, lambda: "", path=tmp_path / "m.csv", measure=lambda: (8000, (9000, 300), 9000),
                               release=FakeRelease(ready=False), busy=lambda: True)
    mon.check(now=1)
    assert mon.pending["restart"] and mon.pending["release"] == "setup"


def test_old_csv_without_the_orbital_column_is_set_aside(tmp_path):
    path = tmp_path / "memoria.csv"
    path.write_text("hora,ram_libre_mb,dwm_compartida_mb,dwm_dedicada_mb,abierto\n2026-10-24 16:23:18,799,52511,16082,\n",
                    encoding="utf-8")
    health.append_sample(path, 0, 900, (600, 300), "Zelda", orbital_mb=780)
    assert path.read_text(encoding="utf-8").splitlines()[0] == health.CSV_HEADER.strip()
    assert path.read_text(encoding="utf-8").splitlines()[1].endswith(",900,600,300,780,Zelda")
    assert "52511" in path.with_suffix(".old.csv").read_text(encoding="utf-8")
