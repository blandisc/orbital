"""Lista de canales de TV en vivo: leer el M3U, traducir categorías y guardar una copia."""

from __future__ import annotations

from pathlib import Path

import pytest

from orbital.library import iptv

SAMPLE = Path(__file__).parent / "fixtures" / "iptv" / "mx-muestra.m3u"


@pytest.fixture
def text() -> str:
    # Las listas de verdad traen saltos de línea de Windows (CRLF).
    return SAMPLE.read_text(encoding="utf-8").replace("\n", "\r\n")


@pytest.fixture
def channels(text) -> dict[str, iptv.Channel]:
    return {c.id: c for c in iptv.parse_m3u(text)}


def test_lee_nombre_calidad_etiquetas_y_logo(channels):
    azteca = channels["Azteca7.mx@SD"]
    assert (azteca.name, azteca.quality, azteca.tags) == ("Azteca 7", "720p", [])
    assert azteca.logo == "https://logos.example.mx/azteca7.png"
    assert azteca.url == "https://tv.example.mx/azteca7/playlist.m3u8"
    noticias = channels["NoticiasMX.mx@SD"]
    assert (noticias.name, noticias.quality, noticias.tags) == ("Noticias MX", "1080p", ["Not 24/7"])
    peques = channels["Peques.mx@SD"]  # la calidad entre paréntesis sale aunque haya otros paréntesis
    assert (peques.name, peques.quality, peques.tags) == ("Peques TV (Mexico)", "480p", ["Geo-blocked"])


def test_categorias_separadas_por_punto_y_coma_en_espanol(channels):
    assert channels["NoticiasMX.mx@SD"].categories == ["Noticias", "General"]
    assert channels["Peques.mx@SD"].categories == ["Animación", "Infantil"]
    assert channels["Peques.mx@SD"].category == "Animación"


def test_undefined_pasa_a_otros(channels):
    assert channels["Cine.mx@SD"].categories == ["Otros"]


def test_translate_casos():
    assert iptv.translate(None) == ["Otros"]
    assert iptv.translate("") == ["Otros"]
    assert iptv.translate("Undefined;News") == ["Noticias"]  # ya se sabe qué es: «Otros» sobra
    assert iptv.translate("News;News; Sports ") == ["Noticias", "Deportes"]
    assert iptv.translate("Gaming") == ["Gaming"]  # una categoría nueva de iptv-org no se pierde


def test_la_coma_dentro_del_nombre_no_corta_el_canal(channels):
    assert channels["Cine.mx@SD"].name == "Cine de Barrio, el canal"
    assert channels["Cine.mx@SD"].logo is None  # logo vacío


def test_referer_y_user_agent_de_la_lista(channels):
    deportes = channels["ConReferer.mx@SD"]
    assert deportes.referrer == "https://sitio.example.mx/en,vivo"
    assert deportes.user_agent == "Mozilla/5.0 (OrbitalTest)"
    assert channels["Azteca7.mx@SD"].referrer is None


def test_cabeceras_raras_se_ignoran(channels):
    mala = channels["UAMala.mx@SD"]
    assert mala.referrer is None  # no es una dirección http
    assert mala.user_agent is None  # vacío


def test_solo_direcciones_http_y_nunca_adultos(channels):
    assert "ArchivoLocal.mx@SD" not in channels  # file:// no se abre jamás
    assert "Rtmp.mx@SD" not in channels
    assert "Adulto.mx@SD" not in channels


def test_mismo_id_dos_veces_se_distingue(channels):
    assert channels["Azteca7.mx@SD"].url.endswith("/azteca7/playlist.m3u8")
    assert channels["Azteca7.mx@SD~2"].name == "Azteca 7 (otra señal)"


def test_sin_id_se_inventa_uno_estable(channels):
    sin_id = next(c for c in channels.values() if c.name == "Sin id ni logo")
    assert sin_id.id == "sin-id-ni-logo"
    assert sin_id.categories == ["Música"]


def test_public_no_expone_direcciones_ni_cabeceras(channels):
    public = channels["ConReferer.mx@SD"].public()
    assert set(public) == {"id", "name", "logo", "categories", "quality"}
    assert "sitio.example.mx" not in str(public) and "tv.example.mx" not in str(public)


def test_orden_de_categorias():
    titles = ["Otros", "Zoología", "Deportes", "Noticias", "General", "Arte"]
    assert sorted(titles, key=iptv.category_sort_key) == ["General", "Noticias", "Deportes", "Arte", "Zoología", "Otros"]


def test_una_lista_sin_nada_no_truena():
    assert iptv.parse_m3u("") == []
    assert iptv.parse_m3u("#EXTM3U\n#EXTINF:-1\nhttps://x.example/a.m3u8\n") == []  # sin nombre
    assert iptv.parse_m3u("#EXTM3U\nhttps://x.example/sin-extinf.m3u8\n") == []
    assert iptv.parse_m3u("﻿#EXTM3U\n#EXTINF:-1,Con BOM\nhttps://x.example/a.m3u8\n")[0].name == "Con BOM"


# --- descarga y copia en disco ---------------------------------------------------------------
def test_descarga_guarda_copia_y_la_usa_sin_internet(tmp_path, text):
    copy = tmp_path / "cache" / "tv-mx.m3u"
    channels, fresh = iptv.fetch_list(copy, download_fn=lambda: text)
    assert fresh and len(channels) == 8 and copy.exists()

    def offline() -> str:
        raise OSError("Sin red")

    again, fresh = iptv.fetch_list(copy, download_fn=offline)
    assert not fresh and [c.id for c in again] == [c.id for c in channels]


def test_sin_internet_ni_copia_la_lista_queda_vacia(tmp_path):
    def offline() -> str:
        raise OSError("Sin red")

    assert iptv.fetch_list(tmp_path / "no-hay.m3u", download_fn=offline) == ([], False)
    assert iptv.fetch_list(None, download_fn=offline) == ([], False)


def test_una_pagina_de_inicia_sesion_no_pisa_la_copia(tmp_path, text):
    copy = tmp_path / "tv-mx.m3u"
    iptv.fetch_list(copy, download_fn=lambda: text)
    channels, fresh = iptv.fetch_list(copy, download_fn=lambda: "<html><body>Inicia sesión en el Wi-Fi</body></html>")
    assert not fresh and len(channels) == 8
    assert copy.read_text(encoding="utf-8").startswith("#EXTM3U")


def test_copia_dañada_no_truena(tmp_path):
    copy = tmp_path / "tv-mx.m3u"
    copy.write_bytes(b"\xff\xfe\x00 no es utf-8")
    assert iptv.read_copy(copy) == []
