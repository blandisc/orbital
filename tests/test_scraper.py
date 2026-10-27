"""Scraper propio: validación de imágenes, búsqueda en TheGamesDB/Steam y «no me gusta»."""

import struct
from pathlib import Path

from orbital.library.emulators import pick_art
from orbital.library.media import MediaStore, good, image_size
from orbital.library.scraper import Scraper, Target, clean, similar


def png(w, h):
    head = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", w, h) + b"\x08\x02\x00\x00\x00"
    return head + b"\x00" * 4096


def jpeg(w, h):
    sof = b"\xff\xc0" + struct.pack(">H", 17) + b"\x08" + struct.pack(">HH", h, w) + b"\x03" + b"\x00" * 9
    return b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00" + b"\x00" * 9 + sof + b"\x00" * 4096


def test_reads_image_size_from_the_header(tmp_path):
    (tmp_path / "a.png").write_bytes(png(600, 900))
    (tmp_path / "b.jpg").write_bytes(jpeg(1920, 1080))
    assert image_size(tmp_path / "a.png") == (600, 900)
    assert image_size(tmp_path / "b.jpg") == (1920, 1080)


def test_a_screenshot_is_not_a_cover_but_can_be_a_background():
    assert not good("cover", (480, 272), "psp")  # la «portada» de Renegade Squadron era una captura
    assert good("cover", (600, 900), "psp")
    assert good("cover", (1530, 1370), "gba")  # las cajas de GBA son casi cuadradas
    assert not good("cover", (1530, 1370), "psp")
    assert good("hero", (1920, 1080))
    assert good("hero", (240, 160))  # captura de GBA: mejor que un fondo genérico (se ve en pixel art)
    assert not good("hero", (160, 144))  # casi cuadrada (Game Boy): no llena un fondo
    assert not good("hero", (1080, 1920))


def test_clean_titles_for_searching():
    assert clean("Simpsons, The - Hit & Run (USA, Japan)") == "The Simpsons - Hit & Run"
    assert clean("Mario Party Superstars[01006FE013472000][US][v0]") == "Mario Party Superstars"
    assert similar("Star Wars Battlefront - Renegade Squadron", "Star Wars Battlefront: Renegade Squadron") > 0.95


SEARCH = """<a href="./game.php?id=11"><div class="card"><div class="card-footer bg-secondary"><p>Star Wars Battlefront: Elite Squadron</p></div></a>
<a href="./game.php?id=12"><div class="card"><div class="card-footer bg-secondary"><p>Star Wars Battlefront: Renegade Squadron</p></div></a>"""
GAME = """<img src="https://cdn.thegamesdb.net/images/original/boxart/front/12-1.jpg">
<a href="https://cdn.thegamesdb.net/images/original/fanart/12-1.jpg"></a>
<a href="https://cdn.thegamesdb.net/images/original/fanart/12-2.jpg"></a>
<img src="https://cdn.thegamesdb.net/images/original/clearlogo/12.png">"""


class FakeHttp:
    def __init__(self, pages):
        self.pages = pages
        self.asked = []

    def get(self, url):
        self.asked.append(url)
        for part, body in self.pages.items():
            if part in url:
                return body
        return None


def scraper(tmp_path, pages):
    return Scraper(MediaStore(tmp_path / "media"), FakeHttp(pages))


def test_fetches_cover_hero_and_logo_from_thegamesdb(tmp_path):
    s = scraper(tmp_path, {
        "search.php": SEARCH.encode(), "game.php?id=12": GAME.encode(),
        "boxart/front/12-1.jpg": jpeg(600, 1000), "fanart/12-1.jpg": jpeg(1920, 1080), "clearlogo/12.png": png(800, 300),
    })
    target = Target("psp", "Star Wars Battlefront - Renegade Squadron (USA)", "Star Wars Battlefront: Renegade Squadron")
    saved = s.fetch(target)
    assert set(saved) == {"cover", "hero", "logo"}
    assert saved["cover"] == tmp_path / "media" / "psp" / "cover" / "Star Wars Battlefront - Renegade Squadron (USA).jpg"
    assert "platform_id%5B%5D=13" in next(u for u in s.http.asked if "search.php" in u)


