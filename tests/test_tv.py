"""TV en vivo: categorías y números, revisar en segundo plano, saltar canales caídos y abrir uno en el reproductor."""

from __future__ import annotations

import io
import threading
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from orbital import player, tv
from orbital.config import parse_config
from orbital.library import iptv
from orbital.library.iptv_health import Unreachable
from orbital.server import create_app

SAMPLE = (Path(__file__).parent / "fixtures" / "iptv" / "mx-muestra.m3u").read_text(encoding="utf-8")
MEDIA = "#EXTM3U\n#EXTINF:6,\nseg1.ts\n"


class Net:
    """El «internet» de los canales: abren los de `up`; cualquier otro responde 404."""

    def __init__(self, up=None) -> None:
        self.up = set(up if up is not None else ())
        self.everything = up is None

    def __call__(self, url, headers, *, limit=0):
        if url.endswith(".ts"):
            return b"\x47" * 4096
        if self.everything or url in self.up:
            return MEDIA.encode()
        raise Unreachable("HTTP 404")


def make_tv(catalog=None, directory=None, *, up=None, text=SAMPLE, online=lambda: True, load=True) -> tv.LiveTV:
    live = tv.LiveTV(parse_config({}), catalog, directory=directory, download_fn=lambda: text, fetch_fn=Net(up), online=online)
    if load:
        live.set_channels(iptv.parse_m3u(text))
    return live


def ids(channels) -> list[str]:
    return [c.id for c in channels]


# --- categorías, números y qué se muestra ---------------------------------------------------------
def test_pestanas_de_categoria_con_todos_primero_y_las_chicas_en_otros():
    live = make_tv()
    overview = live.overview()
    titles = [c["title"] for c in overview["categories"]]
    # «General» tiene 3 canales; Noticias, Deportes, Música… tienen 1 y no son pestañas de un solo canal.
    assert titles == ["Todos", "General", "Otros"]
    assert overview["categories"][0]["count"] == 8
    azteca = next(c for c in overview["channels"] if c["id"] == "Azteca7.mx@SD")
    assert azteca["categories"] == ["General"]
    deportes = next(c for c in overview["channels"] if c["id"] == "ConReferer.mx@SD")
    assert deportes["categories"] == ["Otros"]


def test_los_que_ya_fallaron_van_al_final_y_el_logo_lo_sirve_orbital():
    live = make_tv()
    live.store.record("Azteca7.mx@SD", False, "HTTP 404")  # el primero del orden, ya falló una vez
    channels = live.overview()["channels"]
    assert channels[-1]["id"] == "Azteca7.mx@SD" and channels[-1]["verified"] is False
    numbers = [c["number"] for c in channels[:-1]]
    assert numbers == sorted(numbers)  # el resto sigue en el orden de su número
    azteca = channels[-1]
    assert azteca["logo"] == "/api/tv/logo?id=Azteca7.mx%40SD"  # la dirección de Orbital, no la de imgur
    assert "logos.example.mx" not in str(live.overview())
    assert next(c for c in channels if c["id"] == "Cine.mx@SD")["logo"] is None  # sin logo en la lista, sin dirección


def test_los_canales_traen_numero_y_nunca_su_direccion():
    live = make_tv()
    overview = live.overview()
    numbers = [c["number"] for c in overview["channels"]]
    assert numbers == sorted(numbers) and len(set(numbers)) == 8
    assert "tv.example.mx" not in str(overview) and "sitio.example.mx" not in str(overview)
    assert {"id", "name", "logo", "categories", "quality", "number", "verified"} <= set(overview["channels"][0])


def test_sin_verificar_se_muestra_y_dos_fallos_lo_ocultan():
    live = make_tv()
    assert live.overview()["channels"][0]["verified"] is None  # sin verificar: se muestra
    live.store.record("Azteca7.mx@SD", False, "HTTP 404")
    assert "Azteca7.mx@SD" in ids(live.visible())  # un fallo no lo oculta
    live.store.record("Azteca7.mx@SD", False, "HTTP 404")
    assert "Azteca7.mx@SD" not in ids(live.visible())
    overview = live.overview()
    assert overview["hidden"] == 1 and overview["total"] == 8 and overview["categories"][0]["count"] == 7


