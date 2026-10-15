"""Salud de los canales: manifiesto -> variante -> segmento, 2 fallos seguidos para ocultar, y copia en disco."""

from __future__ import annotations

import io
import urllib.error

import pytest

from orbital.library import iptv, iptv_health
from orbital.library.iptv_health import HealthStore, Unreachable, check_all, check_channel

MASTER = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nhd/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=300000\nsd/index.m3u8\n"
MEDIA = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg1.ts\n#EXTINF:6,\nseg2.ts\n#EXTINF:6,\nseg3.ts\n#EXTINF:6,\nseg4.ts\n"
VIDEO = b"\x47" * 4096
REAL_FETCH = iptv_health.fetch  # conftest cambia iptv_health.fetch por uno que no sale a Internet; aquí se prueba el de verdad


def channel(url="https://tv.example.mx/a/playlist.m3u8", **extra) -> iptv.Channel:
    return iptv.Channel(id=extra.pop("id", "a"), name="A", url=url, **extra)


class Server:
    """Un «internet» de mentiras: url -> bytes (o la excepción que lanza). Anota qué se pidió."""

    def __init__(self, pages: dict) -> None:
        self.pages, self.asked = pages, []

    def __call__(self, url, headers, *, limit=0):
        self.asked.append((url, headers))
        page = self.pages.get(url)
        if page is None:
            raise Unreachable("HTTP 404")
        if isinstance(page, Exception):
            raise page
        return page.encode() if isinstance(page, str) else page


def test_canal_con_calidades_abre_si_responde_hasta_el_segmento():
    server = Server({"https://tv.example.mx/a/playlist.m3u8": MASTER,
                     "https://tv.example.mx/a/hd/index.m3u8": MEDIA,
                     "https://tv.example.mx/a/hd/seg2.ts": VIDEO})
    result = check_channel(channel(), server)
    assert result.ok and result.stage == "segment"
    # Como un reproductor: empieza 3 segmentos antes del final, no en el último (que puede no estar listo).
    assert server.asked[-1][0] == "https://tv.example.mx/a/hd/seg2.ts"


def test_lista_sin_calidades_va_directo_al_segmento():
    server = Server({"https://tv.example.mx/a/playlist.m3u8": MEDIA, "https://tv.example.mx/a/seg2.ts": VIDEO})
    assert check_channel(channel(), server).ok


@pytest.mark.parametrize("pages, stage, reason", [
    ({}, "manifest", "HTTP 404"),
    ({"https://tv.example.mx/a/playlist.m3u8": MASTER}, "variant", "HTTP 404"),
    ({"https://tv.example.mx/a/playlist.m3u8": MASTER, "https://tv.example.mx/a/hd/index.m3u8": "<html>Error</html>"},
     "variant", "la calidad no es una lista de video"),
    ({"https://tv.example.mx/a/playlist.m3u8": "#EXTM3U\n#EXT-X-TARGETDURATION:6\n"}, "segment", "sin segmentos"),
    ({"https://tv.example.mx/a/playlist.m3u8": MEDIA}, "segment", "HTTP 404"),  # el manifiesto contesta y el video no
    ({"https://tv.example.mx/a/playlist.m3u8": MEDIA, "https://tv.example.mx/a/seg2.ts": b"<html>"},
     "segment", "segmento vacío"),
])
def test_cada_paso_que_falla_dice_donde(pages, stage, reason):
    result = check_channel(channel(), Server(pages))
    assert (result.ok, result.stage, result.reason) == (False, stage, reason)


def test_flujo_directo_si_es_video_y_no_una_pagina():
    ts = Server({"https://tv.example.mx/a/playlist.m3u8": VIDEO})
    assert check_channel(channel(), ts).ok
    web = Server({"https://tv.example.mx/a/playlist.m3u8": "<!doctype html><title>Acceso denegado</title>"})
    assert check_channel(channel(), web).reason == "es una página web, no un video"
    assert check_channel(channel(), Server({"https://tv.example.mx/a/playlist.m3u8": b""})).reason == "respuesta vacía"
    dash = Server({"https://tv.example.mx/a/playlist.m3u8": '<?xml version="1.0"?><MPD type="dynamic"></MPD>'})
    assert check_channel(channel(), dash).ok


def test_manda_el_referer_y_el_user_agent_del_canal():
    server = Server({"https://tv.example.mx/a/playlist.m3u8": MEDIA, "https://tv.example.mx/a/seg2.ts": VIDEO})
    check_channel(channel(referrer="https://sitio.example.mx/", user_agent="OrbitalTest/1"), server)
    for _, headers in server.asked:  # en los tres pedidos, igual que mpv
        assert headers["Referer"] == "https://sitio.example.mx/" and headers["User-Agent"] == "OrbitalTest/1"
    plain = Server({"https://tv.example.mx/a/playlist.m3u8": MEDIA, "https://tv.example.mx/a/seg2.ts": VIDEO})
    check_channel(channel(), plain)
    assert plain.asked[0][1]["User-Agent"] == iptv_health.DEFAULT_USER_AGENT and "Referer" not in plain.asked[0][1]


