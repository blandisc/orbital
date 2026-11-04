"""Tus complementos en la TV, sin tu cuenta de Stremio («La TV sin Stremio», S1; design/addons-contract.json)."""

import pytest

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


def keyed():
    """Una lista con el llavero de la consola: la clave de Real-Debrid que traía tu Torrentio se queda ahí."""
    keys = {}
    return AddonList(Store(), key=lambda: keys.get("rd"), on_key=lambda k: keys.__setitem__("rd", k)), keys


def test_traer_de_stremio_una_vez_y_desde_ahi_es_tuya():
    lst, keys = keyed()
    assert lst.source == "stremio" and lst.urls() == [addon_list.OPENSUBTITLES]  # sin clave, Torrentio no se arma
    done = lst.import_from_stremio(brought())
    # Cinemeta no (Orbital ya la usa: apagarla rompería las fichas), OpenSubtitles ya viene con Orbital y tu Torrentio
    # pasa al de Orbital (corte S3), con sus opciones y su clave.
    assert done == {"added": 2, "kept": 1, "skipped": 2}
    assert lst.source == "own" and lst.revision == 1 and lst.imported_at and keys["rd"] == "KEY"
    names = [(e.name, e.origin) for e in lst.entries()]
    assert names == [("Torrentio", "orbital"), ("Comet", "orbital"), ("OpenSubtitles", "orbital"), ("ThePirateBay+", "stremio"),
                     ("Local Files", "stremio")]
    assert "comet.elfhosted.com" not in str(lst.urls())  # Comet viene apagado, como en el iPhone
    assert lst.urls()[0] == TORRENTIO  # la misma dirección: tus versiones no cambian
    assert "KEY" not in str(lst.store[addon_list.LIST_KEY]["entries"])  # la dirección con tu clave no se guarda
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
    assert lst.source == "stremio" and len(lst.entries()) == 5
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
    lst, _ = keyed()
    lst.import_from_stremio([("Torrentio", TORRENTIO, None)])
    registry = addons.AddonRegistry(Account(), auth=lambda: "key", listing=lst)
    assert [a.name for a in registry.addons()] == ["Torrentio", "OpenSubtitles"] and Account.asked == 0
    lst.set_source("stremio")
    registry.forget()
    registry.addons()
    assert Account.asked == 1  # «Volver a los de Stremio»: como antes


def test_el_torrentio_que_ya_habias_traido_pasa_al_de_orbital_y_sus_opciones_se_cambian_aqui():
    keys = {"rd": "KEY"}
    store = Store()
    store.set(addon_list.LIST_KEY, {"source": "own", "entries": [
        {"id": "opensubtitles", "origin": "orbital", "name": "OpenSubtitles", "order": 0, "template": "opensubtitles"},
        {"id": "u1", "origin": "stremio", "name": "Torrentio RD", "order": 1, "url": TORRENTIO, "enabled": {"tv": True}},
        {"id": "u2", "origin": "stremio", "name": "ThePirateBay+", "order": 2, "url": TPB, "enabled": {"tv": True}}]})
    lst = AddonList(store, key=lambda: keys.get("rd"))
    assert lst.adopt_torrentio() and not lst.adopt_torrentio()  # una sola vez
    assert [e.name for e in lst.entries()] == ["OpenSubtitles", "Torrentio", "ThePirateBay+", "Comet"]  # en su lugar
    assert lst.urls() == [addon_list.OPENSUBTITLES, TORRENTIO, TPB]
    mine = lst.set_options({**lst.torrentio().options, "qualityfilter": ["cam"], "limit": 5, "nada": 1})
    assert mine.address == "https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=cam|limit=5|realdebrid=KEY/manifest.json"
    assert "nada" not in mine.options
    lst.import_from_stremio([("Torrentio RD", TORRENTIO, None)])  # «Volver a traer» no pisa lo que cambiaste aquí
    assert lst.torrentio().options["limit"] == 5


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
    assert watch.import_addons() == {"added": 1, "kept": 1, "skipped": 1}
    status = watch.addon_status()
    # Tu Torrentio pasó al de Orbital, con sus opciones y tu clave (corte S3).
    assert status["source"] == "own" and [e["name"] for e in status["entries"]] == ["Torrentio", "Comet", "OpenSubtitles", "Local Files"]
    assert watch.credentials.get("realdebrid_token") == "KEY" and status["entries"][0]["options"]["sort"] == "seeders"
    assert not status["entries"][0]["needs_key"] and watch.addon_list.urls()[0] == TORRENTIO
    local = status["entries"][3]["id"]
    assert not watch.change_addon(local, "off")["entries"][3]["on"]
    gone = watch.change_addon(local, "remove")["removed"]
    assert gone["url"] == LOCAL and len(watch.addon_status()["entries"]) == 3
    assert [e["name"] for e in watch.restore_addon(local)["entries"]] == ["Torrentio", "Comet", "OpenSubtitles", "Local Files"]
    changed = watch.set_torrentio({"language": ["latino", "klingon"], "qualityfilter": ["cam"], "sort": "seeders", "limit": 5,
                                   "sizefilter": "10gb,2gb", "debridoptions": ["nodownloadlinks"]})
    assert changed["previous"]["sort"] == "seeders"  # para «Deshacer»
    assert watch.addon_list.urls()[0] == ("https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=cam|limit=5|"
                                          "sizefilter=10GB,2GB|debridoptions=nodownloadlinks|realdebrid=KEY/manifest.json")
    assert watch.set_addon_source("stremio")["source"] == "stremio"


