"""Complementos de Stremio: el protocolo sin depender de la app ni de la cuenta."""

from orbital.library import addons, cinemeta, streams
from orbital.library.addons import AddonRegistry, manifest_url, parse_manifest


def test_manifest_rules_by_resource_type_and_id_prefix():
    kitsu = parse_manifest({"name": "Kitsu", "types": ["series", "anime"], "idPrefixes": ["kitsu:"],
                            "resources": ["catalog", {"name": "meta", "types": ["anime"]}, "addon_catalog"]},
                           "https://kitsu/manifest.json")
    assert kitsu.resources == ["catalog", "meta"]  # lo que Orbital no usa se ignora
    assert kitsu.handles("meta", "anime", "kitsu:1") and not kitsu.handles("meta", "anime", "tt1")
    assert not kitsu.handles("meta", "series", "kitsu:1")  # el recurso trae sus propios tipos
    torrentio = parse_manifest({"resources": ["stream"]}, "https://t/manifest.json")
    assert torrentio.name == "Addon" and torrentio.handles("stream", "series", "tt1:1:2")  # sin reglas: todo


def test_odd_manifests_are_skipped():
    for manifest, url in [(None, "https://a/manifest.json"), ({"resources": ["stream"]}, "file:///C:/x"),
                          ({"resources": [["stream"]]}, "https://a/manifest.json"), ({"resources": "stream"}, "https://a")]:
        assert parse_manifest(manifest, url) is None


def test_manifest_url_accepts_what_you_would_paste():
    assert manifest_url("https://a.com/cfg") == "https://a.com/cfg/manifest.json"
    assert manifest_url("stremio://a.com/x/manifest.json") == "https://a.com/x/manifest.json"
    assert manifest_url("C:/addon/manifest.json") is None


def test_without_account_only_your_own_addons(monkeypatch):
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: {"name": "Mío", "resources": ["stream"]})
    registry = AddonRegistry(None, own=lambda: ["https://mio.com"])
    assert [a.name for a in registry.addons()] == ["Mío"]
    assert addons.clean_urls(["https://a", "https://a/manifest.json", 5, "ftp://x"]) == ["https://a/manifest.json"]


def test_account_first_then_local_without_repeats(monkeypatch):
    class Account:
        calls = 0

        def request(self, method, params):
            Account.calls += 1
            return {"addons": [{"transportUrl": "https://a/manifest.json", "manifest": {"name": "A", "resources": ["stream"]}}]}

    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: {"name": url, "resources": ["subtitles"]})
    key, own = ["k"], ["https://a", "https://b"]
    registry = AddonRegistry(Account(), auth=lambda: key[0], own=lambda: own)
    assert [a.url for a in registry.addons()] == ["https://a/manifest.json", "https://b/manifest.json"]
    registry.addons()
    assert Account.calls == 1  # en caché
    key[0] = None  # desconectaste la cuenta: se vuelve a armar, ya sin sus complementos
    assert [a.name for a in registry.addons()] == ["https://a/manifest.json", "https://b/manifest.json"]
    assert registry.serving("stream", "movie", "tt1") == []
    own.pop()  # quitaste uno: no se espera a que caduque la lista
    assert [a.name for a in registry.addons()] == ["https://a/manifest.json"]


def test_account_down_still_uses_local_but_alone_raises(monkeypatch):
    from orbital.library.stremio_api import StremioUnreachable

    class Down:
        def request(self, method, params):
            raise StremioUnreachable("sin internet")

    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=0: {"name": "Mío", "resources": ["stream"]})
    assert [a.name for a in AddonRegistry(Down(), auth=lambda: "k", own=lambda: ["https://mio"]).addons()] == ["Mío"]
    try:
        AddonRegistry(Down(), auth=lambda: "k").addons()
    except StremioUnreachable:
        pass
    else:
        raise AssertionError("sin complementos debe avisar del error de la cuenta")


def test_sources_only_asked_to_addons_that_know_the_id(monkeypatch):
    imdb = parse_manifest({"name": "IMDb", "resources": ["stream"], "idPrefixes": ["tt"]}, "https://i/manifest.json")
    anime = parse_manifest({"name": "Anime", "resources": ["stream"], "idPrefixes": ["kitsu:"]}, "https://k/manifest.json")
    asked = []
    monkeypatch.setattr(streams.StreamFinder, "addons", lambda self: [imdb, anime])
    monkeypatch.setattr(streams.StreamFinder, "_fetch", lambda self, addon, kind, vid: asked.append(addon.name) or [])
    streams.StreamFinder(None).find("series", "kitsu:12:3", streams.Preferences())
    assert asked == ["Anime"]


def test_imdb_metas_come_from_cinemeta_others_from_your_addons(monkeypatch):
    """El orden de tu cuenta no cambia las fichas de IMDb (su idioma lo pone Orbital); el anime sí
    va al complemento que lo conoce."""
    spanish = parse_manifest({"name": "TMDB", "resources": ["meta"], "idPrefixes": ["tt"]}, "https://tmdb/manifest.json")
    kitsu = parse_manifest({"name": "Kitsu", "resources": ["meta"], "idPrefixes": ["kitsu:"]}, "https://kitsu/manifest.json")
    registry = type("R", (), {"known": lambda self: [spanish, kitsu]})()
    monkeypatch.setattr(cinemeta.Cinemeta, "_get", lambda self, path, base=None: {"meta": {"id": "x", "name": base or "Cinemeta"}})
    client = cinemeta.Cinemeta(registry=registry)
    assert client.meta("movie", "tt1")["name"] == "Cinemeta"
    assert client.meta_sources("movie", "tt1") == [None, "https://tmdb"]  # TMDB, solo si Cinemeta falla
    assert client.meta("anime", "kitsu:1")["name"] == "https://kitsu"


def test_meta_falls_back_when_your_addon_fails(monkeypatch):
    other = parse_manifest({"name": "Roto", "resources": ["meta"]}, "https://roto/manifest.json")

    def get(self, path, base=None):
        if base:
            raise cinemeta.CinemetaError("caído")
        return {"meta": {"id": "tt1", "name": "Interstellar"}}

    monkeypatch.setattr(cinemeta.Cinemeta, "_get", get)
    client = cinemeta.Cinemeta(registry=type("R", (), {"known": lambda self: [other]})())
    assert client.meta("movie", "tt1")["name"] == "Interstellar"


def test_log_lines_never_carry_addon_keys():
    assert addons.redact("https://torrentio.strem.fun/realdebrid=SECRETO/manifest.json") == "torrentio.strem.fun"