def test_a_screenshot_offered_as_cover_is_skipped(tmp_path):
    s = scraper(tmp_path, {
        "search.php": SEARCH.encode(), "game.php?id=12": GAME.encode(), "boxart/front/12-1.jpg": jpeg(480, 272),
    })
    target = Target("psp", "Renegade", "Star Wars Battlefront: Renegade Squadron", ["cover"])
    assert s.fetch(target) == {}
    assert not list((tmp_path / "media").rglob("*.part"))


def test_wrong_game_is_not_taken(tmp_path):
    s = scraper(tmp_path, {"search.php": SEARCH.encode(), "game.php": GAME.encode()})
    assert s.fetch(Target("psp", "x", "Dante's Inferno")) == {}


def test_dislike_rejects_the_image_and_brings_the_next_one(tmp_path):
    s = scraper(tmp_path, {
        "search.php": SEARCH.encode(), "game.php?id=12": GAME.encode(),
        "fanart/12-1.jpg": jpeg(1920, 1080), "fanart/12-2.jpg": jpeg(2560, 1440),
    })
    target = Target("psp", "Renegade", "Star Wars Battlefront: Renegade Squadron", ["hero"])
    s.fetch(target)
    assert s.sources()["psp/Renegade/hero"].endswith("12-1.jpg")
    s.replace(target, "hero")
    assert s.sources()["psp/Renegade/hero"].endswith("12-2.jpg")
    assert image_size(s.store.path("psp", "Renegade", "hero")) == (2560, 1440)


def test_dislike_of_the_esde_image_with_nothing_else_keeps_it(tmp_path):
    # Antes se escondía y el juego quedaba sin imagen; ahora, sin otra que poner, se queda la de ES-DE.
    store = MediaStore(tmp_path / "media")
    s = Scraper(store, FakeHttp({}))
    assert s.replace(Target("switch", "Mario Party", "Mario Party", ["hero"]), "hero") is None
    assert not store.is_rejected("switch", "Mario Party", "hero", "esde")


class FakeEsde:
    def __init__(self, files):
        self.files = files

    def cover(self, system, rom):
        return self.files.get("cover")

    def hero(self, system, rom):
        return self.files.get("hero")

    def logo(self, system, rom):
        return self.files.get("logo")


def test_own_art_wins_and_bad_esde_art_is_ignored(tmp_path):
    shot = tmp_path / "shot.png"
    shot.write_bytes(png(480, 272))
    fan = tmp_path / "fan.jpg"
    fan.write_bytes(jpeg(1920, 1080))
    store = MediaStore(tmp_path / "media")
    own = store.target("psp", "Renegade", "logo", ".png")
    own.write_bytes(png(800, 300))
    art = pick_art(store, FakeEsde({"cover": shot, "hero": fan}), "psp", "Renegade", Path("Renegade.iso"), "psp")
    assert art == {"cover": None, "hero": str(fan), "logo": str(own)}
    store.reject("psp", "Renegade", "hero", "esde")
    assert pick_art(store, FakeEsde({"hero": fan}), "psp", "Renegade", Path("x"), "psp")["hero"] is None


def test_steam_only_when_the_name_really_matches(tmp_path):
    s = scraper(tmp_path, {
        "storesearch": b'{"items": [{"id": 202970, "name": "Call of Duty\xc2\xae: Black Ops II"}]}',
        "library_600x900_2x.jpg": jpeg(600, 900), "library_hero.jpg": jpeg(1920, 620), "logo.png": png(640, 360),
    })
    s.providers = [s.providers[2]]  # solo Steam
    saved = s.fetch(Target("xbox360", "Call of Duty - Black Ops II", "Call of Duty - Black Ops II"))
    assert set(saved) == {"cover", "hero", "logo"}
    assert s.fetch(Target("gc", "Pikmin", "Pikmin")) == {}