def test_los_numeros_no_se_mueven_cuando_otro_canal_se_oculta():
    live = make_tv()
    before = {c.id: live.store.number(c.id) for c in live.visible()}
    live.store.record("Cine.mx@SD", False)
    live.store.record("Cine.mx@SD", False)
    assert {c.id: live.store.number(c.id) for c in live.visible()} == {k: v for k, v in before.items() if k != "Cine.mx@SD"}


def test_zap_list_por_categoria_y_si_no_existe_son_todos():
    live = make_tv()
    cat, general = live.zap_list("general")
    assert cat == "general" and ids(general) == ["Azteca7.mx@SD", "Azteca7.mx@SD~2", "NoticiasMX.mx@SD"]  # en orden de número
    cat, everyone = live.zap_list("no-existe")
    assert cat == "todos" and len(everyone) == 8
    assert live.zap_list(None)[0] == "todos"


# --- revisar en segundo plano ---------------------------------------------------------------------
def test_refresh_baja_la_lista_revisa_los_canales_y_avisa(library):
    live = make_tv(library, load=False)
    events = []
    library.events.subscribe(events.append)
    assert live.refresh() is True
    assert len(live.visible()) == 8 and live.updated and not live.offline and not live.checking
    assert all(live.store.verified(c.id) for c in live.visible())
    assert {"type": "tv-changed"} in events


def test_refresh_sin_internet_usa_la_copia_y_no_cuenta_fallos(tmp_path):
    first = make_tv(directory=tmp_path, load=False)
    first.refresh()  # con Internet: guarda lista y salud
    assert len(first.visible()) == 8

    def offline() -> str:
        raise OSError("Sin red")

    live = tv.LiveTV(parse_config({}), None, directory=tmp_path, download_fn=offline, fetch_fn=Net(up=[]), online=lambda: False)
    assert len(live.visible()) == 8  # nada más arrancar, sin red: la copia en disco y lo que se sabía
    live.refresh()
    assert live.offline and len(live.visible()) == 8
    assert all(live.store.verified(c.id) for c in live.visible())  # los 404 de «sin Internet» no se anotaron


def test_refresh_dos_a_la_vez_revisa_una_sola_vez():
    live = make_tv(load=False)
    gate, started = threading.Event(), threading.Event()
    inner = live._fetch_fn

    def slow(*args, **kwargs):
        started.set()
        gate.wait(2)
        return inner(*args, **kwargs)

    live._fetch_fn = slow
    worker = threading.Thread(target=live.refresh)
    worker.start()
    assert started.wait(2) and live.checking
    assert live.refresh() is False  # ya se está revisando
    gate.set()
    worker.join(5)
    assert not live.checking


def test_start_revisa_solo_y_stop_lo_detiene(monkeypatch):
    monkeypatch.setattr(tv, "START_DELAY", 0)
    live = make_tv(load=False)
    live.start()
    for _ in range(100):
        if live.updated:
            break
        threading.Event().wait(0.05)
    live.stop()
    assert live.updated and len(live.visible()) == 8
    live._thread.join(2)
    assert not live._thread.is_alive()


def test_la_primera_vez_sin_copia_no_espera_a_la_revision_del_arranque(monkeypatch):
    live = make_tv(load=False)
    monkeypatch.setattr(tv, "START_DELAY", 3600)
    live.start()  # el arranque revisa en una hora…
    asked = []
    monkeypatch.setattr(live, "refresh", lambda background=False: asked.append(background))
    assert live.overview()["channels"] == []  # …pero la interfaz pide la lista vacía: se sale a buscarla ya
    live.overview()
    assert asked == [True]  # y no una vez por cada vistazo
    live.stop()


