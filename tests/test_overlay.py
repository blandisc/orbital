"""El aviso encima del juego entra como los de Orbital (toast.css): con los mismos tiempos y el mismo resorte de tokens.css,
primero el ícono, luego la tarjeta que crece desde él y al final el texto."""

import re
from pathlib import Path

from orbital import overlay

TOKENS = (Path(__file__).resolve().parents[1] / "orbital" / "web" / "styles" / "tokens.css").read_text(encoding="utf-8")


def token(name: str) -> str:
    match = re.search(rf"^\s*{re.escape(name)}:\s*([^;]+);", TOKENS, re.M)
    assert match, name
    return match.group(1).strip()


def ms(name: str) -> float:
    value = token(name)
    return float(value[:-2]) if value.endswith("ms") else float(value[:-1]) * 1000


def cubic(name: str) -> tuple[float, ...]:
    return tuple(float(v) for v in re.findall(r"[\d.]+", token(name)))


def test_the_overlay_moves_with_the_same_tokens_as_toast_css():
    assert overlay.ICON_MS == ms("--duration-notice-icon")
    assert overlay.GROW_DELAY_MS == ms("--delay-notice-grow")
    assert overlay.GROW_MS == ms("--duration-notice-grow")
    assert overlay.TEXT_DELAY_MS == ms("--delay-notice-text")
    assert overlay.ENTER_MS == ms("--duration-base")
    assert overlay.FADE_MS == ms("--duration-fast")
    assert overlay.EXIT_MS == ms("--duration-exit")
    assert overlay.EASE_OUT == cubic("--ease-out")
    assert overlay.EASE_IN == cubic("--ease-in")
    assert overlay.EASE_POP == cubic("--ease-pop")


def test_the_spring_is_the_one_sampled_in_ease_notice_grow():
    samples = [float(v) for v in re.findall(r"[\d.]+", token("--ease-notice-grow"))]
    length = overlay.GROW_MS / 1000
    for i, value in enumerate(samples[:-1]):
        assert abs(overlay.spring(length * i / (len(samples) - 1)) - value) < .002, i
    assert max(samples) > 1.02  # rebota un poco…
    assert abs(overlay.spring(length) - 1) < .003  # …y se asienta


def _ink(image, box=None):
    """Cuánto se ve (la suma de la transparencia) en la imagen o en una parte."""
    alpha = image.getchannel("A")
    return sum(i * n for i, n in enumerate((alpha.crop(box) if box else alpha).histogram()))


def test_the_icon_comes_first_then_the_card_grows_and_then_the_text():
    rem = overlay.rem_for(1920, 1080)
    layers = overlay.toast_layers("Se desconectó el Xbox", "Enciéndelo o conéctalo para seguir jugando", "!", "warn", rem)
    m, w, h = layers["margin"], layers["width"], layers["height"]
    right = (m + round(h) + 4, m, m + round(w), m + round(h))  # la tarjeta a la derecha del ícono, donde va el texto
    assert _ink(overlay.compose_toast(layers, 0)) == 0  # nada todavía
    early = overlay.compose_toast(layers, overlay.GROW_DELAY_MS - 10)
    assert _ink(early) > 0 and _ink(early, right) == 0  # solo el ícono
    growing = overlay.compose_toast(layers, overlay.GROW_DELAY_MS + 60)
    assert 0 < _ink(growing, right) < _ink(overlay.compose_toast(layers), right)  # la tarjeta crece desde el ícono
    assert _ink(layers["text"]) > 0 and _ink(overlay.compose_toast(layers, overlay.TEXT_DELAY_MS - 10)) < _ink(overlay.compose_toast(layers))
    image, margin = overlay.draw_toast("Se desconectó el Xbox", "Enciéndelo o conéctalo para seguir jugando", "!", "warn", rem)
    assert margin == m and image.tobytes() == overlay.compose_toast(layers).tobytes()  # al final, la de siempre y quieta