PAGE_WITH_META = GAME + """<h1>Star Wars Battlefront: Renegade Squadron</h1>
<p class="game-overview">Lead the Renegade Squadron.</p><p>Developer(s): <a href="#">Rebellion</a></p>
<p>Publishers(s): <a href="#">LucasArts</a></p><p>ReleaseDate: 2007-10-09</p><p>Players: 4</p><p>Genre(s): Action | Shooter</p>"""


def test_saves_the_game_sheet_and_uses_its_title_when_esde_only_has_the_file_name(tmp_path):
    from orbital.library.emulators import game_extra, game_title

    s = scraper(tmp_path, {"search.php": SEARCH.encode(), "game.php?id=12": PAGE_WITH_META.encode()})
    s.fetch(Target("psp", "Renegade", "Star Wars Battlefront - Renegade Squadron (USA)", ["meta"]))
    meta = s.store.meta("psp", "Renegade")
    assert meta["title"] == "Star Wars Battlefront: Renegade Squadron" and meta["genres"] == ["Action", "Shooter"]
    entry = Path("Star Wars Battlefront - Renegade Squadron (USA).iso")
    assert game_title("Star Wars Battlefront - Renegade Squadron", entry, meta) == meta["title"]
    assert game_title("Mi nombre", entry, meta) == "Mi nombre"  # lo que escribiste en ES-DE manda
    assert game_extra(meta) == {"description": "Lead the Renegade Squadron.", "genres": ["Action", "Shooter"],
                                "developer": "Rebellion", "year": "2007", "players": "4"}


def test_placeholders_pick_a_stable_option_per_game(tmp_path, monkeypatch):
    from orbital.library import media

    for name in ["hero-switch-1.jpg", "hero-switch-2.jpg", "hero-generic.jpg", "hero-switchx.jpg"]:
        (tmp_path / name).write_bytes(b"x")
    monkeypatch.setattr(media, "PLACEHOLDER_DIR", tmp_path)
    picks = {media.placeholder("hero", "switch", f"juego{i}") for i in range(20)}
    assert picks == {"/img/placeholders/hero-switch-1.jpg", "/img/placeholders/hero-switch-2.jpg"}
    assert media.placeholder("hero", "switch", "zelda") == media.placeholder("hero", "switch", "zelda")
    assert media.placeholder("hero", "psp", "x") == "/img/placeholders/hero-generic.jpg"


def test_official_art_wins_over_screenshots_from_any_source(tmp_path):
    page = GAME.replace("fanart/12-2.jpg", "screenshot/12-1.jpg")
    s = scraper(tmp_path, {
        "search.php": SEARCH.encode(), "game.php?id=12": page.encode(),
        "Named_Snaps": png(480, 272), "screenshot/12-1.jpg": jpeg(1280, 720), "fanart/12-1.jpg": jpeg(1920, 1080),
    })
    target = Target("psp", "Renegade", "Star Wars Battlefront: Renegade Squadron", ["hero"])
    s.fetch(target)
    assert s.sources()["psp/Renegade/hero"].endswith("fanart/12-1.jpg")  # libretro va primero, pero es captura


def test_without_fanart_a_screenshot_is_better_than_nothing(tmp_path):
    s = scraper(tmp_path, {"Named_Snaps": png(240, 160)})
    s.providers = [s.providers[0]]  # solo libretro
    saved = s.fetch(Target("gba", "Pokemon Pinball - Ruby & Sapphire (USA, Europe)", "Pokemon Pinball", ["hero"]))
    assert "hero" in saved and "Named_Snaps" in s.sources()["gba/Pokemon Pinball - Ruby & Sapphire (USA, Europe)/hero"]


def picture(w, h, flip=False, quality=90):
    """Una imagen JPEG de verdad (la misma escena con otra calidad o tamaño se «ve igual»)."""
    import io

    from PIL import Image, ImageDraw

    image = Image.new("RGB", (w, h), (30, 60, 120))
    draw = ImageDraw.Draw(image)
    box = (w * .55, h * .2, w * .95, h * .8) if not flip else (w * .05, h * .2, w * .45, h * .8)
    draw.rectangle(box, fill=(240, 200, 40))
    out = io.BytesIO()
    image.save(out, "JPEG", quality=quality)
    return out.getvalue()