# --- abrir un canal en el reproductor ----------------------------------------------------------------
class FakePlayer:
    def __init__(self) -> None:
        self.played, self.tuned, self.toasts = [], [], []
        self.segment = None
        self.playing = False

    def play(self, run, mpv_exe, url, title, meta, **options):
        self.played.append((mpv_exe, url, title, meta, options))
        options_started = options.pop("started", None)
        if options_started:
            options_started(object())

    def tune(self, url, title, meta, **kwargs):
        self.tuned.append((url, title, meta, kwargs))
        return True

    def toast(self, text, seconds=1.6):
        self.toasts.append(text)


@pytest.fixture
def live(library, monkeypatch):
    fake = FakePlayer()
    library.player = fake
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    return make_tv(library), fake


def test_play_abre_mpv_en_vivo_con_las_cabeceras_del_canal(live, library):
    service, fake = live
    closed = []
    library.before_launch = closed.append
    result = service.play("ConReferer.mx@SD", "todos")
    assert result["ok"] is True and closed == ["media:player"]
    mpv_exe, url, title, meta, options = fake.played[0]
    assert (mpv_exe, url, title) == ("mpv.exe", "https://tv.example.mx/deportes/playlist.m3u8", "Deportes con Referer")
    assert options["live"] is True and options["referrer"] == "https://sitio.example.mx/en,vivo"
    assert options["user_agent"] == "Mozilla/5.0 (OrbitalTest)" and options["subtitles"] == ""
    assert meta["kind"] == "tv" and meta["live"] and meta["channel_id"] == "ConReferer.mx@SD" and meta["number"]
    assert library.launcher.current["id"] == "media:player" and library.launcher.current["title"] == "Deportes con Referer"
    # El reproductor queda conectado a la TV: la lista de ▲▼, qué hacer si un canal falla…
    assert library.watch.player.channels_provider == service.guide and library.watch.player.on_channel_failed == service.failed


def on_air(fake, channel_id="Azteca7.mx@SD"):
    """Un canal al aire en el reproductor (ya con imagen)."""
    fake.playing = True
    fake.segment = type("Segment", (), {"live": True, "meta": {"channel_id": channel_id, "list": "todos"}})()


def test_con_un_canal_al_aire_otro_se_sintoniza_en_el_mismo_mpv_sin_abrir_nada(live, library):
    service, fake = live
    on_air(fake)
    library.before_launch = lambda *a: pytest.fail("no se cierra nada: es el mismo reproductor")
    result = service.play("Cine.mx@SD", "todos")
    assert result == {"ok": True, "reveal": False, "tuned": True}
    assert fake.played == [] and fake.tuned[0][1] == "Cine de Barrio, el canal"


def test_pedir_el_canal_que_ya_esta_al_aire_no_lo_vuelve_a_sintonizar(live):
    service, fake = live
    on_air(fake, "Cine.mx@SD")
    assert service.play("Cine.mx@SD")["tuned"] is True
    assert fake.tuned == [] and fake.played == []


def test_el_canal_al_aire_se_dice_en_el_listado_y_en_el_estado(live, library):
    service, fake = live
    assert service.overview()["playing"] is None
    on_air(fake)
    assert service.overview()["playing"] == "Azteca7.mx@SD" and service.playing() == "Azteca7.mx@SD"
    library.launcher.current = {"id": "media:player", "title": "Azteca 7", "managed": True}
    from orbital.api.deps import Deps
    deps = Deps(config=library.config, catalog=library, shell=type("Shell", (), {"is_paused": False})(), voice=None, hub=None)
    assert deps.status()["running"]["live"] == "Azteca7.mx@SD"  # la interfaz marca la casilla y A vuelve a ella
    library.launcher.current = {"id": "app:otra", "title": "Otra", "managed": True}
    assert "live" not in deps.status()["running"]


def test_play_dice_por_que_no_se_puede(live, monkeypatch):
    service, _ = live
    with pytest.raises(LookupError, match="ya no está disponible"):
        service.play("no-existe")
    service.store.record("Cine.mx@SD", False)
    service.store.record("Cine.mx@SD", False)
    with pytest.raises(LookupError, match="ya no está disponible"):  # se ocultó mientras mirabas la pantalla
        service.play("Cine.mx@SD")
    monkeypatch.setattr(player, "find_mpv", lambda: None)
    with pytest.raises(LookupError, match="mpv"):
        service.play("Azteca7.mx@SD")


