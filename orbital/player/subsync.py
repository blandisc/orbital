"""ST2 (Fernando, 26 nov 2026): los subtítulos de internet se ponen a tiempo solos.

Cerca de la mitad de los subtítulos de OpenSubtitles vienen corridos (otra copia con otro inicio, publicidad cortada).
Antes solo se arreglaba el caso de la edición a 25 cuadros; un retraso fijo de unos segundos se quedaba así.

Cómo: el mismo mpv que reproduce escucha dónde hay voz (el filtro `silencedetect` de lavfi, leído en
`af-metadata/orbsync`): sin abrir otra conexión (Real-Debrid no aguanta dos) ni bajar el audio aparte. Tras unos minutos
de oír, se compara la voz con los tiempos del subtítulo y se busca el corrimiento que mejor empata (como alass/ffsubsync,
pero solo el retraso fijo, que es el caso común). Si el empate es claro, se pone `sub-delay` y un aviso lo dice:
«Subtítulos ajustados a tu copia». Si tú ya moviste la sincronía, no se toca.
"""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Callable
from pathlib import Path

log = logging.getLogger(__name__)

LABEL = "orbsync"
FILTER = f"@{LABEL}:lavfi=[silencedetect=noise=-32dB:d=0.35]"
STEP = 0.1  # s por casilla
MAX_OFFSET = 30.0  # s que se busca hacia cada lado
LISTEN = 150.0  # s de video oído antes de decidir
GIVE_UP = 900.0  # s reales sin poder decidir: se deja como venía
MIN_SHIFT = 0.4  # s: menos que esto ya se ve a tiempo
MIN_CUES = 20  # renglones dentro de lo oído, para que el empate valga
MIN_GAIN = 0.15  # cuánto mejor que como venía (parte del total de renglones)

CUE = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})")


def _secs(h: str, m: str, s: str, ms: str) -> float:
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms.ljust(3, "0")) / 1000


def cues(text: str) -> list[tuple[float, float]]:
    """Los renglones de un .srt/.vtt: (inicio, fin) en s."""
    out = []
    for g in CUE.findall(text):
        start, end = _secs(*g[:4]), _secs(*g[4:])
        if end > start:
            out.append((start, end))
    return out


def best_offset(speech: list[tuple[float, float]], heard: tuple[float, float], subs: list[tuple[float, float]],
                max_offset: float = MAX_OFFSET) -> tuple[float, float] | None:
    """El retraso (s, lo que se le pone a `sub-delay`) con que los renglones caen mejor sobre la voz oída en `heard`, y
    cuánto mejor que sin moverlo (0–1). None si no hay con qué decidir."""
    lo, hi = heard
    if hi - lo < 30:
        return None
    n = int((hi - lo) / STEP) + 1
    voice = [0] * n
    for s, e in speech:
        for i in range(max(0, int((s - lo) / STEP)), min(n, int((e - lo) / STEP) + 1)):
            voice[i] = 1
    prefix = [0]
    for v in voice:
        prefix.append(prefix[-1] + v)

    def voiced(a: float, b: float) -> tuple[int, int]:  # casillas con voz y casillas en total, dentro de lo oído
        i, j = max(0, int((a - lo) / STEP)), min(n, int((b - lo) / STEP))
        return (prefix[j] - prefix[i], j - i) if j > i else (0, 0)

    inside = [c for c in subs if lo - max_offset < c[0] < hi + max_offset]
    if len(inside) < MIN_CUES:
        return None

    def score(d: float) -> float:  # cada renglón suma lo que cae sobre voz y resta lo que cae en silencio
        total = 0
        for s, e in inside:
            v, t = voiced(s + d, e + d)
            total += 2 * v - t
        return total

    steps = int(max_offset / STEP)
    scores = {k: score(k * STEP) for k in range(-steps, steps + 1)}
    best = max(scores, key=lambda k: scores[k])
    span = sum(voiced(s, e)[1] for s, e in inside) or 1
    gain = (scores[best] - scores[0]) / span
    return round(best * STEP, 1), gain


class Listener:
    """Junta los ratos de voz que mpv va oyendo (el filtro dice dónde empieza y acaba cada silencio)."""

    def __init__(self) -> None:
        self.speech: list[tuple[float, float]] = []
        self.start: float | None = None  # desde dónde se oye seguido
        self.last: float | None = None
        self._voice_from: float | None = None
        self._seen: tuple[str | None, str | None] = (None, None)

    def feed(self, pos: float, meta: dict | None) -> None:
        """Un vistazo: la posición del video y lo último que dijo el filtro."""
        if self.last is not None and not (0 <= pos - self.last <= 3):  # adelantaste o regresaste: se empieza de nuevo
            self.__init__()
        if self.start is None:
            self.start, self._voice_from = pos, pos
        self.last = pos
        meta = meta or {}

        def when(raw) -> float:  # el instante que dice el filtro, si es creíble; si no, ahora
            try:
                t = float(raw)
            except (TypeError, ValueError):
                return pos
            return t if abs(t - pos) < 5 else pos

        # mpv deja la última marca de cada tipo: lo nuevo es la que cambió (las dos a la vez, en su orden).
        began, ended = meta.get("lavfi.silence_start"), meta.get("lavfi.silence_end")
        events = []
        if began is not None and began != self._seen[0]:
            events.append((when(began), "quiet"))
        if ended is not None and ended != self._seen[1]:
            events.append((when(ended), "voice"))
        self._seen = (began, ended)
        for t, kind in sorted(events):
            if kind == "voice":
                self._voice_from = t
            elif self._voice_from is not None:
                if t > self._voice_from:
                    self.speech.append((self._voice_from, t))
                self._voice_from = None

    @property
    def heard(self) -> float:
        return 0.0 if self.start is None or self.last is None else self.last - self.start


def listen_and_fix(path: str, get: Callable[[str], object], command: Callable[..., object],
                   still: Callable[[], bool], apply: Callable[[float], None],
                   sleep: Callable[[float], None] = time.sleep, clock: Callable[[], float] = time.monotonic) -> float | None:
    """Oye la película mientras se ve y, si el subtítulo de `path` va corrido, lo pone a tiempo (`apply`). Da el
    retraso puesto, o None si iba bien o no se pudo saber. `still()`: sigue puesto ese subtítulo y nadie movió la
    sincronía. Corre en su hilo."""
    try:
        subs = cues(Path(path).read_text("utf-8", errors="replace"))
    except OSError:
        return None
    if len(subs) < MIN_CUES:
        return None
    command("af", "add", FILTER)
    try:
        ears, began = Listener(), clock()
        while still() and clock() - began < GIVE_UP:
            pos = get("time-pos")
            if isinstance(pos, (int, float)) and not isinstance(pos, bool):
                meta = get(f"af-metadata/{LABEL}")
                ears.feed(float(pos), meta if isinstance(meta, dict) else None)
            if ears.heard >= LISTEN:
                found = best_offset(ears.speech, (ears.start or 0.0, ears.last or 0.0), subs)
                if found is None:
                    ears = Listener()  # una parte sin diálogo: se oye otro rato
                    continue
                shift, gain = found
                log.info("Sincronía de %s: %+.1f s (mejora %.0f %%)", Path(path).name, shift, gain * 100)
                if abs(shift) >= MIN_SHIFT and gain >= MIN_GAIN and still():
                    apply(shift)
                    return shift
                return None
            sleep(0.2)
        return None
    finally:
        command("af", "remove", f"@{LABEL}")
