"""ST2: los subtítulos de internet se ponen a tiempo solos (orbital/player/subsync.py)."""

import random

from orbital.player import subsync


def _scene(seed: int = 7, length: float = 400.0):
    """Diálogos de mentira: ratos de voz y, para cada uno, su renglón (a tiempo)."""
    rng = random.Random(seed)
    t, speech = 5.0, []
    while t < length:
        talk = rng.uniform(1.0, 4.0)
        speech.append((t, t + talk))
        t += talk + rng.uniform(0.6, 5.0)
    return speech


def _srt(cues, shift: float) -> str:
    def ts(x: float) -> str:
        ms = int(round(x * 1000))
        return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"
    return "\n".join(f"{i + 1}\n{ts(s + shift)} --> {ts(e + shift)}\nHola\n" for i, (s, e) in enumerate(cues))


def test_finds_a_fixed_delay():
    speech = _scene()
    subs = subsync.cues(_srt(speech, -2.5))  # el subtítulo sale 2.5 s antes
    shift, gain = subsync.best_offset(speech, (0.0, 400.0), subs)
    assert abs(shift - 2.5) <= 0.2
    assert gain >= subsync.MIN_GAIN


def test_one_already_on_time_stays():
    speech = _scene(3)
    shift, _ = subsync.best_offset(speech, (0.0, 400.0), subsync.cues(_srt(speech, 0.0)))
    assert abs(shift) < subsync.MIN_SHIFT


def test_listener_reads_the_filter():
    ears = subsync.Listener()
    ears.feed(10.0, None)
    ears.feed(11.0, {"lavfi.silence_start": "11.0"})
    ears.feed(12.0, {"lavfi.silence_end": "12.0", "lavfi.silence_start": "11.0"})
    ears.feed(14.0, {"lavfi.silence_start": "14.0"})
    assert ears.speech == [(10.0, 11.0), (12.0, 14.0)]
    ears.feed(80.0, None)  # adelantaste: se empieza de nuevo
    assert ears.speech == [] and ears.heard == 0


def test_listens_while_playing_and_fixes(tmp_path):
    """De punta a punta con un mpv de mentira: oye, pone el retraso, avisa y quita el filtro."""
    speech = _scene(11)
    path = tmp_path / "s.srt"
    path.write_text(_srt(speech, 3.0), "utf-8")  # sale 3 s tarde
    clock = {"t": 0.0}
    sent, applied = [], []

    def get(prop):
        pos = clock["t"]
        if prop == "time-pos":
            return pos
        last = None
        for s, e in speech:
            if s <= pos:
                last = {"lavfi.silence_end": str(s)} if pos < e else {"lavfi.silence_start": str(e), "lavfi.silence_end": str(s)}
        return last

    def sleep(dt):
        clock["t"] += dt

    shift = subsync.listen_and_fix(str(path), get, lambda *a: sent.append(a), lambda: True, applied.append,
                                   sleep=sleep, clock=lambda: clock["t"])
    assert shift is not None and abs(shift + 3.0) <= 0.3
    assert applied == [shift]
    assert sent[0][:2] == ("af", "add") and sent[-1] == ("af", "remove", "@orbsync")


def test_your_own_sync_wins(tmp_path):
    """Si moviste la sincronía (o cambiaste de subtítulo), ya no se toca."""
    speech = _scene(5)
    path = tmp_path / "s.srt"
    path.write_text(_srt(speech, 3.0), "utf-8")
    applied = []
    out = subsync.listen_and_fix(str(path), lambda p: 1.0, lambda *a: None, lambda: False, applied.append,
                                 sleep=lambda dt: None, clock=lambda: 0.0)
    assert out is None and applied == []
