"""V3 · el servidor calcula el tono del fondo igual que el cliente (orbital/web/js/core/color.js)."""

import base64
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from orbital import art_tone

ROOT = Path(__file__).parents[1]
IMAGES = sorted((ROOT / "tests" / "fixtures" / "art-tone").glob("*.*"))
COLOR_JS = (ROOT / "orbital" / "web" / "js" / "core" / "color.js").as_uri()

# El mismo código del cliente, en Node, sobre los mismos píxeles de 24 × 24: lo que diría backdrop.js.
CLIENT = """
const { dominantHue, paletteFor } = await import(process.argv[1]);
const pixels = Uint8ClampedArray.from(Buffer.from(process.argv[2], "base64"));
const d = dominantHue(pixels);
console.log(JSON.stringify({ dominant: d, palette: paletteFor(d) }));
"""


def client(pixels: bytes) -> dict:
    out = subprocess.run(["node", "--input-type=module", "-e", CLIENT, COLOR_JS, base64.b64encode(pixels).decode()],
                         capture_output=True, text=True, timeout=30, check=True)
    return json.loads(out.stdout)


def test_there_are_three_sample_images():
    assert len(IMAGES) == 3


@pytest.mark.skipif(shutil.which("node") is None, reason="sin Node no se puede correr el cliente")
@pytest.mark.parametrize("image", IMAGES, ids=lambda p: p.name)
def test_the_tone_matches_the_client(image, tmp_path):
    pixels = art_tone.sample_pixels(image, tmp_path)
    assert pixels is not None and len(pixels) == art_tone.SAMPLE * art_tone.SAMPLE * 4
    ours = art_tone.dominant_hue(pixels)
    theirs = client(pixels)
    assert ours is not None and theirs["dominant"] is not None
    assert ours["hue"] == pytest.approx(theirs["dominant"]["hue"], abs=1e-9)
    assert ours["saturation"] == pytest.approx(theirs["dominant"]["saturation"], abs=1e-9)
    tone = art_tone.palette_for(ours)
    assert (tone["tint"], tone["accent"]) == (theirs["palette"]["tint"], theirs["palette"]["accent"])


def test_what_each_sample_looks_like(tmp_path):
    hues = {p.stem: art_tone.tone_of(p, tmp_path)["hue"] for p in IMAGES}
    assert 0 <= hues["atardecer"] < 60 or hues["atardecer"] > 270  # naranja o morado, nunca verde
    assert 90 <= hues["bosque"] < 150  # verde
    assert hues["gris-con-rojo"] < 15 or hues["gris-con-rojo"] > 345  # el rojo gana; lo gris no cuenta


def test_gray_art_is_neutral_and_rounding_is_javascripts():
    assert art_tone.palette_for(art_tone.dominant_hue(bytes([128, 128, 128, 255] * 16))) == {"neutral": True}
    assert art_tone._js_round(2.5) == 3 and art_tone._js_round(-0.5) == 0  # Python redondearía 2.5 a 2


def test_tones_are_measured_once_and_kept_on_disk(tmp_path):
    tones = art_tone.ArtTones(tmp_path)
    image = IMAGES[0]
    assert tones.peek(image) is None  # peek nunca mide
    assert tones.warm([image, tmp_path / "no-existe.jpg"]) == 1 and tones.warm([image]) == 0
    again = art_tone.ArtTones(tmp_path)  # otro arranque: lo lee del disco
    assert again.peek(image) == tones.peek(image) and "tint" in again.peek(image)


def test_the_library_sends_the_tone_only_when_known(library, tmp_path):
    item = next(i for i in library.store.all() if i.source == "steam")
    item.hero_path = str(IMAGES[1])
    assert "art_tone" not in library.describe(item)  # sin medir (y en pruebas no se mide solo)
    library.tones = art_tone.ArtTones(tmp_path)
    library.tones.warm([IMAGES[1]])
    assert library.describe(item)["art_tone"] == art_tone.tone_of(IMAGES[1], tmp_path)


def test_two_warmups_at_startup_measure_each_cover_once(tmp_path, monkeypatch):
    """Revisión del 11 nov 2026: el servidor y el escaneo del catálogo piden medir casi juntos; cada portada se mide una
    sola vez y las que trae la segunda petición también quedan medidas."""
    import threading
    import time

    copies = []
    for n in range(6):
        copy = tmp_path / f"art{n}{IMAGES[n % len(IMAGES)].suffix}"
        shutil.copyfile(IMAGES[n % len(IMAGES)], copy)
        copies.append(copy)
    measured: list[Path] = []
    real = art_tone.tone_of
    started = threading.Event()

    def slow_tone(path, thumbs_dir=None):
        measured.append(path)
        started.set()
        time.sleep(0.05)  # medir tarda: la segunda petición llega a media medición
        return real(path, thumbs_dir)

    monkeypatch.setattr(art_tone, "tone_of", slow_tone)
    tones = art_tone.ArtTones(tmp_path / "thumbs")
    first = threading.Thread(target=tones.warm, args=(copies[:4],))
    first.start()
    started.wait(5)
    assert tones.warm(copies) == 0  # la segunda no mide a la par: le deja sus portadas a la primera
    first.join(10)
    assert sorted(measured) == sorted(copies)  # cada una, una vez (también las dos nuevas)
    assert all(tones.peek(p) for p in copies)
    assert tones.warm(copies) == 0 and len(measured) == 6  # lo ya medido no se repite