def test_dislike_skips_the_same_picture_at_another_address(tmp_path):
    # Hit & Run está dos veces en TheGamesDB con el mismo dibujo: «Cambiar imagen» volvía a poner el mismo.
    s = scraper(tmp_path, {
        "search.php": SEARCH.encode(), "game.php?id=12": GAME.encode(),
        "fanart/12-1.jpg": picture(1920, 1080), "fanart/12-2.jpg": picture(1280, 720, quality=60),
    })
    target = Target("psp", "Renegade", "Star Wars Battlefront: Renegade Squadron", ["hero"])
    s.fetch(target)
    assert s.sources()["psp/Renegade/hero"].endswith("12-1.jpg")
    # 12-2 se ve igual que la rechazada: no se pone, y como no hay otra distinta, se queda la de antes.
    assert s.replace(target, "hero") is None and image_size(s.store.path("psp", "Renegade", "hero")) == (1920, 1080)
    # Una de verdad distinta sí entra.
    s.http.pages["fanart/12-2.jpg"] = picture(1920, 1080, flip=True)
    assert s.replace(target, "hero") is not None


DREAD = """<a href="./game.php?id=121672"><div class="card"><div class="card-footer bg-secondary"><p>Metroid Dread</p></div></a>
<a href="./game.php?id=87675"><div class="card"><div class="card-footer bg-secondary"><p>Metroid Dread</p></div></a>"""


def test_dislike_of_one_edition_brings_the_box_of_another(tmp_path):
    # Metroid Dread tiene cinco fichas en TheGamesDB. Solo se miraba una (la de México): al rechazar su caja
    # no quedaba otra y el juego se quedó sin portada para siempre.
    s = scraper(tmp_path, {
        "search.php": DREAD.encode(),
        "game.php?id=87675": b'<img src="https://cdn.thegamesdb.net/images/original/boxart/front/87675-1.jpg">',
        "game.php?id=121672": b'<img src="https://cdn.thegamesdb.net/images/original/boxart/front/121672-1.jpg">',
        "front/87675-1.jpg": picture(600, 900), "front/121672-1.jpg": picture(600, 900, flip=True),
    })
    target = Target("switch", "Metroid Dread [010093801237C000][v0]", "Metroid Dread", ["cover"])
    s.fetch(target)
    # Con el mismo nombre, primero la ficha más vieja (la principal), aunque la página la ponga después.
    assert s.sources()[f"switch/{target.key}/cover"].endswith("87675-1.jpg")
    assert s.replace(target, "cover") is not None
    assert s.sources()[f"switch/{target.key}/cover"].endswith("121672-1.jpg")


WIKI = """{"query": {"pages": {
 "1": {"index": 2, "title": "Pikmin", "description": "Nintendo video game series"},
 "2": {"index": 1, "title": "Pikmin (video game)", "description": "2001 video game",
       "original": {"source": "https://upload.wikimedia.org/wikipedia/en/1/13/Pikmin_cover_art.jpg?utm_source=x"}},
 "3": {"index": 3, "title": "Pikmin Bloom", "description": "2021 mobile game",
       "original": {"source": "https://upload.wikimedia.org/wikipedia/en/f/f2/Pikmin_Bloom.png"}}}}}"""


def test_wikipedia_box_as_last_resort_only_for_that_very_game(tmp_path):
    s = scraper(tmp_path, {"api.php": WIKI.encode(), "Pikmin_cover_art.jpg": picture(600, 900)})
    s.providers = [s.providers[3]]  # solo Wikipedia
    saved = s.fetch(Target("gc", "Pikmin (USA)", "Pikmin"))
    assert set(saved) == {"cover"}  # ni fondo ni logotipo: Wikipedia solo trae la caja
    assert s.sources()["gc/Pikmin (USA)/cover"] == "https://upload.wikimedia.org/wikipedia/en/1/13/Pikmin_cover_art.jpg"
    # Otro juego con nombre parecido no se lleva la caja de Pikmin.
    assert s.fetch(Target("gc", "Pikmin 2", "Pikmin 2", ["cover"])) == {}