def test_sin_cuenta_de_stremio_la_tv_usa_su_lista():
    """Corte S4: una TV nueva funciona sin Stremio; con la cuenta conectada (y sin haber elegido) sigue como antes."""
    linked = [False]
    lst = AddonList(Store(), key=lambda: "KEY", stremio=lambda: linked[0])
    assert lst.source == "own" and lst.urls()[0].startswith("https://torrentio.strem.fun/language=latino,spanish|")
    linked[0] = True
    assert lst.source == "stremio"
    lst.set_source("own")
    linked[0] = False
    assert lst.source == "own"


def test_la_lista_viaja_con_el_iphone_por_revision_y_sin_claves():
    """Corte S6 (design/addons-contract.json): GET con direcciones tapadas, PUT con su revisión (409 si es vieja, 422 si
    algo no cuadra), cada aparato solo cambia su propio prendido y nada con clave cruza antes de las llaves por aparato."""
    lst, _ = keyed()
    lst.import_from_stremio(brought())
    shared = lst.shared()
    assert shared["revision"] == 1 and all("KEY" not in str(a) for a in shared["addons"])
    torrentio = next(a for a in shared["addons"] if a.get("template") == "torrentio")
    assert "url" not in torrentio and torrentio["options"]["sort"] == "seeders"
    tpb = next(a for a in shared["addons"] if a.get("url") == TPB)
    with pytest.raises(addon_list.Conflict) as old:
        lst.receive({"base_revision": 0, "addons": shared["addons"]}, "iPhone")
    assert old.value.current["revision"] == 1
    changed = [dict(a) for a in shared["addons"]]
    changed.reverse()  # el iPhone cambió el orden,
    for a in changed:
        a["enabled"] = {**a["enabled"], "iphone-1": False, "tv": False}  # su propio prendido (y no el de la TV)
        if a.get("template") == "torrentio":
            a["options"] = {**a["options"], "limit": 5}
    saved = lst.receive({"base_revision": 1, "changed_by": "iPhone de Fernando", "addons": changed, "removed": []}, "iPhone")
    assert saved["revision"] == 2 and saved["changed_by"] == "iPhone de Fernando"
    assert [a["name"] for a in saved["addons"]][0] == "Local Files"
    assert saved["changed_at"].endswith("+00:00")  # ISO 8601, como el contrato
    assert all(a["enabled"].get("tv", True) for a in saved["addons"])  # la TV sigue igual
    assert lst.torrentio().options["limit"] == 5 and any("limit=5" in u for u in lst.urls())
    masked = {**changed[0], "id": "nuevo", "url": "https://x.strem.fun/realdebrid=•••/manifest.json"}
    for bad in [{**changed[0], "origin": "a mano"}, masked,
                {"id": "otro", "origin": "stremio", "name": "Con clave", "url": "https://y.strem.fun/realdebrid=ZZZ/manifest.json", "order": 0}]:
        with pytest.raises(ValueError):
            lst.receive({"base_revision": 2, "addons": [bad]}, "iPhone")
    fresh = {"id": "uuid-iphone", "origin": "stremio", "name": "Anime", "url": "https://anime.strem.fun/manifest.json", "order": 0}
    lst.receive({"base_revision": 2, "addons": [fresh], "removed": [tpb["id"]]}, "iPhone")
    names = [e.name for e in lst.entries()]
    assert "Anime" in names and "ThePirateBay+" not in names and "Torrentio" in names  # lo no mandado se queda


def test_comet_y_las_claves_escondidas_en_la_ruta():
    """Comet se arma con tu clave igual que el iPhone y una configuración opaca en la ruta (Comet, MediaFusion) se tapa entera:
    una dirección así no entra por el túnel antes de las llaves por aparato."""
    url = addon_list.comet_url("KEY")
    assert url.startswith("https://comet.elfhosted.com/") and "/" not in url.split("/")[3] and "+" not in url
    assert addon_list.masked(url) == "https://comet.elfhosted.com/•••/manifest.json"
    assert addon_list.masked("https://mediafusion.elfhosted.com/D-abcdefghijklmnopqrstuvwxyz0123456789ABCD/manifest.json").count("•••") == 1
    assert addon_list.masked(TPB) == TPB and addon_list.masked(TORRENTIO).endswith("realdebrid=•••/manifest.json")
    lst, _ = keyed()
    with pytest.raises(ValueError, match="escanear el código"):
        lst.receive({"base_revision": 0, "addons": [{"id": "x", "origin": "stremio", "name": "Comet viejo", "url": url, "order": 0}]}, "iPhone")


def test_local_files_no_se_quita_desde_el_iphone():
    """Fernando, 3 nov 2026: quitó Local Files sin querer en el iPhone y la TV lo borraba. Lo que vive en esta computadora
    se queda aunque otro aparato lo mande en «removed»; lo demás sí se quita."""
    lst = AddonList(Store())
    lst.import_from_stremio(brought())
    shared = lst.shared()
    local = next(e for e in lst.entries() if e.url == LOCAL)
    tpb = next(e for e in lst.entries() if e.url == TPB)
    rest = [a for a in shared["addons"] if a["id"] not in (local.id, tpb.id)]
    lst.receive({"base_revision": shared["revision"], "addons": rest, "removed": [local.id, tpb.id]}, device="iphone")
    urls = [e.url for e in lst.entries()]
    assert LOCAL in urls, "Local Files se queda en la TV"
    assert TPB not in urls, "lo que sí se quiso quitar, se quita"
    assert local.id not in lst.shared()["removed"]
