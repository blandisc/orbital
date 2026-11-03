"""Tus complementos en la TV, sin tu cuenta de Stremio («La TV sin Stremio», S1; design/addons-contract.json)."""

from orbital.library import addon_list, addons
from orbital.library.addon_list import AddonList

TORRENTIO = "https://torrentio.strem.fun/sort=seeders|language=latino|realdebrid=KEY/manifest.json"
TPB = "https://thepiratebay-plus.strem.fun/manifest.json"
LOCAL = "http://127.0.0.1:1222/manifest.json"
CINEMETA = "https://v3-cinemeta.strem.io/manifest.json"


class Store(dict):
    def set(self, key, value):
        self[key] = value


def brought():
    return [("Torrentio RD", TORRENTIO, {"id": "com.stremio.torrentio.addon"}),
            ("ThePirateBay+", TPB, {"id": "com.tpb"}),
            ("Local Files", LOCAL, {"id": "org.stremio.local.files"}),
            ("Cinemeta", CINEMETA, {"id": "com.linvo.cinemeta"}),
            ("OpenSubtitles v3", addon_list.OPENSUBTITLES, {"id": "org.stremio.opensubtitlesv3"})]


def test_traer_de_stremio_una_vez_y_desde_ahi_es_tuya():
    lst = AddonList(Store())
    assert lst.source == "stremio" and lst.urls() == [addon_list.OPENSUBTITLES]  # lo de Orbital ya está
    done = lst.import_from_stremio(brought())
    # Cinemeta no (Orbital ya la usa: apagarla rompería las fichas) y OpenSubtitles ya viene con Orbital.
    assert done == {"added": 3, "kept": 0, "skipped": 2}
    assert lst.source == "own" and lst.revision == 1 and lst.imported_at
    names = [(e.name, e.origin) for e in lst.entries()]
    assert names == [("OpenSubtitles", "orbital"), ("Torrentio RD", "stremio"), ("ThePirateBay+", "stremio"), ("Local Files", "stremio")]
    local = next(e for e in lst.entries() if e.url == LOCAL)
    assert local.only_on == "tv" and local.on("tv") and not local.on("iphone")  # Archivos de la TV: solo en la TV


def test_volver_a_traer_conserva_lo_tuyo():
    lst = AddonList(Store())
    lst.import_from_stremio(brought())
    tpb = next(e for e in lst.entries() if e.url == TPB)
    lst.set_enabled(tpb.id, False)
    lst.move(tpb.id, -1)
    done = lst.import_from_stremio(brought())
    assert done["added"] == 0 and done["kept"] == 3
    again = next(e for e in lst.entries() if e.url == TPB)
    assert again.id == tpb.id and not again.on() and TPB not in lst.urls()


def test_quitar_deshacer_y_lo_de_orbital_solo_se_apaga():
    lst = AddonList(Store())
    lst.import_from_stremio(brought())
    tpb = next(e for e in lst.entries() if e.url == TPB)
    gone = lst.remove(tpb.id)
    assert TPB not in lst.urls()
    lst.restore(addon_list.asdict(gone))
    assert TPB in lst.urls()
    try:
        lst.remove("opensubtitles")
        raise AssertionError("lo de Orbital no se quita")
    except ValueError as exc:
        assert "se apaga" in str(exc)
    lst.set_enabled("opensubtitles", False)
    assert addon_list.OPENSUBTITLES not in lst.urls()


def test_volver_a_los_de_stremio_deja_tu_lista():
    lst = AddonList(Store())
    lst.import_from_stremio(brought())
    lst.set_source("stremio")
    assert lst.source == "stremio" and len(lst.entries()) == 4
    lst.set_source("own")
    assert lst.source == "own"


def test_con_tu_lista_ya_no_se_le_pregunta_a_tu_cuenta(monkeypatch):
    class Account:
        asked = 0

        def request(self, method, params):
            Account.asked += 1
            return {"addons": []}

    manifests = {TORRENTIO: {"name": "Torrentio", "resources": ["stream"], "types": ["movie"]},
                 addon_list.OPENSUBTITLES: {"name": "OpenSubtitles", "resources": ["subtitles"], "types": ["movie"]}}
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: manifests[url])
    lst = AddonList(Store())
    lst.import_from_stremio([("Torrentio", TORRENTIO, None)])
    registry = addons.AddonRegistry(Account(), auth=lambda: "key", listing=lst)
    assert [a.name for a in registry.addons()] == ["OpenSubtitles", "Torrentio"] and Account.asked == 0
    lst.set_source("stremio")
    registry.forget()
    registry.addons()
    assert Account.asked == 1  # «Volver a los de Stremio»: como antes