def test_each_source_is_asked_only_for_what_is_missing(tmp_path):
    s = scraper(tmp_path, {"api.php": WIKI.encode()})
    s.providers = [s.providers[3]]
    s.store.target("gc", "Pikmin", "cover", ".jpg").write_bytes(picture(600, 900))
    s.fetch(Target("gc", "Pikmin", "Pikmin", ["cover", "hero"]))
    assert not any("api.php" in u for u in s.http.asked)  # ya tiene caja: no se le pregunta a Wikipedia


def test_dislike_with_nothing_else_keeps_the_picture_you_had(tmp_path):
    # Luigi's Mansion 3: «Cambiar imagen» no encontró otra y el juego se quedó sin portada.
    s = scraper(tmp_path, {"search.php": SEARCH.encode(), "game.php?id=12": GAME.encode(), "boxart/front/12-1.jpg": picture(600, 900)})
    target = Target("psp", "Renegade", "Star Wars Battlefront: Renegade Squadron", ["cover"])
    s.fetch(target)
    before = s.store.path("psp", "Renegade", "cover").read_bytes()
    assert s.replace(target, "cover") is None  # no hay otra
    assert s.store.path("psp", "Renegade", "cover").read_bytes() == before  # pero la tuya sigue ahí
    assert not s.store.rejected()  # y no queda rechazada


def test_choices_list_every_cover_and_background_and_you_can_pick_one(tmp_path):
    s = scraper(tmp_path, {"search.php": DREAD.encode(),
                           "game.php?id=87675": b'<img src="https://cdn.thegamesdb.net/images/original/boxart/front/87675-1.jpg">'
                                                b'<a href="https://cdn.thegamesdb.net/images/original/fanart/87675-1.jpg"></a>',
                           "game.php?id=121672": b'<img src="https://cdn.thegamesdb.net/images/original/boxart/front/121672-1.jpg">',
                           "front/121672-1.jpg": picture(600, 900)})
    target = Target("switch", "Dread", "Metroid Dread", ["cover"])
    found = s.choices(target)
    assert [o["url"].rsplit("/", 1)[1] for o in found["cover"]] == ["87675-1.jpg", "121672-1.jpg"]
    assert [o["url"].rsplit("/", 1)[1] for o in found["hero"]] == ["87675-1.jpg"]
    assert {o["source"] for o in found["cover"]} == {"TheGamesDB"}  # de dónde viene, para escoger la de tu región
    pick = found["cover"][1]["url"]
    s.store.reject("switch", "Dread", "cover", pick)  # aunque la hubieras rechazado antes, la puedes elegir
    assert s.choose(target, "cover", pick) is not None
    assert s.sources()["switch/Dread/cover"].endswith("121672-1.jpg")


def test_steamgriddb_only_with_your_key_and_only_for_that_very_game(tmp_path):
    from orbital.library.scraper import SteamGridDB

    pages = {"search/autocomplete": b'{"success": true, "data": [{"id": 7, "name": "Luigi Mansion 3"}]}',
             "grids/game/7": b'{"success": true, "data": [{"url": "https://cdn2.steamgriddb.com/grid/a.png"}]}',
             "heroes/game/7": b'{"success": true, "data": [{"url": "https://cdn2.steamgriddb.com/hero/b.png"}]}'}
    http = FakeHttp(pages)
    http.get = lambda url, headers=None: next((v for k, v in pages.items() if k in url), None)
    target = Target("switch", "Luigi", "Luigi's Mansion 3", ["cover", "hero"])
    assert SteamGridDB(http, lambda: "").candidates(target) == []  # sin clave, nada (ni una consulta)
    found = SteamGridDB(http, lambda: "clave").candidates(target)
    assert [(c.kind, c.url.rsplit("/", 1)[1]) for c in found] == [("cover", "a.png"), ("hero", "b.png")]
    assert SteamGridDB(http, lambda: "clave").candidates(Target("switch", "x", "Pikmin 4")) == []  # otro juego: no
