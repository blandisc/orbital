from orbital.library import geforcenow


def test_parse_route_and_clean_title():
    args = '--url-route="#?cmsId=100013311&launchSource=External&shortName=apex_legends"'
    assert geforcenow.parse_route(args)["cmsId"] == "100013311"
    assert geforcenow.parse_route("--otra-cosa") is None
    assert geforcenow.clean_title("Apex Legends - Shortcut") == "Apex Legends"
    assert geforcenow.clean_title("Fortnite (GeForce NOW)") == "Fortnite"
    assert geforcenow._split_args(args) == ["--url-route=#?cmsId=100013311&launchSource=External&shortName=apex_legends"]


def test_shortcuts_become_cloud_games(monkeypatch):
    monkeypatch.setattr(geforcenow, "read_shortcuts", lambda: [{
        "title": "Apex Legends - Shortcut", "target": r"C:\GFN\GeForceNOWStreamer.exe",
        "arguments": '--url-route="#?cmsId=100013311&launchSource=External"', "cms_id": "100013311"}])

    class Art:
        def appid(self, title):
            return 1172470 if title == "Apex Legends" else None

    [apex] = geforcenow.items(Art())
    assert apex.id == "gfn:100013311" and apex.title == "Apex Legends" and apex.category == "geforcenow"
    assert apex.argv == [r"C:\GFN\GeForceNOWStreamer.exe", "--url-route=#?cmsId=100013311&launchSource=External"]
    assert apex.image.endswith("/1172470/library_600x900.jpg") and apex.extra["logo"].endswith("/logo.png")


LIBRARY = {"data": {"panels": [{"id": "x", "name": "library", "sections": [
    {"title": "My Library", "items": [
        {"app": {"title": "Apex Legends™", "images": {"TV_BANNER": "https://img/b.jpg", "HERO_IMAGE": "https://img/h.jpg"},
                 "gfn": {"playabilityState": "PLAYABLE"},
                 "variants": [
                     {"id": "1", "shortName": "apex_epic", "appStore": "EPIC", "gfn": {"library": {"status": None}}},
                     {"id": "100013311", "shortName": "apex_steam", "appStore": "STEAM",
                      "gfn": {"library": {"status": "MANUAL", "selected": True, "playStatus": "PLAYABLE"}}},
                 ]}},
        {"app": {"title": "Juego que ya no está", "images": {}, "gfn": {"playabilityState": "NOT_PLAYABLE"},
                 "variants": [{"id": "9", "shortName": "x", "appStore": "STEAM",
                               "gfn": {"library": {"status": "MANUAL", "selected": True, "playStatus": "NOT_PLAYABLE"}}}]}},
    ]},
    {"title": "My Private Games", "items": []},
]}]}}


def test_library_from_gfn_cache(tmp_path):
    import json

    entry = tmp_path / "bf01" / "48c1"
    entry.mkdir(parents=True)
    head = b"0\r\x00https://apps.gxn.nvidia.com/graphql?requestType=panels/Library&x=1\x00\x00"
    (entry / "aaa_0").write_bytes(head + json.dumps(LIBRARY).encode() + b"\x00trailer")
    (entry / "bbb_0").write_bytes(b"otra cosa")
    games = geforcenow.read_library_cache(tmp_path)
    assert games == [{"title": "Apex Legends", "cms_id": "100013311", "short_name": "apex_steam", "store": "Steam",
                      "banner": "https://img/b.jpg", "hero": "https://img/h.jpg"}]  # solo lo jugable
    argv = geforcenow.library_argv(r"C:\GFN\GeForceNOWStreamer.exe", games[0])
    assert argv[1] == "--url-route=#?cmsId=100013311&launchSource=External&shortName=apex_steam&parentGameId="


def test_library_games_become_cards_without_duplicating_shortcuts(monkeypatch, tmp_path):
    monkeypatch.setattr(geforcenow, "install_dir", lambda: tmp_path)
    monkeypatch.setattr(geforcenow, "read_library_cache", lambda folder=None: [
        {"title": "Apex Legends", "cms_id": "100013311", "short_name": "a", "store": "Steam", "banner": "b", "hero": "h"},
        {"title": "Juego Raro", "cms_id": "5", "short_name": "r", "store": "EA app", "banner": "https://b", "hero": "https://h"}])
    monkeypatch.setattr(geforcenow, "read_shortcuts", lambda: [{
        "title": "Apex Legends", "target": "S.exe", "arguments": '--url-route="#?cmsId=100013311"', "cms_id": "100013311"}])

    class Art:
        def appid(self, title):
            return None

    apex, raro = geforcenow.items(Art())
    assert apex.argv[0] == "S.exe"  # el acceso directo manda
    assert raro.subtitle == "GeForce NOW · EA app" and raro.image == "https://b" and raro.hero == "https://h"
    assert raro.argv[0].endswith("GeForceNOWStreamer.exe")