def test_un_complemento_que_falla_dos_veces_se_salta_y_se_reintenta_cada_vez_mas_tarde():
    now = [1000.0]
    health = addons.Health(clock=lambda: now[0])
    health.ok("a", 0.6)
    assert health.status("a") == {"state": "ok", "seconds": 0.6}
    health.ok("b", 4.2)
    assert health.status("b")["state"] == "slow"
    health.fail("c")
    assert not health.skip("c") and health.status("c")["state"] == "down"  # uno solo no basta
    health.fail("c")
    assert health.skip("c") and health.status("c") == {"state": "down", "since": 1000.0, "skipped": True}
    now[0] += 61
    assert not health.skip("c")  # a los 60 s se vuelve a probar
    health.fail("c")
    now[0] += 61
    assert health.skip("c")  # ahora espera 120 s
    for _ in range(10):
        health.fail("c")
    now[0] += 3601
    assert not health.skip("c")  # nunca más de una hora
    health.ok("c", 0.3)
    assert health.status("c")["state"] == "ok"  # contestó: vuelve solo


def test_un_manifiesto_que_ya_contesto_sirve_si_el_complemento_no_responde(monkeypatch, tmp_path):
    good = {"name": "Torrentio", "resources": ["stream"], "types": ["movie"]}
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: good)
    saved = tmp_path / "manifiestos.json"
    registry = addons.AddonRegistry(own=lambda: [TORRENTIO], manifests=saved)
    assert [a.name for a in registry.addons()] == ["Torrentio"]
    assert "KEY" not in saved.read_text(encoding="utf-8")  # la dirección lleva tu clave: no se escribe tal cual

    def down(url, timeout=0):
        raise OSError("sin red")

    monkeypatch.setattr(addons, "fetch_json", down)
    again = addons.AddonRegistry(own=lambda: [TORRENTIO], manifests=saved)
    assert [a.name for a in again.addons()] == ["Torrentio"]
    assert again.health.status(TORRENTIO)["state"] == "down"


def test_ajustes_complementos_de_punta_a_punta(tmp_path, monkeypatch):
    """Traer de tu Stremio, lo que enseña Ajustes, prender y apagar, quitar y deshacer, y volver a los de Stremio."""
    from orbital.catalog import Catalog
    from orbital.config import parse_config
    from orbital.credentials import Credentials
    from tests.conftest import FakeLauncher

    class Account:
        def library(self, auth_key):
            return []

        def request(self, method, params):
            assert method == "addonCollectionGet" and params["authKey"] == "clave"
            return {"addons": [{"transportUrl": TORRENTIO, "manifest": {"id": "t", "name": "Torrentio RD"}},
                               {"transportUrl": CINEMETA, "manifest": {"id": "com.linvo.cinemeta", "name": "Cinemeta"}},
                               {"transportUrl": LOCAL, "manifest": {"id": "local", "name": "Local Files"}}]}

    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: {"name": "x", "resources": ["stream"], "types": ["movie"]})
    cfg = parse_config({"steam": {"enabled": False}, "esde": {"enabled": False}, "detect": {"enabled": False},
                        "stremio": {"executable": "stremio-test"}})
    watch = Catalog(cfg, FakeLauncher(), credentials=Credentials(tmp_path / "secrets.json"), stremio_client=Account()).watch
    watch.credentials.set("stremio_auth_key", "clave")
    assert watch.addon_status()["source"] == "stremio"
    assert watch.import_addons() == {"added": 2, "kept": 0, "skipped": 1}
    status = watch.addon_status()
    assert status["source"] == "own" and [e["name"] for e in status["entries"]] == ["OpenSubtitles", "Torrentio RD", "Local Files"]
    torrentio = status["entries"][1]["id"]
    assert not watch.change_addon(torrentio, "off")["entries"][1]["on"]
    gone = watch.change_addon(torrentio, "remove")["removed"]
    assert gone["url"] == TORRENTIO and len(watch.addon_status()["entries"]) == 2
    assert [e["name"] for e in watch.restore_addon(torrentio)["entries"]] == ["OpenSubtitles", "Torrentio RD", "Local Files"]
    assert watch.set_addon_source("stremio")["source"] == "stremio"