def test_play_con_mpv_que_no_abre_deja_orbital_como_estaba(live, library, monkeypatch):
    service, fake = live
    unpinned = []
    monkeypatch.setattr(type(library.sessions), "pin", staticmethod(lambda: 99))
    monkeypatch.setattr(type(library.sessions), "unpin", staticmethod(unpinned.append))

    def broken(*args, **kwargs):
        raise OSError("no abre")

    fake.play = broken
    with pytest.raises(OSError):
        service.play("Azteca7.mx@SD")
    assert unpinned == [99]  # Orbital no se queda «siempre encima»


def test_la_guia_lista_categorias_y_canales_con_el_actual_marcado(live):
    service, _ = live
    azteca = service.channel("Azteca7.mx@SD")
    meta = service.meta_for(azteca, "general")
    guide = service.guide(meta)
    assert guide["category"] == "general" and [c["id"] for c in guide["categories"]] == ["todos", "general", "otros"]
    assert [c["label"] for c in guide["categories"] if c["current"]] == ["General"]
    assert [c["name"] for c in guide["channels"] if c["current"]] == ["Azteca 7"]
    assert len(guide["channels"]) == 3 and all(c["category"] == "General" for c in guide["channels"])
    assert len(service.guide(meta, "todos")["channels"]) == 8  # otra categoría de la guía, sin cambiar la lista del canal


def test_la_barra_dice_la_categoria_de_la_lista_de_la_que_vienes(live):
    service, _ = live
    noticias = service.channel("NoticiasMX.mx@SD")
    assert service.meta_for(noticias, "general")["category"] == "General"
    assert service.meta_for(noticias, "todos")["category"] == "General"  # Noticias es una pestaña de un solo canal


def test_sintonizar_pone_el_canal_en_la_barra_de_arriba(live, library):
    service, fake = live
    running = type("Running", (), {"item_id": "media:player", "title": "Azteca 7"})()
    library.launcher.current = running
    meta = service.meta_for(service.channel("Azteca7.mx@SD"), "todos")
    assert service.tune(meta, "Cine.mx@SD") is True
    assert fake.tuned[0][1] == "Cine de Barrio, el canal" and running.title == "Cine de Barrio, el canal"
    assert fake.tuned[0][2]["list"] == "todos"  # sigue en la misma lista
    assert service.tune(meta, "no-existe") is False


# --- canales que fallan ----------------------------------------------------------------------------
def meta_of(service, channel_id, category="todos", **extra):
    return {**service.meta_for(service.channel(channel_id), category), **extra}


def test_un_canal_que_no_abre_se_marca_y_se_pasa_al_siguiente_de_la_lista(live):
    service, fake = live
    first = service.visible()[0]
    meta = meta_of(service, first.id)
    assert service.failed(meta, False) is True
    assert service.store.verified(first.id) is False and not service.store.hidden(first.id)  # un fallo no lo oculta
    url, title, new_meta, _ = fake.tuned[0]
    assert title == service.visible()[1].name and new_meta["tried"] == sorted([first.id, service.visible()[1].id])
    assert "no abre · pasando a" in fake.toasts[0]


def test_el_siguiente_se_busca_antes_de_ocultar_el_canal_que_falla(live):
    """Con el segundo fallo el canal se oculta y sale de su lista: el siguiente sigue siendo el de al lado (antes volvía al principio)."""
    service, fake = live
    visible = service.visible()
    failing = visible[5]
    service.store.record(failing.id, False)  # ya había fallado una vez: este es el segundo
    assert service.failed(meta_of(service, failing.id), False) is True
    assert service.store.hidden(failing.id)
    assert fake.tuned[0][1] == visible[6].name


def test_al_saltar_prefiere_un_canal_que_no_haya_fallado(live):
    service, fake = live
    visible = service.visible()
    service.store.record(visible[3].id, False)  # el que sigue ya falló una vez
    service.failed(meta_of(service, visible[2].id), False)
    assert fake.tuned[0][1] == visible[4].name  # se salta el dudoso


