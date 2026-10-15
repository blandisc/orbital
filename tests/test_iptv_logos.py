"""Logos de los canales: parejos, legibles sobre el fondo oscuro, en disco y sin salir a la red local."""

from __future__ import annotations

import io
import threading
import urllib.error

import pytest
from PIL import Image, ImageDraw

from orbital.library import iptv_logos
from orbital.library.iptv_logos import BOX, LogoCache, LogoError, prepare

REAL_DOWNLOAD = iptv_logos.download_logo  # conftest lo cambia por uno que no sale a internet; aquí se prueba el de verdad


def png(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


def logo(color, size=(400, 160), margin=0, background=(0, 0, 0, 0)):
    """Un «logo» de mentiras: un óvalo de `color` sobre `background`, con `margin` px de aire alrededor."""
    image = Image.new("RGBA", (size[0] + 2 * margin, size[1] + 2 * margin), background)
    ImageDraw.Draw(image).ellipse((margin, margin, margin + size[0] - 1, margin + size[1] - 1), fill=color)
    return image


def result(data: bytes) -> Image.Image:
    return Image.open(io.BytesIO(prepare(data))).convert("RGBA")


# --- parejar ---------------------------------------------------------------------------------
def test_un_logo_claro_sobre_transparente_no_lleva_placa_y_se_recorta():
    out = result(png(logo((255, 255, 255, 255), margin=60)))  # blanco, con aire transparente alrededor
    assert out.size[0] <= BOX[0] and out.size[1] <= BOX[1]
    assert round(out.width / out.height, 1) == round(400 / 160, 1)  # sin el aire: la proporción del dibujo
    assert out.getpixel((0, 0))[3] == 0  # la esquina sigue transparente: no hay placa


def test_un_logo_oscuro_va_sobre_una_placa_clara_para_leerse_en_el_fondo_oscuro():
    out = result(png(logo((10, 10, 10, 255))))  # negro sobre transparente
    assert out.getpixel((0, 0))[3] == 0  # esquinas redondeadas de la placa
    plate = out.getpixel((out.width // 2, 8))  # arriba, dentro de la placa y fuera del dibujo
    assert plate[3] == 255 and min(plate[:3]) > 220  # papel, no negro
    assert out.getpixel((out.width // 2, out.height // 2))[:3] == (10, 10, 10)  # el logo, encima
    assert out.width <= BOX[0] and out.height <= BOX[1]


def test_un_logo_de_color_medio_no_lleva_placa():
    out = result(png(logo((0, 120, 200, 255))))  # azul tipo Disney Jr.
    assert out.getpixel((0, 0))[3] == 0


def test_un_logo_con_fondo_propio_se_queda_como_es_con_las_esquinas_redondeadas():
    out = result(png(logo((20, 40, 160, 255), background=(255, 255, 255, 255), margin=10)))  # cuadro blanco con un óvalo
    assert out.getpixel((0, 0))[3] == 0  # esquina redondeada
    assert out.getpixel((out.width // 2, 2))[:4] == (255, 255, 255, 255)  # el fondo blanco propio se respeta
    assert out.getpixel((out.width // 2, out.height // 2))[:3] == (20, 40, 160)


def test_un_logo_enorme_se_reduce_y_uno_chiquito_se_agranda_hasta_el_doble():
    big = result(png(logo((255, 255, 255, 255), size=(1600, 800))))
    assert big.size == (320, 160)
    tiny = result(png(logo((255, 255, 255, 255), size=(50, 20))))
    assert tiny.size == (100, 40)  # el doble y no más (borroso)


def test_lo_que_no_es_un_logo_se_rechaza_con_su_motivo():
    with pytest.raises(LogoError, match="no es una imagen"):
        prepare(b"<html>404</html>")
    with pytest.raises(LogoError, match="transparente"):
        prepare(png(Image.new("RGBA", (200, 100), (0, 0, 0, 0))))
    with pytest.raises(LogoError, match="muy chico"):
        prepare(png(Image.new("RGBA", (3, 3), (255, 255, 255, 255))))


def test_una_imagen_gigante_no_se_decodifica(monkeypatch):
    monkeypatch.setattr(iptv_logos, "MAX_PIXELS", 1000)
    with pytest.raises(LogoError, match="demasiado grande"):
        prepare(png(logo((255, 255, 255, 255), size=(100, 100))))


def test_la_placa_usa_el_papel_de_la_paleta():
    assert iptv_logos._plate_color() == (0xF5, 0xF4, 0xF0)


# --- a dónde se puede pedir ---------------------------------------------------------------------
@pytest.mark.parametrize("url, ok", [
    ("https://i.imgur.com/abc.png", True), ("http://logos.example.mx/a.png", True),
    ("http://localhost/a.png", False), ("http://127.0.0.1:8710/api/stop", False), ("http://192.168.1.1/admin.png", False),
    ("http://10.0.0.5/a.png", False), ("http://169.254.169.254/latest/meta-data", False), ("http://[::1]/a.png", False),
    ("http://impresora.local/a.png", False), ("file:///C:/Windows/win.ini", False), ("ftp://x.example/a.png", False), ("", False),
])
def test_solo_se_piden_direcciones_de_internet(url, ok):
    assert iptv_logos.public_host(url) is ok


def test_download_no_toca_la_red_local(monkeypatch):
    called = []
    monkeypatch.setattr(iptv_logos.urllib.request, "urlopen", lambda *a, **k: called.append(a))
    with pytest.raises(LogoError, match="no permitida"):
        REAL_DOWNLOAD("http://192.168.1.1/logo.png")
    assert called == []


def test_download_corta_lo_demasiado_pesado(monkeypatch):
    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self, n):
            return b"x" * 64 * 1024  # no se acaba nunca

        read1 = read

    monkeypatch.setattr(iptv_logos.urllib.request, "urlopen", lambda *a, **k: Response())
    with pytest.raises(ValueError, match="demasiado grande"):
        REAL_DOWNLOAD("https://logos.example.mx/enorme.png")


# --- la caché en disco -----------------------------------------------------------------------
GOOD = png(logo((255, 255, 255, 255)))


class Net:
    def __init__(self, pages=None, error=None) -> None:
        self.pages, self.error, self.asked = pages or {}, error, []

    def __call__(self, url: str) -> bytes:
        self.asked.append(url)
        if self.error:
            raise self.error
        return self.pages[url]


def test_se_baja_una_vez_se_guarda_parejo_y_la_segunda_ya_no_pide_nada(tmp_path):
    net = Net({"https://logos.example.mx/a.png": GOOD})
    cache = LogoCache(tmp_path, download=net)
    path = cache.get("https://logos.example.mx/a.png")
    assert path is not None and path.parent == tmp_path and path.suffix == ".png"
    with Image.open(path) as saved:
        assert saved.size[0] <= BOX[0]
    assert cache.get("https://logos.example.mx/a.png") == path and net.asked == ["https://logos.example.mx/a.png"]
    assert LogoCache(tmp_path, download=Net()).get("https://logos.example.mx/a.png") == path  # y sobrevive a reiniciar Orbital


def test_un_logo_que_no_baja_se_anota_y_no_se_insiste_hasta_el_dia_siguiente(tmp_path, monkeypatch):
    net = Net(error=urllib.error.URLError("sin red"))
    cache = LogoCache(tmp_path, download=net)
    assert cache.get("https://logos.example.mx/b.png") is None and len(net.asked) == 1
    assert cache.get("https://logos.example.mx/b.png") is None and len(net.asked) == 1  # no insiste en cada pantalla
    monkeypatch.setattr(iptv_logos, "RETRY_AFTER", 0)
    net.error, net.pages = None, {"https://logos.example.mx/b.png": GOOD}
    assert cache.get("https://logos.example.mx/b.png") is not None and len(net.asked) == 2  # pasó el día: otra vez


def test_un_fallo_pasajero_se_reintenta_pronto_y_uno_definitivo_no(tmp_path, monkeypatch):
    """Wikimedia pide calma con un 429 cuando se le piden muchos de golpe: eso no es «este logo no existe»."""
    clock = [1000.0]
    monkeypatch.setattr(iptv_logos.time, "time", lambda: clock[0])
    busy = Net(error=urllib.error.HTTPError("https://logos.example.mx/g.png", 429, "Too Many Requests", {}, io.BytesIO(b"")))
    cache = LogoCache(tmp_path, download=busy)
    assert cache.get("https://logos.example.mx/g.png") is None and len(busy.asked) == 1
    clock[0] += iptv_logos.RETRY_SOON + 1  # un cuarto de hora después
    busy.error, busy.pages = None, {"https://logos.example.mx/g.png": GOOD}
    assert cache.get("https://logos.example.mx/g.png") is not None and len(busy.asked) == 2
    gone = Net(error=urllib.error.HTTPError("https://logos.example.mx/h.png", 404, "Not Found", {}, io.BytesIO(b"")))
    cache = LogoCache(tmp_path, download=gone)
    assert cache.get("https://logos.example.mx/h.png") is None
    clock[0] += iptv_logos.RETRY_SOON + 1
    assert cache.get("https://logos.example.mx/h.png") is None and len(gone.asked) == 1  # un 404 no se vuelve a pedir en el día
    clock[0] += iptv_logos.RETRY_AFTER
    assert cache.get("https://logos.example.mx/h.png") is None and len(gone.asked) == 2


def test_una_respuesta_que_no_es_imagen_tambien_se_anota(tmp_path):
    net = Net({"https://logos.example.mx/c.png": b"<html>Acceso denegado</html>"})
    cache = LogoCache(tmp_path, download=net)
    assert cache.get("https://logos.example.mx/c.png") is None
    assert cache.get("https://logos.example.mx/c.png") is None and len(net.asked) == 1


def test_dos_pantallas_pidiendo_el_mismo_logo_lo_bajan_una_sola_vez(tmp_path):
    gate, started = threading.Event(), threading.Event()
    asked = []

    def slow(url):
        asked.append(url)
        started.set()
        gate.wait(2)
        return GOOD

    cache = LogoCache(tmp_path, download=slow)
    paths = []
    threads = [threading.Thread(target=lambda: paths.append(cache.get("https://logos.example.mx/d.png"))) for _ in range(4)]
    for t in threads:
        t.start()
    assert started.wait(2)
    gate.set()
    for t in threads:
        t.join(5)
    assert len(asked) == 1 and len(set(paths)) == 1 and paths[0] is not None


def test_sin_carpeta_o_sin_direccion_no_hay_logo(tmp_path):
    assert LogoCache(None, download=Net()).get("https://logos.example.mx/a.png") is None
    assert LogoCache(tmp_path, download=Net()).get(None) is None
    assert LogoCache(tmp_path, download=Net()).get("") is None


def test_put_guarda_uno_que_ya_se_tiene_y_rechaza_basura(tmp_path):
    cache = LogoCache(tmp_path, download=Net())
    assert cache.put("https://logos.example.mx/e.png", GOOD) is not None
    assert cache.get("https://logos.example.mx/e.png") is not None  # y get lo encuentra sin bajarlo
    assert cache.put("https://logos.example.mx/f.png", b"nada") is None


def test_warm_baja_los_que_faltan_y_dice_cuantos_hay(tmp_path):
    net = Net({"https://logos.example.mx/1.png": GOOD, "https://logos.example.mx/2.png": GOOD})
    cache = LogoCache(tmp_path, download=net)
    urls = ["https://logos.example.mx/1.png", "https://logos.example.mx/2.png", "https://logos.example.mx/1.png", None, ""]
    assert cache.warm(urls) == 2 and len(net.asked) == 2  # sin repetidos ni vacíos