# --- la regla de los dos fallos --------------------------------------------------------------
def test_un_canal_se_oculta_solo_tras_dos_fallos_seguidos():
    store = HealthStore()
    assert store.verified("a") is None and not store.hidden("a")  # sin verificar: se muestra
    store.record("a", False, "HTTP 404")
    assert store.verified("a") is False and not store.hidden("a")  # un fallo no lo oculta
    store.record("a", False, "HTTP 404")
    assert store.hidden("a")
    store.record("a", True)  # volvió: otra vez a la vista, sin deuda
    assert not store.hidden("a") and store.verified("a") is True
    store.record("a", False, "x")
    assert not store.hidden("a")  # los fallos no se acumulan entre rachas


def test_guarda_y_recupera_de_disco(tmp_path):
    path = tmp_path / "cache" / "tv-health.json"
    store = HealthStore(path)
    store.record("a", False, "HTTP 403")
    store.record("a", False, "HTTP 403")
    store.record("b", True)
    store.assign_numbers([channel(id="a"), channel(id="b")])
    store.save()
    again = HealthStore(path)
    assert again.hidden("a") and again.verified("b") is True and again.verified("c") is None
    assert (again.number("a"), again.number("b")) == (1, 2)
    assert again.record_of("a")["reason"] == "HTTP 403"


def test_archivo_roto_o_con_basura_no_truena(tmp_path):
    path = tmp_path / "tv-health.json"
    path.write_text("{no es json", encoding="utf-8")
    assert HealthStore(path).verified("a") is None
    path.write_text('{"channels": {"a": {"fails": "muchos"}, "b": 5, "c": {"fails": 1, "ok": false}}, "numbers": {"a": "x", "b": -3, "c": 7}}',
                    encoding="utf-8")
    store = HealthStore(path)
    assert store.verified("a") is None and store.verified("b") is None and store.verified("c") is False
    assert store.number("a") is None and store.number("b") is None and store.number("c") == 7


def test_los_numeros_no_se_mueven_cuando_otro_canal_desaparece():
    store = HealthStore()
    store.assign_numbers([channel(id="a"), channel(id="b"), channel(id="c")])
    store.forget_missing({"a", "c"})  # b ya no está en la lista
    store.assign_numbers([channel(id="a"), channel(id="c"), channel(id="d")])
    assert (store.number("a"), store.number("c"), store.number("d")) == (1, 3, 4)
    store.assign_numbers([channel(id="b")])  # si b vuelve, no se le da el de otro
    assert store.number("b") == 2


# --- revisar toda la lista -------------------------------------------------------------------
def pages_for(ok_ids):
    pages = {}
    for cid in ok_ids:
        pages[f"https://tv.example.mx/{cid}/playlist.m3u8"] = MEDIA
        pages[f"https://tv.example.mx/{cid}/seg2.ts"] = VIDEO
    return pages


def test_revisar_todo_anota_cada_canal_y_olvida_los_que_ya_no_estan():
    channels = [channel(f"https://tv.example.mx/{i}/playlist.m3u8", id=i) for i in "abc"]
    store = HealthStore()
    store.record("viejo", False, "x")
    summary = check_all(channels, store, fetch_fn=Server(pages_for("ab")))
    assert summary == {"ok": 2, "failed": 1, "discarded": False}
    assert store.verified("a") and store.verified("b") and store.verified("c") is False
    assert store.verified("viejo") is None


def test_sin_internet_ningun_fallo_cuenta():
    channels = [channel(f"https://tv.example.mx/{i}/playlist.m3u8", id=i) for i in "ab"]
    store = HealthStore()
    store.record("a", True)
    summary = check_all(channels, store, fetch_fn=Server({}), online=lambda: False)
    assert summary["discarded"] and store.verified("a") is True and store.verified("b") is None


def test_dos_revisiones_malas_ocultan_y_una_buena_lo_devuelve():
    channels = [channel(id="a")]
    store = HealthStore()
    for _ in range(2):
        check_all(channels, store, fetch_fn=Server({}))
    assert store.hidden("a")
    check_all(channels, store, fetch_fn=Server(pages_for("a")))
    assert not store.hidden("a")


# --- la descarga de verdad (sin red: urlopen de mentiras) --------------------------------------
def test_fetch_traduce_los_errores_de_red(monkeypatch):
    def fail_with(exc):
        def urlopen(*args, **kwargs):
            raise exc
        return urlopen

    monkeypatch.setattr(iptv_health.urllib.request, "urlopen", fail_with(
        urllib.error.HTTPError("https://x", 403, "Forbidden", {}, io.BytesIO(b""))))
    with pytest.raises(Unreachable, match="HTTP 403"):
        REAL_FETCH("https://x", {})
    monkeypatch.setattr(iptv_health.urllib.request, "urlopen", fail_with(TimeoutError()))
    with pytest.raises(Unreachable, match="no responde"):
        REAL_FETCH("https://x", {})
    monkeypatch.setattr(iptv_health.urllib.request, "urlopen", fail_with(urllib.error.URLError("dns")))
    with pytest.raises(Unreachable, match="sin conexión"):
        REAL_FETCH("https://x", {})


def test_fetch_corta_en_el_limite_sin_fallar(monkeypatch):
    class Response:
        def __init__(self) -> None:
            self.left = 10

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self, n):
            self.left -= 1
            return b"x" * 40_000 if self.left else b""  # un video que no se acaba

        read1 = read

    monkeypatch.setattr(iptv_health.urllib.request, "urlopen", lambda *a, **k: Response())
    assert len(REAL_FETCH("https://x", {}, limit=64 * 1024)) == 64 * 1024
