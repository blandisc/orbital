"""Encontrar un título por lo que se dijo (Alexa transcribe; a veces mal)."""

from __future__ import annotations

import difflib

FILLER = {"el", "la", "los", "las", "un", "una", "de", "del", "the", "a", "of",
          # Lo que se dice alrededor del título: «el juego Hades», «la app YouTube», «Hades por favor».
          "juego", "videojuego", "app", "aplicacion", "programa", "por", "favor"}


def _one_edit(a: str, b: str) -> bool:
    """¿A lo más una letra distinta, de más o de menos?"""
    if abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(x != y for x, y in zip(a, b, strict=True)) <= 1
    short, long_ = (a, b) if len(a) < len(b) else (b, a)
    return any(long_[:i] + long_[i + 1:] == short for i in range(len(long_)))


def title_match(target: str, by_name: dict):
    """El título que quisiste decir, sin adivinar de más (Alexa transcribe; a veces mal):
    - todas tus palabras están en el título, como palabras ("zelda" → The Legend of Zelda); la última
      puede ir a medias ("hollow kni"). Antes bastaba un pedazo de letras: «h» abría Hades, «super man»
      Super Mario World y «chrono cross» Chrono Trigger.
    - o el título completo se parece mucho a lo que dijiste ("hello knight" → Hollow Knight).
    Si sobra una palabra que el título no tiene («silksong»), no es ese juego."""
    words = [w for w in target.split() if w not in FILLER] or target.split()
    if not words or len(target.replace(" ", "")) < 3:
        return None

    def has_all(name: str) -> bool:
        title = name.split()
        *full, last = words
        return all(w in title for w in full) and (last in title or (len(last) >= 4 and any(t.startswith(last) for t in title)))

    found = [i for name, i in by_name.items() if has_all(name)]
    if found:
        return min(found, key=lambda i: len(i.title))
    spoken = " ".join(words)  # sin «el juego…»: así se compara solo el título
    if len(spoken) >= 5:  # una letra mal oída («jades» → Hades), no dos («hands» no es Hades)
        near = [i for name, i in by_name.items() if _one_edit(spoken, name)]
        if near:
            return min(near, key=lambda i: len(i.title))
    close = difflib.get_close_matches(spoken, list(by_name), n=1, cutoff=0.82)  # «hands» ya no es Hades
    return by_name[close[0]] if close else None
