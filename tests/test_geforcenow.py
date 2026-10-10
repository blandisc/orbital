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