def test_la_guia_marca_los_canales_dudosos(live):
    service, _ = live
    first = service.visible()[0]
    service.store.record(first.id, False)
    shaky = {c["id"]: c["shaky"] for c in service.guide(service.meta_for(service.visible()[1], "todos"))["channels"]}
    assert shaky[first.id] is True and not any(v for k, v in shaky.items() if k != first.id)


def test_dos_fallos_seguidos_lo_ocultan(live):
    service, _ = live
    first = service.visible()[0]
    service.failed(meta_of(service, first.id), False)
    service.failed(meta_of(service, first.id), False)
    assert first.id not in ids(service.visible())


def test_el_siguiente_da_la_vuelta_a_la_lista(live):
    service, fake = live
    last = service.visible()[-1]
    service.failed(meta_of(service, last.id), False)
    assert fake.tuned[0][1] == service.visible()[0].name


def test_no_salta_mas_de_tres_canales_seguidos(live):
    service, fake = live
    meta = meta_of(service, service.visible()[0].id)
    results = []
    for _ in range(5):
        results.append(service.failed(meta, False))
        meta = fake.tuned[-1][2] if results[-1] else meta
    assert results == [True, True, True, False, False]
    assert len(fake.tuned) == 3  # se queda en «Sin señal» para que decidas tú


def test_sin_internet_no_marca_ni_salta(live):
    service, fake = live
    service._online = lambda: False
    first = service.visible()[0]
    assert service.failed(meta_of(service, first.id), False) is False
    assert service.store.verified(first.id) is None and fake.tuned == []


def test_si_se_corta_a_media_vista_primero_reintenta_el_mismo_una_vez(live):
    service, fake = live
    first = service.visible()[0]
    meta = meta_of(service, first.id)
    assert service.failed(meta, True) is True
    url, title, retry_meta, _ = fake.tuned[0]
    assert title == first.name and retry_meta["retried"] is True  # el mismo canal
    assert service.store.verified(first.id) is None  # todavía no cuenta como fallo
    assert service.failed(retry_meta, True) is True  # se volvió a cortar: ahora sí se marca y se salta
    assert service.store.verified(first.id) is False and fake.tuned[1][1] == service.visible()[1].name


def test_un_canal_que_da_imagen_borra_sus_fallos(live):
    service, _ = live
    first = service.visible()[0]
    service.store.record(first.id, False)
    meta = meta_of(service, first.id, retried=True)
    service.opened(meta)
    assert service.store.verified(first.id) is True and "retried" not in meta
    service.store.record(first.id, False)
    assert not service.store.hidden(first.id)  # la racha empezó de cero


# --- la API ---------------------------------------------------------------------------------------
@pytest.fixture
def client(library, monkeypatch):
    service = make_tv(library)
    library.tv = service
    library.player = FakePlayer()
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("127.0.0.1", 5000)) as c:
        yield c, service


def test_api_lista_los_canales(client):
    c, _ = client
    data = c.get("/api/tv").json()
    assert [x["title"] for x in data["categories"]] == ["Todos", "Orbital 24/7", "General", "Otros"]
    assert data["channels"][0]["synthetic"] is True and data["channels"][0]["name"] == "Los Simpson 24/7"  # los de Orbital, primero
    assert len(data["channels"]) == 9 and data["checking"] is False and data["offline"] is False
    assert "tv.example.mx" not in c.get("/api/tv").text


def test_api_play_abre_el_canal_y_dice_si_hay_pantalla_de_carga(client):
    c, service = client
    res = c.post("/api/tv/play", json={"id": "Azteca7.mx@SD", "category": "general"})
    assert res.status_code == 200 and res.json()["ok"] is True and "reveal" in res.json()
    assert c.get("/api/status").json()["running"]["title"] == "Azteca 7"


