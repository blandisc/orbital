"""PA7-B: los sustos de la película marcados en la barra del reproductor de la TV (Where's The Jump), como el iPhone
(`JumpScaresTests`, la misma página de prueba)."""

import time
from types import SimpleNamespace

from orbital import player, player_ui, watch
from orbital.library import cinemeta, jumpscares
from orbital.player_ui import canvas
from orbital.watch.items import ScareMaps

PAGE = """
<a href="https://www.imdb.com/title/tt1591095/">IMDb</a><script>var t="00:00:01 – no";</script>
<p>00:13:35 <span class="spoilerdescription">– A ladder cracks while Dalton is climbing it.</span></p>
<p><strong>00:22:32 <span class="spoilerdescription">&#8211; A voice in the baby monitor yells &#8220;NOW&#8221;.</span></strong></p>
<p>01:03:12 <span class="spoilerdescription">– There is a cracking sound.</span></p>
"""


def test_parses_times_text_and_the_major_ones():
    scares = jumpscares.parse(PAGE)
    assert [s.time for s in scares] == [815, 1352, 3792]
    assert scares[1].text == "A voice in the baby monitor yells “NOW”."
    assert [s.major for s in scares] == [False, True, False]


def test_only_trusts_the_page_of_that_movie_and_builds_the_sites_slug():
    assert jumpscares.checked(PAGE, "tt1591095") is not None
    assert jumpscares.checked(PAGE, "tt0000001") is None
    assert jumpscares.page_url("Insidious: Chapter 2", 2013) == "https://wheresthejump.com/jump-scares-in-insidious-chapter-2-2013/"
    assert jumpscares.slugify("Don't Breathe") == "dont-breathe"


def test_tries_the_year_around_and_then_the_sites_search():
    asked = []
    pages = {"https://wheresthejump.com/?s=Insidious":
             '<a href="https://wheresthejump.com/jump-scares-in-insidious-2011/">x</a>'
             '<a href="https://wheresthejump.com/jump-scares-in-insidious-2023/">y</a>',
             "https://wheresthejump.com/jump-scares-in-insidious-2011/": PAGE}

    def get(url):
        asked.append(url)
        return pages.get(url)

    found = jumpscares.scares("Insidious", 2010, "tt1591095", get=get)
    assert [s.time for s in found] == [815, 1352, 3792]
    assert asked[:3] == [jumpscares.page_url("Insidious", y) for y in (2010, 2009, 2011)]
    assert jumpscares.scares("Nada", 2020, "tt1", get=lambda url: None) is None


def test_the_tv_asks_once_per_movie_and_keeps_the_map(tmp_path, monkeypatch):
    asked = []
    monkeypatch.setattr(jumpscares, "scares", lambda title, year, imdb: asked.append((title, year, imdb)) or jumpscares.parse(PAGE))
    fake = SimpleNamespace(scare_maps=ScareMaps(tmp_path / "sustos.json"),
                           cinemeta=SimpleNamespace(meta=lambda kind, imdb, localized=True: {"name": "Insidious", "year": "2010"}))
    meta = {"kind": "movie", "meta_id": "tt1591095", "title": "La noche del demonio"}
    first = watch.Watch._scares_for(fake, meta)
    assert first[1] == (1352.0, True, "A voice in the baby monitor yells “NOW”.")
    assert asked == [("Insidious", 2010, "tt1591095")]  # el nombre en inglés y el año, de Cinemeta
    fresh = SimpleNamespace(scare_maps=ScareMaps(tmp_path / "sustos.json"), cinemeta=None)
    assert watch.Watch._scares_for(fresh, meta) == first and len(asked) == 1  # guardado: sin volver a preguntar
    assert watch.Watch._scares_for(fake, {**meta, "kind": "series"}) == []  # una serie no


def test_without_cinemeta_it_uses_the_title_it_has(monkeypatch):
    monkeypatch.setattr(jumpscares, "scares", lambda title, year, imdb: None)
    fake = SimpleNamespace(scare_maps=ScareMaps(None), cinemeta=SimpleNamespace(
        meta=lambda *a, **k: (_ for _ in ()).throw(cinemeta.CinemetaError("x"))))
    assert watch.Watch._scares_for(fake, {"kind": "movie", "meta_id": "tt1", "title": "Algo"}) == []
    assert fake.scare_maps.get("tt1") is None  # sin página: se vuelve a buscar otro día


def test_the_bar_marks_major_minor_and_past_scares_and_names_the_one_youre_seeking_to():
    scares = [(815.0, False, "A ladder cracks"), (1352.0, True, "A voice yells"), (3792.0, False, "A cracking sound")]
    hud = player_ui.Hud("Insidious", position=1000, duration=6000, scares=scares)
    bar, _ = player_ui.progress_bar(hud)
    assert bar.count(canvas.DANGER) == 1 and bar.count(canvas.NEXT) == 1  # el fuerte en rojo, el leve que viene en ámbar
    assert len(bar.splitlines()) == len(player_ui.progress_bar(player_ui.Hud("Insidious", position=1000, duration=6000))[0].splitlines()) + 3
    assert player_ui.hud.scare_near(player_ui.Hud("X", position=1360, duration=6000, scares=scares)) == "Susto fuerte · A voice yells"
    assert player_ui.hud.scare_near(player_ui.Hud("X", position=2000, duration=6000, scares=scares)) == ""
    seeking = player_ui.hud_ass(player_ui.Hud("X", position=1360, duration=6000, scares=scares, seeking="+10 s"))
    assert "Susto fuerte · A voice yells" in seeking


def test_the_player_looks_them_up_for_a_movie_and_the_setting_turns_them_off():
    from test_player import make_player

    p, _ = make_player(duration=6000)
    p.scares_provider = lambda meta: [(815.0, True, "Boo")]
    movie = player.Segment({"kind": "movie", "meta_id": "tt1"}, "Insidious", "http://a")
    p.segment = movie
    p._find_scares(movie)
    deadline = time.monotonic() + 2
    while not movie.scares and time.monotonic() < deadline:
        time.sleep(.01)
    assert movie.scares == [(815.0, True, "Boo")]
    p.current.meta = movie.meta
    assert p._hud(p.current).scares == [(815.0, True, "Boo")]
    p.scares_provider = None  # Ajustes › «Marcar los sustos» apagado
    assert p._hud(p.current).scares == []
    episode = player.Segment({"kind": "series", "meta_id": "s"}, "X", "http://b")
    p.scares_provider = lambda meta: [(1.0, True, "no")]
    p._find_scares(episode)
    time.sleep(.05)
    assert episode.scares == []