def test_api_play_errores_en_palabras_de_persona(client, monkeypatch):
    c, _ = client
    res = c.post("/api/tv/play", json={"id": "no-existe"})
    assert res.status_code == 404 and "ya no está disponible" in res.json()["detail"]
    assert c.post("/api/tv/play", json={}).status_code == 422
    assert c.post("/api/tv/play", json={"id": "x" * 500}).status_code == 422
    monkeypatch.setattr(player, "find_mpv", lambda: None)
    assert "mpv" in c.post("/api/tv/play", json={"id": "Azteca7.mx@SD"}).json()["detail"]


def test_api_play_si_mpv_no_abre_es_un_error_claro(client, library):
    c, _ = client

    def broken(*args, **kwargs):
        raise PermissionError(13, "Acceso denegado")

    library.player.play = broken
    res = c.post("/api/tv/play", json={"id": "Azteca7.mx@SD"})
    assert res.status_code == 500 and "No pude abrir el reproductor" in res.json()["detail"]


def test_api_logo_se_sirve_desde_orbital_y_da_404_si_no_hay(client, tmp_path):
    from PIL import Image

    c, service = client
    service.logos.directory = tmp_path
    out = io.BytesIO()
    Image.new("RGBA", (300, 120), (255, 255, 255, 255)).save(out, "PNG")
    assert service.logos.put("https://logos.example.mx/azteca7.png", out.getvalue()) is not None
    res = c.get("/api/tv/logo", params={"id": "Azteca7.mx@SD"})
    assert res.status_code == 200 and res.headers["content-type"] == "image/png" and "max-age" in res.headers["cache-control"]
    assert res.content[1:4] == b"PNG"
    assert c.get("/api/tv/logo", params={"id": "Cine.mx@SD"}).status_code == 404  # sin logo en la lista
    assert c.get("/api/tv/logo", params={"id": "no-existe"}).status_code == 404
    assert c.get("/api/tv/logo").status_code == 422 and c.get("/api/tv/logo", params={"id": "x" * 500}).status_code == 422


def test_api_play_con_un_canal_al_aire_trae_su_ventana_al_frente(client, library, monkeypatch):
    c, service = client
    on_air(library.player)
    resumed = []
    monkeypatch.setattr(c.app.state.shell, "resume", lambda: resumed.append(True) or True)
    res = c.post("/api/tv/play", json={"id": "Cine.mx@SD"})
    assert res.json()["tuned"] is True and resumed == [True]
    on_air(library.player, "Cine.mx@SD")


def test_api_refresh_arranca_la_revision_en_segundo_plano(client, monkeypatch):
    c, service = client
    asked = []
    monkeypatch.setattr(service, "refresh", lambda background=False: asked.append(background) or True)
    assert c.post("/api/tv/refresh").json() == {"ok": True, "started": True} and asked == [True]


def test_api_no_se_abre_desde_fuera_sin_token(library):
    with TestClient(create_app(library.config, library), base_url="http://127.0.0.1:8710", client=("203.0.113.9", 5000)) as c:
        assert c.get("/api/tv").status_code == 401
        assert c.post("/api/tv/play", json={"id": "x"}).status_code == 401


def test_un_canal_que_ocupa_demasiada_memoria_se_abre_en_un_mpv_nuevo(live, library):
    """El vigilante de memoria: el mismo canal, sin sintonizar en el mpv inflado (fresh: uno nuevo)."""
    service, fake = live
    on_air(fake)
    library.before_launch = None
    service.reopen({"channel_id": "Cine.mx@SD", "title": "Cine", "list": "todos"})
    assert fake.tuned == [] and len(fake.played) == 1


def test_tus_canales_son_los_ultimos_que_diste_imagen_y_se_guardan(tmp_path):
    live = make_tv(directory=tmp_path)
    live.opened({"channel_id": "Cine.mx@SD"})
    live.opened({"channel_id": "Azteca7.mx@SD"})
    live.opened({"channel_id": "Cine.mx@SD"})  # otra vez: sube, no se repite
    assert live.overview()["recent"] == ["Cine.mx@SD", "Azteca7.mx@SD"]
    again = make_tv(directory=tmp_path)  # se recuerdan al reabrir Orbital
    assert again.overview()["recent"] == ["Cine.mx@SD", "Azteca7.mx@SD"]
